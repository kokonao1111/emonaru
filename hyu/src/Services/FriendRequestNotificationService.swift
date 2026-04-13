import Foundation
import FirebaseFirestore

final class FriendRequestNotificationService {
    static let shared = FriendRequestNotificationService()
    
    private let db = Firestore.firestore()
    private let firestoreService = FirestoreService()
    private var listener: ListenerRegistration? // 自分が送った申請の監視
    private var receivedRequestListener: ListenerRegistration? // 自分宛ての申請の監視
    private var processedRequestIDs: Set<String> = []
    private let processedNotificationsKey = "processedFriendNotifications"
    
    private init() {
        // UserDefaultsから処理済みの通知IDを読み込む
        loadProcessedNotifications()
    }
    
    // 処理済みの通知IDをUserDefaultsから読み込む
    private func loadProcessedNotifications() {
        if let savedIDs = UserDefaults.standard.stringArray(forKey: processedNotificationsKey) {
            processedRequestIDs = Set(savedIDs)
        }
    }
    
    // 処理済みの通知IDをUserDefaultsに保存
    private func saveProcessedNotifications() {
        UserDefaults.standard.set(Array(processedRequestIDs), forKey: processedNotificationsKey)
    }
    
    // 友達申請の状態を監視開始
    func startMonitoring() {
        let currentUserID = UserService.shared.currentUserID
        
        print("🔔 友達申請の監視を開始: \(currentUserID)")
        
        // 自分が送った友達申請を監視（承認されたときの通知用）
        listener = db.collection("friendRequests")
            .whereField("fromUserID", isEqualTo: currentUserID)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ 友達申請監視エラー: \(error.localizedDescription)")
                    return
                }
                
                guard let snapshot = snapshot else {
                    print("⚠️ スナップショットがnilです")
                    return
                }
                
                // 変更されたドキュメントのみを処理
                for change in snapshot.documentChanges {
                    let document = change.document
                    
                    guard
                        let requestID = document.get("id") as? String,
                        let status = document.get("status") as? String
                    else {
                        continue
                    }
                    
                    print("📝 友達申請の変更を検知: \(requestID), ステータス: \(status), 変更タイプ: \(change.type.rawValue)")
                    
                    // 承認された申請を検知（新規作成または更新）
                    if status == "accepted" && !self.processedRequestIDs.contains(requestID) {
                        // 既に処理済みとしてマーク
                        self.processedRequestIDs.insert(requestID)
                        self.saveProcessedNotifications()
                        
                        print("✅ 友達申請が承認されました: \(requestID)")
                        
                        // 通知を送信（リクエストIDを渡す）
                        Task { @MainActor in
                            await self.sendNotification(requestID: requestID)
                        }
                    }
                }
            }
        
        // 自分宛ての友達申請を監視（申請を受けたときの通知用）
        receivedRequestListener = db.collection("friendRequests")
            .whereField("toUserID", isEqualTo: currentUserID)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ 受信した友達申請監視エラー: \(error.localizedDescription)")
                    return
                }
                
                guard let snapshot = snapshot else {
                    return
                }
                
                // 新しく追加された申請のみを処理
                for change in snapshot.documentChanges {
                    if change.type == .added {
                        let document = change.document
                        
                        guard
                            let requestID = document.get("id") as? String,
                            let fromUserID = document.get("fromUserID") as? String
                        else {
                            continue
                        }
                        
                        let notificationID = "received_friend_request_\(requestID)"
                        
                        // 既に処理済みの通知はスキップ
                        if self.processedRequestIDs.contains(notificationID) {
                            continue
                        }
                        
                        // 処理済みとしてマーク
                        self.processedRequestIDs.insert(notificationID)
                        self.saveProcessedNotifications()
                        
                        print("📨 新しい友達申請を受信: \(requestID), 送信者: \(fromUserID)")
                        
                        // 申請者の名前を取得
                        let currentUserID = UserService.shared.currentUserID
                        Task {
                            do {
                                // 申請者の名前を取得
                                let fromUserName = try? await FirestoreService().fetchUserName(userID: fromUserID)
                                let displayName = fromUserName ?? "ユーザー"
                                
                                // Firestoreに通知を保存（requestIDも保存）
                                try await FirestoreService().createFriendRequestNotification(
                                    requestID: requestID,
                                    fromUserID: fromUserID,
                                    toUserID: currentUserID,
                                    fromUserName: displayName
                                )
                                print("✅ Firestoreに友達申請通知を保存しました")
                                
                                // ローカル通知も送信（名前入り）
                                await MainActor.run {
                                    NotificationService.shared.sendFriendRequestNotification(fromUserName: displayName)
                                }
                            } catch {
                                print("❌ Firestoreへの友達申請通知保存に失敗: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
    }
    
    @MainActor
    private func sendNotification(requestID: String) async {
        // 友達申請のドキュメントから相手のユーザー名を取得
        do {
            let requestDoc = try await db.collection("friendRequests")
                .document(requestID)
                .getDocument()
            
            guard let toUserID = requestDoc.get("toUserID") as? String else {
                print("⚠️ toUserIDが取得できません")
                NotificationService.shared.sendFriendAcceptedNotification(requestID: requestID)
                return
            }
            
            let userDoc = try await db.collection("users")
                .document(toUserID)
                .getDocument()
            
            let userName = userDoc.get("name") as? String ?? "ユーザー"
            print("📝 友達承認通知送信: ユーザー名=\(userName)")
            
            // NotificationServiceが許可状態を確認してから送信するので、直接呼び出す
            NotificationService.shared.sendFriendAcceptedNotification(userName: userName, requestID: requestID)
        } catch {
            print("❌ ユーザー名の取得に失敗: \(error.localizedDescription)")
            // エラーの場合は名前なしで通知
            NotificationService.shared.sendFriendAcceptedNotification(requestID: requestID)
        }
    }
    
    // 監視を停止
    func stopMonitoring() {
        listener?.remove()
        listener = nil
        receivedRequestListener?.remove()
        receivedRequestListener = nil
        // メモリからは削除するが、UserDefaultsには残す
        processedRequestIDs.removeAll()
    }
}

import SwiftUI
import UserNotifications
import UIKit
import FirebaseFirestore
import CoreLocation

// ============================================
// NotificationsView: 通知一覧画面
// ============================================
// このファイルの役割：
// - アプリ内の通知を一覧表示
// - 友達申請の承認・拒否ボタン
// - コメント通知をタップして投稿に移動
// - 通知の既読管理と削除
// ============================================

struct NotificationsView: View {
    // データベース操作用
    private let firestoreService = FirestoreService()
    private let notificationUseCase = NotificationUseCase(
        notificationPort: IOSNotificationPort()
    )
    
    // 画面内で使う変数
    @State private var notifications: [AppNotification] = []  // 通知リスト
    @State private var isLoading = false  // 読み込み中フラグ
    @State private var errorMessage: String?  // エラーメッセージ
    @Environment(\.dismiss) private var dismiss  // 画面を閉じる機能
    
    var body: some View {
        NavigationView {
            List {
                if let errorMessage = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        if errorMessage.contains("index") || errorMessage.contains("インデックス") {
                            Text("Firestoreコンソールでインデックスを作成してください")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .listRowSeparator(.hidden)
                } else if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding()
                } else if notifications.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bell")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("通知はありません")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(notifications) { notification in
                        NotificationRow(notification: notification, onUpdate: {
                            // 通知が更新されたときにリストを再読み込み
                            Task {
                                await loadNotifications()
                            }
                        }, onDismiss: {
                            // 通知画面を閉じる
                            dismiss()
                        })
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    await deleteNotification(notification)
                                }
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("通知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .refreshable {
                await loadNotifications()
            }
            .task {
                await loadNotifications()
                // 通知画面を開いたときに、すべての通知を既読にしてバッジを0に設定
                await markAllNotificationsAsRead()
            }
            .onDisappear {
                // 画面を閉じたときに親画面に更新を通知（簡易実装）
                NotificationCenter.default.post(name: NSNotification.Name("NotificationsUpdated"), object: nil)
            }
        }
    }
    
    private func loadNotifications() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let firestoreNotifications = try await firestoreService.fetchAllNotifications()
            let systemNotifications = await NotificationService.shared.fetchDeliveredNotifications()
            
            print("🔔 Firestore通知: \(firestoreNotifications.count)件")
            print("🔔 システム通知: \(systemNotifications.count)件")
            
            // Firestore通知のみを使用（システム通知は除外して重複を防ぐ）
            await MainActor.run {
                notifications = firestoreNotifications.sorted { $0.createdAt > $1.createdAt }
                isLoading = false
                print("🔔 通知一覧を更新しました: \(notifications.count)件")
            }
        } catch {
            let errorDescription = error.localizedDescription
            print("❌ 通知の取得に失敗: \(errorDescription)")
            await MainActor.run {
                if errorDescription.contains("index") || errorDescription.contains("インデックス") {
                    errorMessage = "通知の取得に失敗しました。Firestoreのインデックスが必要です。エラーメッセージに表示されたURLからインデックスを作成してください。"
                } else {
                    errorMessage = "通知の取得に失敗しました: \(errorDescription)"
                }
                isLoading = false
            }
        }
    }
    
    // すべての通知を既読にしてバッジを0に設定
    private func markAllNotificationsAsRead() async {
        // 未読の通知をすべて既読にする
        for notification in notifications where !notification.isRead && notification.source == .firestore {
            do {
                try await firestoreService.markNotificationAsRead(notificationID: notification.id)
            } catch {
                print("通知の既読マークに失敗しました: \(error.localizedDescription)")
            }
        }

        await NotificationService.shared.clearDeliveredNotifications()
        
        // アプリアイコンのバッジを0に設定
        await notificationUseCase.syncBadge(unreadCount: 0)
        
        // 通知リストを更新
        await loadNotifications()
    }
    
    // 通知を削除
    private func deleteNotification(_ notification: AppNotification) async {
        do {
            // Firestore通知の場合は削除
            if notification.source == .firestore {
                try await firestoreService.deleteNotification(notificationID: notification.id)
                print("✅ 通知を削除しました: \(notification.id)")
            } else {
                // システム通知の場合は配信済み通知から削除
                NotificationService.shared.removeDeliveredNotification(identifier: notification.id)
                print("✅ システム通知を削除しました: \(notification.id)")
            }
            
            // リストを更新
            await loadNotifications()
            
            // バッジ数を更新
            await updateBadgeCount()
        } catch {
            print("❌ 通知の削除に失敗: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = "通知の削除に失敗しました: \(error.localizedDescription)"
            }
        }
    }
    
    // バッジ数を更新
    private func updateBadgeCount() async {
        do {
            let allNotifications = try await firestoreService.fetchAllNotifications()
            let systemNotifications = await NotificationService.shared.fetchDeliveredNotifications()
            let unreadCount = allNotifications.filter { !$0.isRead }.count + systemNotifications.count
            await notificationUseCase.syncBadge(unreadCount: unreadCount)
        } catch {
            print("❌ バッジ数の更新に失敗: \(error.localizedDescription)")
        }
    }
}

struct NotificationRow: View {
    let notification: AppNotification
    let onUpdate: () async -> Void
    let onDismiss: () -> Void
    
    private let firestoreService = FirestoreService()
    @State private var isRead: Bool
    @State private var isProcessing = false
    @State private var friendRequestID: String?
    @State private var selectedPost: EmotionPost?
    @State private var showPostDetail = false
    @State private var showPostNotFoundAlert = false
    
    init(notification: AppNotification, onUpdate: @escaping () async -> Void = {}, onDismiss: @escaping () -> Void = {}) {
        self.notification = notification
        self.onUpdate = onUpdate
        self.onDismiss = onDismiss
        _isRead = State(initialValue: notification.isRead)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // アイコン
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: iconName)
                        .foregroundColor(iconColor)
                        .font(.title3)
                }
                
                // 通知内容
                VStack(alignment: .leading, spacing: 4) {
                    Text(notification.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(notification.body)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true) // 縦方向に自動拡張
                    
                    Text(formatDate(notification.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 未読マーカー
                if !isRead {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                print("📍 通知をタップしました: type=\(notification.type.rawValue), relatedID=\(notification.relatedID ?? "nil")")
                
                // 友達申請通知の場合はタップで既読にしない（ボタンで操作するため）
                if notification.type != .friendRequest {
                    Task {
                        await markAsRead()
                        // 投稿関連の通知（コメント、応援、いいね）の場合は投稿詳細を表示
                        if notification.type == .comment || notification.type == .support || notification.type == .like {
                            print("📍 投稿関連通知をタップ - 投稿を読み込みます")
                            await loadAndShowPost()
                        }
                    }
                }
            }
            .allowsHitTesting(notification.type != .friendRequest)
            
            // 友達申請通知の場合、承認/拒否ボタンを表示
            if notification.type == .friendRequest {
                HStack(spacing: 12) {
                    Spacer()
                    
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.trailing, 8)
                    } else {
                        Button(action: {
                            Task {
                                await acceptFriendRequest()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("承認")
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.green)
                            .cornerRadius(20)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            Task {
                                await rejectFriendRequest()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                Text("拒否")
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.red)
                            .cornerRadius(20)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .task {
                    // 友達申請IDを取得
                    await loadFriendRequestID()
                }
            }
        }
        .sheet(isPresented: $showPostDetail) {
            if let post = selectedPost {
                NavigationView {
                    ScrollView {
                        VStack(spacing: 24) {
                            Text(postEmoji(for: post.level))
                                .font(.system(size: 80))
                            
                            Text(postLevelText(for: post.level))
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("レベル: \(post.level.rawValue)")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            
                            if let createdAt = formatPostDate(post.createdAt) {
                                Text(createdAt)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            // 投稿者のコメント表示
                            if let comment = post.comment, !comment.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("投稿者のコメント")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text(comment)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(12)
                                }
                                .padding(.horizontal)
                                .padding(.top, 8)
                            }
                        }
                        .padding()
                    }
                    .navigationTitle("投稿の詳細")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("閉じる") {
                                showPostDetail = false
                            }
                        }
                    }
                }
            }
        }
        .alert("投稿が見つかりません", isPresented: $showPostNotFoundAlert) {
            Button("OK", role: .cancel) {
                showPostNotFoundAlert = false
            }
        } message: {
            Text("この投稿は削除されたか、利用できなくなっています。")
        }
    }
    
    private var iconName: String {
        switch notification.type {
        case .friendRequest:
            return "person.badge.plus"
        case .friendAccepted:
            return "checkmark.circle.fill"
        case .support:
            return "heart.fill"
        case .comment:
            return "bubble.left.fill"
        case .like:
            return "hand.thumbsup.fill"
        case .view:
            return "eye.fill"
        case .mistCleared:
            return "cloud.sun.fill"
        case .missionCleared:
            return "checkmark.seal.fill"
        case .levelUp:
            return "arrow.up.circle.fill"
        case .gaugeFilled:
            return "gauge.high"
        case .dailyEmotionReminder:
            return "bell.fill"
        case .systemUpdate:
            return "megaphone.fill"
        case .announcement:
            return "envelope.fill"
        }
    }
    
    private var iconColor: Color {
        switch notification.type {
        case .friendRequest:
            return .blue
        case .friendAccepted:
            return .green
        case .support:
            return .orange
        case .comment:
            return .purple
        case .like:
            return .purple
        case .view:
            return .cyan
        case .mistCleared:
            return .teal
        case .missionCleared:
            return .green
        case .levelUp:
            return .indigo
        case .gaugeFilled:
            return .blue
        case .dailyEmotionReminder:
            return .yellow
        case .systemUpdate:
            return .orange
        case .announcement:
            return .purple
        }
    }
    
    private func markAsRead() async {
        if notification.source == .system {
            NotificationService.shared.removeDeliveredNotification(identifier: notification.id)
            await MainActor.run {
                isRead = true
                updateBadgeCount()
            }
            return
        }

        do {
            try await firestoreService.markNotificationAsRead(notificationID: notification.id)
            await MainActor.run {
                isRead = true
                // バッジの数を更新
                updateBadgeCount()
            }
        } catch {
            print("通知の既読マークに失敗しました: \(error.localizedDescription)")
        }
    }
    
    private func updateBadgeCount() {
        // 未読通知数を再計算してバッジを更新
        Task {
            do {
                let allNotifications = try await firestoreService.fetchAllNotifications()
                let systemNotifications = await NotificationService.shared.fetchDeliveredNotifications()
                let unreadCount = allNotifications.filter { !$0.isRead }.count + systemNotifications.count
                await MainActor.run {
                    if #available(iOS 17.0, *) {
                        UNUserNotificationCenter.current().setBadgeCount(unreadCount)
                    } else {
                        UIApplication.shared.applicationIconBadgeNumber = unreadCount
                    }
                }
            } catch {
                print("バッジ数の更新に失敗しました: \(error.localizedDescription)")
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // 友達申請IDを取得
    private func loadFriendRequestID() async {
        guard notification.type == .friendRequest,
              let fromUserID = notification.relatedID else {
            return
        }
        
        do {
            // 申請者のユーザーIDから保留中の申請IDを取得
            let currentUserID = UserService.shared.currentUserID
            let db = Firestore.firestore()
            let snapshot = try await db.collection("friendRequests")
                .whereField("fromUserID", isEqualTo: fromUserID)
                .whereField("toUserID", isEqualTo: currentUserID)
                .whereField("status", isEqualTo: "pending")
                .limit(to: 1)
                .getDocuments()
            
            if let doc = snapshot.documents.first,
               let requestID = doc.get("id") as? String {
                await MainActor.run {
                    friendRequestID = requestID
                }
            }
        } catch {
            print("❌ 友達申請IDの取得に失敗: \(error.localizedDescription)")
        }
    }
    
    // 友達申請を承認
    private func acceptFriendRequest() async {
        guard let requestID = friendRequestID else {
            print("⚠️ 友達申請IDが取得できていません")
            return
        }
        
        isProcessing = true
        
        do {
            print("🔔 友達申請を承認中: requestID=\(requestID)")
            try await firestoreService.acceptFriendRequest(requestID: requestID)
            print("✅ 友達申請の承認完了: requestID=\(requestID)")
            
            // 通知を送信
            NotificationService.shared.sendFriendAcceptedNotification(requestID: requestID)
            
            // この通知を直接削除（確実に削除するため）
            print("🗑️ 通知を直接削除中: notificationID=\(notification.id)")
            try await firestoreService.deleteNotification(notificationID: notification.id)
            print("✅ 通知を削除しました: notificationID=\(notification.id)")
            
            // Firestoreの削除が反映されるまで少し待つ
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3秒
            
            // 親の通知リストを更新
            print("🔔 通知リストを再読み込み中...")
            await onUpdate()
            print("✅ 通知リストの再読み込み完了")
        } catch {
            print("❌ 友達申請の承認に失敗: \(error.localizedDescription)")
        }
        
        isProcessing = false
    }
    
    // 友達申請を拒否
    private func rejectFriendRequest() async {
        guard let requestID = friendRequestID else {
            print("⚠️ 友達申請IDが取得できていません")
            return
        }
        
        isProcessing = true
        
        do {
            print("🔔 友達申請を拒否中: requestID=\(requestID)")
            try await firestoreService.rejectFriendRequest(requestID: requestID)
            print("✅ 友達申請の拒否完了: requestID=\(requestID)")
            
            // この通知を直接削除（確実に削除するため）
            print("🗑️ 通知を直接削除中: notificationID=\(notification.id)")
            try await firestoreService.deleteNotification(notificationID: notification.id)
            print("✅ 通知を削除しました: notificationID=\(notification.id)")
            
            // Firestoreの削除が反映されるまで少し待つ
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3秒
            
            // 親の通知リストを更新
            print("🔔 通知リストを再読み込み中...")
            await onUpdate()
            print("✅ 通知リストの再読み込み完了")
        } catch {
            print("❌ 友達申請の拒否に失敗: \(error.localizedDescription)")
        }
        
        isProcessing = false
    }
    
    // 投稿を読み込んで地図画面に表示
    private func loadAndShowPost() async {
        print("📍 loadAndShowPost開始: relatedID=\(notification.relatedID ?? "nil")")
        
        guard let postIDString = notification.relatedID else {
            print("⚠️ relatedIDがnil")
            await MainActor.run {
                showPostNotFoundAlert = true
            }
            return
        }
        
        print("📍 postIDString: \(postIDString)")
        
        guard let postID = UUID(uuidString: postIDString) else {
            print("⚠️ UUIDへの変換に失敗: \(postIDString)")
            await MainActor.run {
                showPostNotFoundAlert = true
            }
            return
        }
        
        print("📍 投稿を取得します: postID=\(postID.uuidString)")
        
        do {
            let post = try await firestoreService.fetchPostByID(postID: postID)
            print("✅ 投稿の取得に成功: \(post.id.uuidString)")
            
            // 投稿に位置情報があれば、地図画面に遷移
            if let latitude = post.latitude, let longitude = post.longitude {
                await MainActor.run {
                    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                    // 地図画面に遷移して投稿を表示
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenMapAtPost"),
                        object: ["coordinate": coordinate, "postID": postID]
                    )
                    print("✅ 地図画面への遷移通知を送信しました")
                }
                
                // 少し遅延してから通知一覧画面を閉じる
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                await MainActor.run {
                    onDismiss()
                }
            } else {
                print("⚠️ 投稿に位置情報がありません")
                // 位置情報がない場合はシートで表示
                await MainActor.run {
                    selectedPost = post
                    showPostDetail = true
                }
            }
        } catch {
            print("❌ 投稿の取得に失敗: \(error.localizedDescription)")
            // 投稿が見つからない場合は、アラートを表示
            await MainActor.run {
                showPostNotFoundAlert = true
            }
        }
    }
    
    // 投稿の日時をフォーマット
    private func formatPostDate(_ date: Date) -> String? {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
    
    // 投稿レベルの絵文字を取得
    private func postEmoji(for level: EmotionLevel) -> String {
        switch level {
        case .minusFive, .minusFour: return "😢"
        case .minusThree, .minusTwo: return "😔"
        case .minusOne: return "😐"
        case .zero: return "😊"
        case .plusOne: return "😄"
        case .plusTwo, .plusThree: return "😃"
        case .plusFour, .plusFive: return "🤩"
        }
    }
    
    // 投稿レベルのテキストを取得
    private func postLevelText(for level: EmotionLevel) -> String {
        switch level {
        case .minusFive: return "とても悲しい"
        case .minusFour: return "悲しい"
        case .minusThree: return "少し悲しい"
        case .minusTwo: return "やや悲しい"
        case .minusOne: return "少し低い"
        case .zero: return "普通"
        case .plusOne: return "少し高い"
        case .plusTwo: return "やや嬉しい"
        case .plusThree: return "少し嬉しい"
        case .plusFour: return "嬉しい"
        case .plusFive: return "とても嬉しい"
        }
    }
}


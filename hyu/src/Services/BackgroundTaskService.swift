import Foundation
import BackgroundTasks
import UIKit

final class BackgroundTaskService {
    static let shared = BackgroundTaskService()
    
    // タスクの識別子
    private let refreshTaskIdentifier = "com.nao.emotionapp.refresh"
    private let firestoreService = FirestoreService()
    
    private init() {}
    
    // バックグラウンドタスクを登録
    func registerBackgroundTasks() {
        // バックグラウンドでのデータ更新タスク
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskIdentifier, using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        
        print("🔄 バックグラウンドタスクを登録しました")
    }
    
    // アプリ更新タスクのスケジュール
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        
        // 最短15分後に実行（iOSが自動的に調整）
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ バックグラウンド更新をスケジュールしました（15分後）")
        } catch {
            print("❌ バックグラウンドタスクのスケジュールに失敗: \(error.localizedDescription)")
        }
    }
    
    // バックグラウンド更新の処理
    private func handleAppRefresh(task: BGAppRefreshTask) {
        print("🔄 バックグラウンド更新を開始...")
        
        // 次回の更新をスケジュール
        scheduleAppRefresh()
        
        // タスクのタイムアウト処理
        task.expirationHandler = {
            print("⏱️ バックグラウンドタスクがタイムアウトしました")
            task.setTaskCompleted(success: false)
        }
        
        // 実際の更新処理
        Task {
            do {
                // 1. タイムラインの新しい投稿をチェック
                let hasNewPosts = try await checkForNewPosts()
                
                // 2. 友達申請をチェック
                let hasNewRequests = try await checkForFriendRequests()
                
                // 3. 未読の応援をチェック
                let hasNewSupport = try await checkForNewSupport()
                
                // 4. 通知を送信
                if hasNewPosts {
                    await sendLocalNotification(title: "新しい投稿", body: "友達が新しい投稿をシェアしました")
                }
                
                if hasNewRequests {
                    await sendLocalNotification(title: "友達申請", body: "新しい友達申請が届いています")
                }
                
                if hasNewSupport {
                    await sendLocalNotification(title: "応援されました", body: "あなたの投稿に応援が届きました")
                }
                
                print("✅ バックグラウンド更新が完了しました")
                task.setTaskCompleted(success: true)
                
            } catch {
                print("❌ バックグラウンド更新に失敗: \(error.localizedDescription)")
                task.setTaskCompleted(success: false)
            }
        }
    }
    
    // 新しい投稿をチェック
    private func checkForNewPosts() async throws -> Bool {
        // 最後にチェックした時刻を取得
        let lastCheck = UserDefaults.standard.object(forKey: "lastBackgroundCheck") as? Date ?? Date.distantPast
        
        // Firestoreから新しい投稿を取得（友達の投稿のみ、過去6時間）
        let posts = try await firestoreService.fetchRecentEmotions(lastHours: 6, includeOnlyFriends: true)
        let newPosts = posts.filter { $0.createdAt > lastCheck }
        
        // チェック時刻を更新
        UserDefaults.standard.set(Date(), forKey: "lastBackgroundCheck")
        
        return !newPosts.isEmpty
    }
    
    // 友達申請をチェック
    private func checkForFriendRequests() async throws -> Bool {
        let currentUserID = UserService.shared.currentUserID
        let lastCheck = UserDefaults.standard.object(forKey: "lastFriendRequestCheck") as? Date ?? Date.distantPast
        
        // 新しい友達申請があるかチェック（Firestoreから取得）
        // ここでは簡易的に実装
        UserDefaults.standard.set(Date(), forKey: "lastFriendRequestCheck")
        
        return false // 実際の実装ではFirestoreをチェック
    }
    
    // 新しい応援をチェック
    private func checkForNewSupport() async throws -> Bool {
        let lastCheck = UserDefaults.standard.object(forKey: "lastSupportCheck") as? Date ?? Date.distantPast
        
        // 新しい応援があるかチェック
        UserDefaults.standard.set(Date(), forKey: "lastSupportCheck")
        
        return false // 実際の実装ではFirestoreをチェック
    }
    
    // ローカル通知を送信
    @MainActor
    private func sendLocalNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = 1
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "background_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("✅ バックグラウンド通知を送信しました: \(title)")
        } catch {
            print("❌ バックグラウンド通知の送信に失敗: \(error.localizedDescription)")
        }
    }
}

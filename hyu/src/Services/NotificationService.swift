import Foundation
import UserNotifications

// ============================================
// NotificationService: 通知送信管理
// ============================================
// このファイルの役割：
// - ローカル通知を送信（スマホに通知を表示）
// - 応援、友達申請、モヤ浄化などの通知
// - 1日2回のランダム通知（午前・午後）
// - 通知の権限管理
// ============================================

final class NotificationService {
    // アプリ全体で1つだけ使う（shared = 共有インスタンス）
    static let shared = NotificationService()
    private let firestoreService = FirestoreService()
    
    // 外部から直接作れないようにする
    private init() {}
    
    // ============================================
    // 通知の権限をリクエスト（アプリ起動時に呼ぶ）
    // ============================================
    func requestAuthorization() async {
        do {
            // ユーザーに通知の許可を求める
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            print("🔔 通知の許可状態: \(granted ? "許可" : "拒否")")
        } catch {
            print("❌ 通知の許可リクエストに失敗しました: \(error.localizedDescription)")
        }
    }
    
    // ============================================
    // 通知の許可状態を確認してから送信（内部用）
    // ============================================
    @MainActor
    private func ensureAuthorizationAndSend(_ sendBlock: @escaping () -> Void) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        if settings.authorizationStatus == .authorized {
            // 既に許可されている場合は即座に送信
            sendBlock()
        } else if settings.authorizationStatus == .notDetermined {
            // まだユーザーが選んでいない場合は許可をリクエスト
            let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted == true {
                sendBlock()
            } else {
                print("⚠️ 通知の許可が拒否されました")
            }
        } else {
            // 拒否されている場合でも送信を試みる（後で設定変更される可能性）
            print("⚠️ 通知の許可が拒否されていますが、送信を試みます")
            sendBlock()
        }
    }
    
    // ============================================
    // 応援通知を即座に送信
    // ============================================
    func sendImmediateSupportNotification(isHappy: Bool, postID: String? = nil, toUserID: String? = nil, shouldSaveToFirestore: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = isHappy ? "共感されました" : "応援されました"
        
        if isHappy {
            content.body = "誰かがあなたの投稿に共感しました"
        } else {
            content.body = "誰かがあなたの投稿を応援しました"
        }
        
        content.sound = .default
        content.badge = 1
        content.userInfo = [
            "type": "support"
        ]
        
        // Firestoreにも通知を保存（プロフィールの通知一覧に表示されるように）
        // 注意: FirestoreService.addSupportで既に保存されている場合は重複を避ける
        if shouldSaveToFirestore, let toUserID = toUserID, let postID = postID {
            Task {
                do {
                    try await firestoreService.createNotification(
                        type: .support,
                        title: content.title,
                        body: content.body,
                        relatedID: postID,
                        toUserID: toUserID
                    )
                    print("✅ Firestoreに応援通知を保存しました")
                } catch {
                    print("❌ Firestoreへの応援通知保存に失敗: \(error.localizedDescription)")
                }
            }
        }
        
        // 即座に通知を表示（0.1秒後）
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "support_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        Task { @MainActor in
            await ensureAuthorizationAndSend {
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("❌ 応援通知の送信に失敗しました: \(error.localizedDescription)")
                    } else {
                        print("✅ 応援通知を送信しました")
                    }
                }
            }
        }
    }
    
    // 友達申請の通知を送信
    func sendFriendRequestNotification(fromUserName: String = "ユーザー") {
        let content = UNMutableNotificationContent()
        content.title = "友達申請"
        content.body = "\(fromUserName)さんが友達になりたがっています"
        content.sound = .default
        content.badge = 1
        content.userInfo = [
            "type": "friend_request"
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "friend_request_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        Task { @MainActor in
            await ensureAuthorizationAndSend {
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("❌ 友達申請通知の送信に失敗しました: \(error.localizedDescription)")
                    } else {
                        print("✅ 友達申請通知を送信しました")
                    }
                }
            }
        }
    }
    
    // 友達承認の通知を送信
    func sendFriendAcceptedNotification(userName: String? = nil, requestID: String? = nil) {
        let content = UNMutableNotificationContent()
        if let userName = userName {
            content.title = "\(userName)さんと友達になりました"
            content.body = "プロフィールから確認できます"
        } else {
            content.title = "友達になりました"
            content.body = "プロフィールから確認できます"
        }
        content.sound = .default
        content.badge = 1
        content.userInfo = [
            "type": "friend_accepted"
        ]
        
        // リクエストIDがある場合は固定の識別子を使用（重複防止）
        // ない場合はUUIDを使用（後方互換性のため）
        let identifier: String
        if let requestID = requestID {
            identifier = "friend_accepted_\(requestID)"
        } else {
            identifier = "friend_accepted_\(UUID().uuidString)"
        }
        
        // 既に同じ識別子の通知が存在するか確認
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let existingRequest = requests.first { $0.identifier == identifier }
            if existingRequest != nil {
                print("⚠️ 既に同じ通知が存在するため、スキップします: \(identifier)")
                return
            }
            
            // フォアグラウンドでも通知を表示する
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )
            
            Task { @MainActor in
                await self.ensureAuthorizationAndSend {
                    center.add(request) { error in
                        if let error = error {
                            print("❌ 友達承認通知の送信に失敗しました: \(error.localizedDescription)")
                        } else {
                            print("✅ 友達承認通知を送信しました: \(identifier)")
                        }
                    }
                }
            }
        }
    }

    // モヤイベント発生通知を送信
    func sendMistEventNotification(prefectureName: String, latitude: Double, longitude: Double) {
        let content = UNMutableNotificationContent()
        content.title = "モヤイベント発生！"
        content.body = "\(prefectureName)のとこにイベント発生！"
        content.sound = .default
        content.badge = 1
        content.userInfo = [
            "type": "mist_event",
            "lat": latitude,
            "lon": longitude,
            "prefecture": prefectureName
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "mist_event_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        Task { @MainActor in
            await ensureAuthorizationAndSend {
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("❌ モヤイベント通知の送信に失敗しました: \(error.localizedDescription)")
                    } else {
                        print("✅ モヤイベント通知を送信しました")
                    }
                }
            }
        }
    }

    // モヤ浄化完了通知を送信
    func sendMistClearedNotification(prefectureName: String) {
        let content = UNMutableNotificationContent()
        content.title = "モヤを倒しました！"
        content.body = "\(prefectureName)のモヤを浄化しました"
        content.sound = .default
        content.badge = 1
        content.userInfo = ["type": "mist_cleared"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "mist_cleared_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        Task { @MainActor in
            await ensureAuthorizationAndSend {
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("❌ モヤ浄化通知の送信に失敗しました: \(error.localizedDescription)")
                    } else {
                        print("✅ モヤ浄化通知を送信しました")
                    }
                }
            }
        }
    }
    
    // ランダムな時間に「今のあなたの感情を教えて」通知をスケジュール
    func scheduleDailyEmotionReminder() {
        let center = UNUserNotificationCenter.current()
        
        // 既存の通知を全て削除（ランダム通知用）
        center.getPendingNotificationRequests { requests in
            let beRealIdentifiers = requests
                .filter { $0.identifier.starts(with: "bereal_reminder_") }
                .map { $0.identifier }
            center.removePendingNotificationRequests(withIdentifiers: beRealIdentifiers)
        }
        
        print("🎲 ランダム感情リマインダーをスケジュール（ランダムな時間）")
        
        // 今日から7日分の通知を事前にスケジュール
        let calendar = Calendar.current
        let now = Date()
        
        Task { @MainActor in
            await ensureAuthorizationAndSend {
                for dayOffset in 0..<7 {
                    guard let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else {
                        continue
                    }
                    
                    // 午前のランダムな時間（9:00〜12:00）
                    let morningHour = Int.random(in: 9...11)
                    let morningMinute = Int.random(in: 0...59)
                    
                    // 午後のランダムな時間（15:00〜20:00）
                    let eveningHour = Int.random(in: 15...19)
                    let eveningMinute = Int.random(in: 0...59)
                    
                    // 午前の通知
                    self.scheduleEmotionNotification(
                        center: center,
                        date: targetDate,
                        hour: morningHour,
                        minute: morningMinute,
                        identifier: "bereal_reminder_\(dayOffset)_morning"
                    )
                    
                    // 午後の通知
                    self.scheduleEmotionNotification(
                        center: center,
                        date: targetDate,
                        hour: eveningHour,
                        minute: eveningMinute,
                        identifier: "bereal_reminder_\(dayOffset)_evening"
                    )
                    
                    if dayOffset == 0 {
                        print("📅 今日の通知: 午前 \(morningHour):\(String(format: "%02d", morningMinute)), 午後 \(eveningHour):\(String(format: "%02d", eveningMinute))")
                    }
                }
                
                print("✅ 7日分のランダム通知をスケジュールしました")
            }
        }
    }
    
    // ランダム通知が少なくなったら再スケジュール
    func rescheduleBeRealNotificationsIfNeeded() {
        let center = UNUserNotificationCenter.current()
        
        center.getPendingNotificationRequests { requests in
            let beRealRequests = requests.filter { $0.identifier.starts(with: "bereal_reminder_") }
            
            // 通知が3日分（6個）未満になったら再スケジュール
            if beRealRequests.count < 6 {
                print("🔄 ランダム通知が少なくなったため、再スケジュールします（現在: \(beRealRequests.count)個）")
                self.scheduleDailyEmotionReminder()
            } else {
                print("✅ ランダム通知は十分にスケジュール済みです（\(beRealRequests.count)個）")
            }
        }
    }
    
    // ランダム通知を個別にスケジュール
    private func scheduleEmotionNotification(center: UNUserNotificationCenter, date: Date, hour: Int, minute: Int, identifier: String) {
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        // ランダムなメッセージ
        let messages = [
            ("⏰ 今の感情を記録しよう", "今のあなたの感情を1分以内にシェアしよう！"),
            ("📸 感情を記録する時間です", "あなたの今の気持ちは？1分以内に投稿！"),
            ("💭 今の気分は？", "リアルな感情を今すぐシェアしよう"),
            ("🎯 感情を投稿しよう！", "1分以内に今の感情を教えてください"),
            ("⚡️ 急げ！", "今の気持ちをすぐに投稿しよう！"),
        ]
        
        let randomMessage = messages.randomElement() ?? messages[0]
        
        let content = UNMutableNotificationContent()
        content.title = randomMessage.0
        content.body = randomMessage.1
        content.sound = .default
        content.badge = 1
        content.userInfo = [
            "type": "daily_emotion_reminder",
            "bereal_style": true,
            "scheduled_time": "\(hour):\(minute)"
        ]
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        center.add(request) { error in
            if let error = error {
                print("❌ ランダム通知のスケジュールに失敗: \(error.localizedDescription)")
            }
        }
    }

    // 手動でランダム通知を即座に送信（管理者用）
    func sendManualEmotionNotification() {
        // 通知を送信した時刻を記録（1分以内に投稿すればボーナス）
        UserService.shared.recordNotificationReceived()
        
        let messages = [
            ("⏰ 今の感情を記録しよう", "今のあなたの感情を1分以内にシェアしよう！"),
            ("📸 感情を記録する時間です", "あなたの今の気持ちは？1分以内に投稿！"),
            ("💭 今の気分は？", "リアルな感情を今すぐシェアしよう"),
            ("🎯 感情を投稿しよう！", "1分以内に今の感情を教えてください"),
            ("⚡️ 急げ！", "今の気持ちをすぐに投稿しよう！"),
        ]
        
        let randomMessage = messages.randomElement() ?? messages[0]
        
        let content = UNMutableNotificationContent()
        content.title = randomMessage.0
        content.body = randomMessage.1
        content.sound = .default
        content.badge = 1
        content.userInfo = [
            "type": "daily_emotion_reminder",
            "bereal_style": true,
            "manual": true
        ]
        
        // Firestoreにも保存
        let currentUserID = UserService.shared.currentUserID
        Task {
            do {
                try await firestoreService.createNotification(
                    type: .dailyEmotionReminder,
                    title: content.title,
                    body: content.body,
                    relatedID: nil,
                    toUserID: currentUserID
                )
                print("✅ ランダム通知をFirestoreに保存しました")
            } catch {
                print("❌ Firestoreへの通知保存に失敗: \(error.localizedDescription)")
            }
        }
        
        // 即座に通知を表示（0.1秒後）
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "manual_bereal_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        Task { @MainActor in
            await ensureAuthorizationAndSend {
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("❌ 手動ランダム通知の送信に失敗しました: \(error.localizedDescription)")
                    } else {
                        print("✅ 手動ランダム通知を送信しました")
                    }
                }
            }
        }
    }
    
    // 最近届いた感情リマインダーがあれば投稿タブへ遷移
    func handleRecentDailyReminder(openPostTab: @escaping () -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notifications in
            let now = Date()
            let recentNotification = notifications
                .filter { notification in
                    let userInfo = notification.request.content.userInfo
                    return (userInfo["type"] as? String) == "daily_emotion_reminder"
                }
                .max(by: { $0.date < $1.date })

            guard let notification = recentNotification else { return }
            guard now.timeIntervalSince(notification.date) <= 60.0 else { return }

            // Firestoreに通知を保存（まだ保存されていない場合）
            let content = notification.request.content
            let currentUserID = UserService.shared.currentUserID
            Task {
                do {
                    try await self.firestoreService.createNotification(
                        type: .dailyEmotionReminder,
                        title: content.title,
                        body: content.body,
                        relatedID: notification.request.identifier,
                        toUserID: currentUserID
                    )
                    print("✅ 配信されたランダム通知をFirestoreに保存しました")
                } catch {
                    print("❌ Firestoreへの通知保存に失敗: \(error.localizedDescription)")
                }
            }

            UserService.shared.recordNotificationReceived(at: notification.date)
            DispatchQueue.main.async {
                openPostTab()
            }
            center.removeDeliveredNotifications(withIdentifiers: [notification.request.identifier])
        }
    }

    func fetchDeliveredNotifications() async -> [AppNotification] {
        let center = UNUserNotificationCenter.current()
        return await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                let mapped = notifications.map { notification in
                    let content = notification.request.content
                    let userInfo = content.userInfo
                    let type = self.resolveNotificationType(userInfo: userInfo, identifier: notification.request.identifier)
                    let relatedID = userInfo["relatedID"] as? String
                        ?? userInfo["postID"] as? String
                        ?? userInfo["fromUserID"] as? String
                        ?? userInfo["userID"] as? String

                    return AppNotification(
                        id: notification.request.identifier,
                        type: type,
                        title: content.title.isEmpty ? "通知" : content.title,
                        body: content.body,
                        createdAt: notification.date,
                        isRead: false,
                        relatedID: relatedID,
                        source: .system
                    )
                }
                continuation.resume(returning: mapped)
            }
        }
    }

    func clearDeliveredNotifications() async {
        let center = UNUserNotificationCenter.current()
        let identifiers = await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications.map { $0.request.identifier })
            }
        }
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func removeDeliveredNotification(identifier: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private func resolveNotificationType(userInfo: [AnyHashable: Any], identifier: String) -> NotificationType {
        if let typeString = userInfo["type"] as? String,
           let type = NotificationType(rawValue: typeString) {
            return type
        }

        if identifier.hasPrefix("friend_request_"),
           userInfo["fromUserID"] != nil || userInfo["relatedID"] != nil {
            return .friendRequest
        }
        if identifier.hasPrefix("friend_accepted_") { return .friendAccepted }
        if identifier.hasPrefix("support_") { return .support }
        if identifier.hasPrefix("like_") { return .like }
        if identifier.hasPrefix("view_") { return .view }
        if identifier.hasPrefix("mission_") { return .missionCleared }
        if identifier.hasPrefix("level_up_") { return .levelUp }
        if identifier.hasPrefix("gauge_filled_") { return .gaugeFilled }
        if identifier.hasPrefix("bereal_reminder_") || identifier.hasPrefix("manual_bereal_") {
            return .dailyEmotionReminder
        }

        return .view
    }
}

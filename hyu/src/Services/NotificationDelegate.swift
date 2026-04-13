import Foundation
import UserNotifications
import CoreLocation

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    
    private override init() {
        super.init()
    }
    
    // フォアグラウンドでも通知を表示
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 毎日の感情リマインダーの場合は時刻を記録
        let userInfo = notification.request.content.userInfo
        if let type = userInfo["type"] as? String, type == "daily_emotion_reminder" {
            UserService.shared.recordNotificationReceived()
        }
        
        // フォアグラウンドでも通知を表示
        completionHandler([.banner, .sound, .badge])
    }
    
    // 通知がタップされたときの処理
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        // 毎日の感情リマインダーの場合は投稿画面に遷移する通知を送信
        if let type = userInfo["type"] as? String, type == "daily_emotion_reminder" {
            // 通知が来た時刻を記録（バックグラウンドで通知が来た場合）
            UserService.shared.recordNotificationReceived()
        }

        // モヤイベント通知の場合は地図タブに遷移して該当地点を表示
        if let type = userInfo["type"] as? String, type == "mist_event",
           let lat = userInfo["lat"] as? Double,
           let lon = userInfo["lon"] as? Double {
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            NotificationCenter.default.post(name: NSNotification.Name("OpenMapAtLocation"), object: coordinate)
        }
        
        // 友達申請通知の場合は友達リクエスト画面に遷移
        if let type = userInfo["type"] as? String, type == "friend_request" {
            NotificationCenter.default.post(name: NSNotification.Name("OpenFriendRequests"), object: nil)
        }
        
        // 応援通知の場合はプロフィール画面に遷移
        if let type = userInfo["type"] as? String, type == "support" {
            NotificationCenter.default.post(name: NSNotification.Name("OpenProfile"), object: nil)
        }
        
        // 観光スポット到着通知の場合は地図タブに遷移
        if let type = userInfo["type"] as? String, type == "spot_arrival" {
            NotificationCenter.default.post(name: NSNotification.Name("OpenMapTab"), object: nil)
        }
        
        completionHandler()
    }
}

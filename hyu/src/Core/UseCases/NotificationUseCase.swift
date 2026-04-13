import Foundation

final class NotificationUseCase {
    private let notificationPort: NotificationPort

    init(notificationPort: NotificationPort) {
        self.notificationPort = notificationPort
    }

    func syncBadge(unreadCount: Int) async {
        await notificationPort.refreshBadge(unreadCount: unreadCount)
    }

    func requestPermissionIfNeeded() async {
        await notificationPort.requestPermissionIfNeeded()
    }
}

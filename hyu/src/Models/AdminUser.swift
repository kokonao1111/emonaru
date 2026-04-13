import Foundation

struct AdminUser: Identifiable, Hashable {
    let id: String
    var isPublicAccount: Bool
    var isFrozen: Bool
    var isBanned: Bool
    var bannedDeviceCount: Int
    var grantedPostLimitBonusTotal: Int
    let updatedAt: Date?
    let userName: String?
    let fcmToken: String?
}

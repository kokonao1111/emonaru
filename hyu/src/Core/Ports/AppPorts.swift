import Foundation

struct CoreCoordinate: Equatable, Codable {
    let latitude: Double
    let longitude: Double
}

struct CoreAuthUser {
    let username: String
    let userID: String
}

protocol AuthRepository {
    func signIn(username: String, password: String) async throws -> CoreAuthUser
    func signUp(username: String, password: String, age: Int, gender: String) async throws -> CoreAuthUser
    func signOut() async
    func deleteCurrentAccount() async throws
    func currentUser() async -> CoreAuthUser?
}

protocol UserProfileRepository {
    func loadUserProfile(userID: String) async throws
    func saveCurrentUserProfile() async throws
    func updateUserName(_ name: String) async
    func updatePublicFlag(_ isPublic: Bool) async
    func updateHomePrefecture(_ prefectureName: String) async
}

protocol PostRepository {
    func postEmotion(
        level: Int,
        coordinate: CoreCoordinate?,
        comment: String?,
        isPublicPost: Bool,
        isMistCleanup: Bool
    ) async throws -> Bool
}

protocol TimelineRepository {
    func fetchRecentPosts(lastHours: Int, friendsOnly: Bool) async throws -> [EmotionPost]
    func fetchMyPosts() async throws -> [EmotionPost]
}

protocol MistEventRepository {
    func fetchActiveMistEvents() async throws -> [MistEvent]
}

protocol LocationPort {
    func currentCoordinate() async -> CoreCoordinate?
}

protocol NotificationPort {
    func requestPermissionIfNeeded() async
    func refreshBadge(unreadCount: Int) async
}

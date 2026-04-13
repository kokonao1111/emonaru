import Foundation

enum AndroidAdapterError: LocalizedError {
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let feature):
            return "Android adapter not implemented yet: \(feature)"
        }
    }
}

// Skip/Android 実装の受け皿。現時点ではiOSビルドを壊さないようにスタブで用意する。
final class AndroidAuthRepository: AuthRepository {
    func signIn(username: String, password: String) async throws -> CoreAuthUser {
        throw AndroidAdapterError.notImplemented("AuthRepository.signIn")
    }

    func signUp(username: String, password: String, age: Int, gender: String) async throws -> CoreAuthUser {
        throw AndroidAdapterError.notImplemented("AuthRepository.signUp")
    }

    func signOut() async {}

    func deleteCurrentAccount() async throws {
        throw AndroidAdapterError.notImplemented("AuthRepository.deleteCurrentAccount")
    }

    func currentUser() async -> CoreAuthUser? {
        nil
    }
}

final class AndroidUserProfileRepository: UserProfileRepository {
    func loadUserProfile(userID: String) async throws {
        throw AndroidAdapterError.notImplemented("UserProfileRepository.loadUserProfile")
    }

    func saveCurrentUserProfile() async throws {
        throw AndroidAdapterError.notImplemented("UserProfileRepository.saveCurrentUserProfile")
    }

    func updateUserName(_ name: String) async {}
    func updatePublicFlag(_ isPublic: Bool) async {}
    func updateHomePrefecture(_ prefectureName: String) async {}
}

final class AndroidPostRepository: PostRepository {
    func postEmotion(
        level: Int,
        coordinate: CoreCoordinate?,
        comment: String?,
        isPublicPost: Bool,
        isMistCleanup: Bool
    ) async throws -> Bool {
        throw AndroidAdapterError.notImplemented("PostRepository.postEmotion")
    }
}

final class AndroidTimelineRepository: TimelineRepository {
    func fetchRecentPosts(lastHours: Int, friendsOnly: Bool) async throws -> [EmotionPost] {
        throw AndroidAdapterError.notImplemented("TimelineRepository.fetchRecentPosts")
    }

    func fetchMyPosts() async throws -> [EmotionPost] {
        throw AndroidAdapterError.notImplemented("TimelineRepository.fetchMyPosts")
    }
}

final class AndroidMistEventRepository: MistEventRepository {
    func fetchActiveMistEvents() async throws -> [MistEvent] {
        throw AndroidAdapterError.notImplemented("MistEventRepository.fetchActiveMistEvents")
    }
}

final class AndroidLocationPort: LocationPort {
    func currentCoordinate() async -> CoreCoordinate? {
        nil
    }
}

final class AndroidNotificationPort: NotificationPort {
    func requestPermissionIfNeeded() async {}
    func refreshBadge(unreadCount: Int) async {}
}

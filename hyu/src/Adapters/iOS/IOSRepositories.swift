import Foundation
import UserNotifications
import UIKit
import CoreLocation

enum AdapterError: LocalizedError {
    case authFailed(String)
    case accountDeletionFailed(String)

    var errorDescription: String? {
        switch self {
        case .authFailed(let message):
            return message
        case .accountDeletionFailed(let message):
            return message
        }
    }
}

@MainActor
final class IOSAuthRepository: AuthRepository {
    private let authService: LocalAuthService

    init(authService: LocalAuthService = .shared) {
        self.authService = authService
    }

    func signIn(username: String, password: String) async throws -> CoreAuthUser {
        let ok = await authService.signIn(username: username, password: password)
        guard ok, let current = authService.currentUsername else {
            throw AdapterError.authFailed(authService.errorMessage ?? "ログインに失敗しました")
        }
        return CoreAuthUser(username: current, userID: UserService.shared.currentUserID)
    }

    func signUp(username: String, password: String, age: Int, gender: String) async throws -> CoreAuthUser {
        let ok = await authService.signUp(username: username, password: password, age: age, gender: gender)
        guard ok, let current = authService.currentUsername else {
            throw AdapterError.authFailed(authService.errorMessage ?? "新規登録に失敗しました")
        }
        return CoreAuthUser(username: current, userID: UserService.shared.currentUserID)
    }

    func signOut() async {
        authService.signOut()
    }

    func deleteCurrentAccount() async throws {
        let ok = await authService.deleteAccount()
        guard ok else {
            throw AdapterError.accountDeletionFailed(authService.errorMessage ?? "アカウント削除に失敗しました")
        }
    }

    func currentUser() async -> CoreAuthUser? {
        guard let current = authService.currentUsername else { return nil }
        return CoreAuthUser(username: current, userID: UserService.shared.currentUserID)
    }
}

final class IOSUserProfileRepository: UserProfileRepository {
    private let firestoreService: FirestoreService

    init(firestoreService: FirestoreService = FirestoreService()) {
        self.firestoreService = firestoreService
    }

    func loadUserProfile(userID: String) async throws {
        UserService.shared.setCurrentUserID(userID)
        try await firestoreService.loadCurrentUserProfile()
    }

    func saveCurrentUserProfile() async throws {
        try await firestoreService.saveUserProfile()
    }

    func updateUserName(_ name: String) async {
        UserService.shared.userName = name
    }

    func updatePublicFlag(_ isPublic: Bool) async {
        UserService.shared.isPublicAccount = isPublic
    }

    func updateHomePrefecture(_ prefectureName: String) async {
        UserService.shared.homePrefectureName = prefectureName
    }
}

final class IOSPostRepository: PostRepository {
    private let firestoreService: FirestoreService

    init(firestoreService: FirestoreService = FirestoreService()) {
        self.firestoreService = firestoreService
    }

    func postEmotion(
        level: Int,
        coordinate: CoreCoordinate?,
        comment: String?,
        isPublicPost: Bool,
        isMistCleanup: Bool
    ) async throws -> Bool {
        let emotionLevel = EmotionLevel.clamped(level)
        return try await firestoreService.postEmotion(
            level: emotionLevel,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            isPublicPost: isPublicPost,
            comment: comment,
            isMistCleanup: isMistCleanup
        )
    }
}

final class IOSTimelineRepository: TimelineRepository {
    private let firestoreService: FirestoreService

    init(firestoreService: FirestoreService = FirestoreService()) {
        self.firestoreService = firestoreService
    }

    func fetchRecentPosts(lastHours: Int, friendsOnly: Bool) async throws -> [EmotionPost] {
        try await firestoreService.fetchRecentEmotions(lastHours: lastHours, includeOnlyFriends: friendsOnly)
    }

    func fetchMyPosts() async throws -> [EmotionPost] {
        try await firestoreService.fetchMyPosts()
    }
}

final class IOSMistEventRepository: MistEventRepository {
    private let firestoreService: FirestoreService

    init(firestoreService: FirestoreService = FirestoreService()) {
        self.firestoreService = firestoreService
    }

    func fetchActiveMistEvents() async throws -> [MistEvent] {
        try await firestoreService.fetchActiveMistEvents()
    }
}

@MainActor
final class IOSLocationPort: LocationPort {
    private let locationService: LocationService

    init(locationService: LocationService) {
        self.locationService = locationService
    }

    convenience init() {
        self.init(locationService: LocationService())
    }

    func currentCoordinate() async -> CoreCoordinate? {
        guard let location = await locationService.getCurrentLocation() else { return nil }
        return CoreCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
}

final class IOSNotificationPort: NotificationPort {
    private let notificationService: NotificationService

    init(notificationService: NotificationService = .shared) {
        self.notificationService = notificationService
    }

    func requestPermissionIfNeeded() async {
        await notificationService.requestAuthorization()
    }

    func refreshBadge(unreadCount: Int) async {
        if #available(iOS 16.0, *) {
            try? await UNUserNotificationCenter.current().setBadgeCount(unreadCount)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = unreadCount
        }
    }
}

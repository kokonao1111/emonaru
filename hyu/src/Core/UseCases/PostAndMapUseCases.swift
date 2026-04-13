import Foundation

final class PostUseCase {
    private let postRepository: PostRepository

    init(postRepository: PostRepository) {
        self.postRepository = postRepository
    }

    func createPost(
        level: Int,
        coordinate: CoreCoordinate?,
        comment: String?,
        isPublicPost: Bool,
        isMistCleanup: Bool
    ) async throws -> Bool {
        try await postRepository.postEmotion(
            level: level,
            coordinate: coordinate,
            comment: comment,
            isPublicPost: isPublicPost,
            isMistCleanup: isMistCleanup
        )
    }
}

final class TimelineUseCase {
    private let timelineRepository: TimelineRepository

    init(timelineRepository: TimelineRepository) {
        self.timelineRepository = timelineRepository
    }

    func loadRecentPosts(lastHours: Int = 24, friendsOnly: Bool = false) async throws -> [EmotionPost] {
        try await timelineRepository.fetchRecentPosts(lastHours: lastHours, friendsOnly: friendsOnly)
    }

    func loadMyPosts() async throws -> [EmotionPost] {
        try await timelineRepository.fetchMyPosts()
    }
}

final class MistUseCase {
    private let mistRepository: MistEventRepository

    init(mistRepository: MistEventRepository) {
        self.mistRepository = mistRepository
    }

    func loadActiveEvents() async throws -> [MistEvent] {
        try await mistRepository.fetchActiveMistEvents()
    }
}

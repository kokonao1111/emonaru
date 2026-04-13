import Foundation

enum EmotionLevel: Int, CaseIterable, Codable, Hashable {
    case minusFive = -5
    case minusFour = -4
    case minusThree = -3
    case minusTwo = -2
    case minusOne = -1
    case zero = 0
    case plusOne = 1
    case plusTwo = 2
    case plusThree = 3
    case plusFour = 4
    case plusFive = 5

    static func clamped(_ value: Int) -> EmotionLevel {
        EmotionLevel(rawValue: max(-5, min(5, value))) ?? .zero
    }
}

enum EmotionVisualType: String, CaseIterable, Codable, Hashable {
    case glow
    case ripple
    case mist
    case pulse
}

enum SupportEmoji: String, CaseIterable, Codable, Hashable {
    // 悲しい感情用の応援絵文字
    case muscle = "💪"      // ガッツポーズ・努力（応援・ファイト）
    case megaphone = "📣"   // 応援
    case fire = "🔥"        // 熱い応援
    case heart = "❤️"       // 心からの応援
    case clap = "👏"        // 拍手・励まし
    case star = "⭐"        // 頑張れ
    
    // 嬉しい感情用の共感絵文字
    case hug = "🤗"         // ハグ
    case relieved = "😌"    // ほっとした
    case smiling = "🥰"     // 嬉しい
    case sparkles = "✨"    // キラキラ
    case star2 = "🌟"      // 星
    case raisedHands = "🙌" // 両手を上げる
    case thumbsUp = "👍"   // いいね
    
    var displayName: String {
        switch self {
        case .muscle: return "ファイト"
        case .megaphone: return "応援"
        case .fire: return "熱い応援"
        case .heart: return "心からの応援"
        case .clap: return "拍手"
        case .star: return "頑張れ"
        case .hug: return "ハグ"
        case .relieved: return "ほっとした"
        case .smiling: return "嬉しい"
        case .sparkles: return "キラキラ"
        case .star2: return "星"
        case .raisedHands: return "両手を上げる"
        case .thumbsUp: return "いいね"
        }
    }
    
    // 感情レベルに応じた応援絵文字のリストを返す
    static func emojisForEmotion(level: EmotionLevel) -> [SupportEmoji] {
        if level.rawValue < 0 {
            // 悲しい感情用（応援系）
            return [.muscle, .megaphone, .fire, .heart, .clap, .star]
        } else if level.rawValue > 0 {
            // 嬉しい感情用（共感系）
            return [.hug, .relieved, .smiling, .sparkles, .star2, .raisedHands, .thumbsUp]
        } else {
            // 普通の場合は中立的な共感系のみ（応援系は不適切）
            return [.hug, .relieved, .smiling, .sparkles, .star2, .raisedHands, .thumbsUp]
        }
    }
}

struct SupportInfo: Codable, Hashable {
    let emoji: SupportEmoji
    let userID: String
    let timestamp: Date
}

struct EmotionPost: Identifiable, Codable, Hashable {
    let id: UUID
    let level: EmotionLevel
    let visualType: EmotionVisualType
    let createdAt: Date
    let latitude: Double?
    let longitude: Double?
    let likeCount: Int
    let likedBy: [String] // ユーザーIDのリスト
    let supports: [SupportInfo] // 応援情報のリスト
    let authorID: String? // 投稿者のユーザーID
    let isPublicPost: Bool // 投稿の公開設定（true: 誰でも見れる、false: 友達のみ）
    let comment: String? // コメント（友達のみの投稿の場合のみ）
    let isMistCleanup: Bool // モヤ浄化投稿かどうか

    init(id: UUID = UUID(),
         level: EmotionLevel,
         visualType: EmotionVisualType,
         createdAt: Date = Date(),
         latitude: Double? = nil,
         longitude: Double? = nil,
         likeCount: Int = 0,
         likedBy: [String] = [],
         supports: [SupportInfo] = [],
         authorID: String? = nil,
         isPublicPost: Bool = true,
         comment: String? = nil,
         isMistCleanup: Bool = false) {
        self.id = id
        self.level = level
        self.visualType = visualType
        self.createdAt = createdAt
        self.latitude = latitude
        self.longitude = longitude
        self.likeCount = likeCount
        self.likedBy = likedBy
        self.supports = supports
        self.authorID = authorID
        self.isPublicPost = isPublicPost
        self.comment = comment
        self.isMistCleanup = isMistCleanup
    }
    
    var isLikedByCurrentUser: Bool {
        let currentUserID = UserService.shared.currentUserID
        return likedBy.contains(currentUserID)
    }
    
    var supportCount: Int {
        supports.count
    }
    
    var supportEmojiCounts: [SupportEmoji: Int] {
        var counts: [SupportEmoji: Int] = [:]
        for support in supports {
            counts[support.emoji, default: 0] += 1
        }
        return counts
    }
    
    var hasSupportFromCurrentUser: Bool {
        let currentUserID = UserService.shared.currentUserID
        return supports.contains { $0.userID == currentUserID }
    }
    
    var needsSupport: Bool {
        // 悲しい感情（マイナス）または嬉しい感情（プラス）の場合は応援/共感が必要
        level.rawValue != 0
    }
    
    var isHappyEmotion: Bool {
        level.rawValue > 0
    }
    
    var isSadEmotion: Bool {
        level.rawValue < 0
    }
    
    var isMyPost: Bool {
        guard let authorID = authorID else { return false }
        return authorID == UserService.shared.currentUserID
    }
}

// MARK: - Notification Models

struct AppNotification: Identifiable {
    let id: String
    let type: NotificationType
    let title: String
    let body: String
    let createdAt: Date
    let isRead: Bool
    let source: NotificationSource
    let relatedID: String? // 関連する投稿IDやユーザーIDなど

    init(
        id: String,
        type: NotificationType,
        title: String,
        body: String,
        createdAt: Date,
        isRead: Bool,
        relatedID: String?,
        source: NotificationSource = .firestore
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.isRead = isRead
        self.relatedID = relatedID
        self.source = source
    }
}

enum NotificationSource {
    case firestore
    case system
}

enum NotificationType: String {
    case friendRequest = "friend_request"
    case friendAccepted = "friend_accepted"
    case support = "support"
    case comment = "comment"
    case like = "like"
    case view = "view"
    case mistCleared = "mist_cleared"
    case missionCleared = "mission_cleared"
    case levelUp = "level_up"
    case gaugeFilled = "gauge_filled"
    case dailyEmotionReminder = "daily_emotion_reminder"
    case systemUpdate = "system_update" // 管理者からのアップデート通知
    case announcement = "announcement" // 管理者からのカスタム通知
}

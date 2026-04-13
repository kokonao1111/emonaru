import Foundation

// ============================================
// UserService: ユーザー情報管理
// ============================================
// このファイルの役割：
// - ユーザーのID、名前、レベル、経験値を管理
// - 投稿回数の制限を管理（1日5回〜10回）
// - スマホ本体に情報を保存（UserDefaults）
// - アプリ全体で1つだけ作る（shared = 共有インスタンス）
// ============================================

final class UserService {
    // アプリ全体で1つだけ使う（どこからでもUserService.sharedで呼び出せる）
    static let shared = UserService()
    
    // スマホ本体に保存するデータの「キー」（名前）
    private let userIDKey = "com.nao.hyu.userID"  // ユーザーID
    private let userNameKey = "com.nao.hyu.userName"  // ユーザー名
    private let isPublicAccountKey = "com.nao.hyu.isPublicAccount"  // アカウント公開設定
    private let homePrefectureKey = "com.nao.hyu.homePrefecture"  // 出身都道府県
    private let experienceKey = "com.nao.hyu.experiencePoints"  // 経験値
    private let ageKey = "com.nao.hyu.userAge"  // 年齢
    private let genderKey = "com.nao.hyu.userGender"  // 性別
    
    // 投稿回数制限関連のキー
    private let lastNotificationTimeKey = "com.nao.hyu.lastNotificationTime"  // 最後に通知が来た時刻
    private let todayPostCountKey = "com.nao.hyu.todayPostCount"  // 今日の投稿回数
    private let lastPostDateKey = "com.nao.hyu.lastPostDate"  // 最後に投稿した日付
    private let respondedToNotificationKey = "com.nao.hyu.respondedToNotification"  // 通知に1分以内に応答したか
    private let hasActiveNotificationBonusKey = "com.nao.hyu.hasActiveNotificationBonus"  // 通知ボーナスが有効か
    private let bonusPostLimitKey = "com.nao.hyu.bonusPostLimit"  // 追加の投稿上限（ゲージ満タン報酬など）
    private let appliedAdminPostLimitBonusTotalKey = "com.nao.hyu.appliedAdminPostLimitBonusTotal"  // 管理者付与の適用済み累計
    
    // 外部から直接作れないようにする（shared経由で使う）
    private init() {}
    
    // ============================================
    // ユーザーIDを取得（なければ新規作成）
    // ============================================
    var currentUserID: String {
        // 保存されているIDがあればそれを返す
        if let savedID = UserDefaults.standard.string(forKey: userIDKey) {
            return savedID
        }
        // なければランダムなIDを新規作成
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: userIDKey)
        return newID
    }

    // ユーザーIDを変更（管理者用）
    func setCurrentUserID(_ userID: String) {
        UserDefaults.standard.set(userID, forKey: userIDKey)
    }

    // ユーザーIDをリセット（再ログイン用）
    func resetUserID() {
        UserDefaults.standard.removeObject(forKey: userIDKey)
    }

    // アカウント切替時にユーザー依存データを初期化
    // 別アカウントに前回のレベル/設定が引き継がれないようにする
    func resetUserScopedData(defaultUserName: String = "あなた") {
        UserDefaults.standard.set(defaultUserName, forKey: userNameKey)
        UserDefaults.standard.set(true, forKey: isPublicAccountKey)
        UserDefaults.standard.removeObject(forKey: homePrefectureKey)
        UserDefaults.standard.set(0, forKey: experienceKey)
        UserDefaults.standard.removeObject(forKey: ageKey)
        UserDefaults.standard.set("無回答", forKey: genderKey)

        // 投稿回数関連もユーザー依存データとして初期化
        UserDefaults.standard.removeObject(forKey: lastNotificationTimeKey)
        UserDefaults.standard.set(0, forKey: todayPostCountKey)
        UserDefaults.standard.removeObject(forKey: lastPostDateKey)
        UserDefaults.standard.set(false, forKey: respondedToNotificationKey)
        UserDefaults.standard.set(false, forKey: hasActiveNotificationBonusKey)
        UserDefaults.standard.set(0, forKey: bonusPostLimitKey)
        UserDefaults.standard.set(0, forKey: appliedAdminPostLimitBonusTotalKey)
    }
    
    // ============================================
    // ユーザー名（読み書き可能）
    // ============================================
    var userName: String {
        get {
            UserDefaults.standard.string(forKey: userNameKey) ?? "あなた"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userNameKey)
        }
    }
    
    // ============================================
    // アカウント公開設定（true=公開、false=非公開）
    // ============================================
    var isPublicAccount: Bool {
        get {
            // デフォルトは公開アカウント
            if UserDefaults.standard.object(forKey: isPublicAccountKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: isPublicAccountKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: isPublicAccountKey)
        }
    }

    // ============================================
    // 出身都道府県（文字列）
    // ============================================
    var homePrefectureName: String {
        get {
            UserDefaults.standard.string(forKey: homePrefectureKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: homePrefectureKey)
        }
    }

    // 出身都道府県（Prefecture型）
    var homePrefecture: Prefecture? {
        guard !homePrefectureName.isEmpty else { return nil }
        return Prefecture(rawValue: homePrefectureName)
    }
    
    // ============================================
    // 年齢（任意）
    // ============================================
    var userAge: Int? {
        get {
            let age = UserDefaults.standard.integer(forKey: ageKey)
            return age > 0 ? age : nil
        }
        set {
            if let age = newValue {
                UserDefaults.standard.set(age, forKey: ageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: ageKey)
            }
        }
    }
    
    // ============================================
    // 性別（任意）
    // ============================================
    var userGender: String {
        get {
            UserDefaults.standard.string(forKey: genderKey) ?? "無回答"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: genderKey)
        }
    }

    // ============================================
    // 経験値（読み書き可能）
    // ============================================
    var experiencePoints: Int {
        get {
            UserDefaults.standard.integer(forKey: experienceKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: experienceKey)
        }
    }
    
    // ============================================
    // レベル計算（レベルが上がるほど必要経験値が増える）
    // ============================================
    
    // レベルnに到達するために必要な累積経験値を計算
    // 例：レベル1→2は100、レベル2→3は150、レベル3→4は200...
    static func totalExpForLevel(_ level: Int) -> Int {
        LevelMath.totalExpForLevel(level)
    }
    
    // 経験値から現在のレベルを計算（逆算）
    static func calculateLevel(fromExp exp: Int) -> Int {
        LevelMath.calculateLevel(fromExp: exp)
    }
    
    // レベルnからレベルn+1に上がるために必要な経験値
    // 例：レベル1→2は100、レベル2→3は150
    static func expForNextLevel(_ currentLevel: Int) -> Int {
        LevelMath.expForNextLevel(currentLevel)
    }

    // ============================================
    // 現在のレベル（自動計算）
    // ============================================
    var level: Int {
        let calculatedLevel = UserService.calculateLevel(fromExp: experiencePoints)
        #if DEBUG
        print("📊 レベル計算: 経験値=\(experiencePoints), レベル=\(calculatedLevel)")
        #endif
        return calculatedLevel
    }

    // 現在のレベル内での経験値（例：レベル2で経験値30持っている）
    var xpInCurrentLevel: Int {
        let currentLevelTotalExp = UserService.totalExpForLevel(level)
        let xpInLevel = max(0, experiencePoints - currentLevelTotalExp)
        #if DEBUG
        print("📊 現在レベルの経験値: 総経験値=\(experiencePoints), レベル\(level)開始時=\(currentLevelTotalExp), レベル内経験値=\(xpInLevel)")
        #endif
        return xpInLevel
    }

    // 次のレベルまであと何経験値必要か
    var xpToNextLevel: Int {
        let expNeeded = UserService.expForNextLevel(level)
        let remaining = expNeeded - xpInCurrentLevel
        #if DEBUG
        print("📊 次のレベルまで: 必要=\(expNeeded), 現在=\(xpInCurrentLevel), 残り=\(remaining)")
        #endif
        return max(0, remaining)
    }

    // レベルの進行度（0.0〜1.0の割合）
    var levelProgress: Double {
        let expNeeded = UserService.expForNextLevel(level)
        guard expNeeded > 0 else { return 0.0 }
        let progress = Double(xpInCurrentLevel) / Double(expNeeded)
        let clampedProgress = min(1.0, max(0.0, progress))
        #if DEBUG
        print("📊 レベル進行度: \(xpInCurrentLevel)/\(expNeeded) = \(clampedProgress * 100)%")
        #endif
        return clampedProgress
    }

    // ============================================
    // 経験値を追加（投稿やミッションで呼ばれる）
    // ============================================
    func addExperience(points: Int) {
        guard points > 0 else { return }
        
        // 現在のレベルを記録
        let oldLevel = level
        
        // 経験値を加算
        experiencePoints += points
        
        // Firebaseにも保存（バックグラウンドで）
        Task {
            await FirestoreService().incrementUserExperiencePoints(points: points)
        }
        
        // レベルアップしたかチェック
        let newLevel = level
        if newLevel > oldLevel {
            // レベルアップした！
            Task {
                // レベルアップ報酬を付与
                try? await FirestoreService().awardLevelRewards(from: oldLevel, to: newLevel)
                // レベルアップ通知を作成
                try? await FirestoreService().createNotification(
                    type: .levelUp,
                    title: "レベルアップ！",
                    body: "レベル\(newLevel)になりました",
                    relatedID: "level_\(newLevel)",
                    toUserID: self.currentUserID
                )
            }
        }
        
        // 他の画面に「経験値が更新されたよ」と通知
        NotificationCenter.default.post(name: NSNotification.Name("ExperienceUpdated"), object: nil)
    }

    // Firebaseから経験値を同期（アプリ起動時など）
    func syncExperienceFromFirestore() async {
        do {
            if let remote = try await FirestoreService().fetchUserExperiencePoints() {
                if remote > experiencePoints {
                    experiencePoints = remote
                }
            }
        } catch {
            print("❌ 経験値の同期に失敗: \(error.localizedDescription)")
        }
    }
    
    // ============================================
    // 投稿回数制限管理
    // ============================================
    
    // 通知が来た時刻を記録（1日2回：午前と午後にランダムに通知が来る）
    func recordNotificationReceived(at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: lastNotificationTimeKey)
        // 通知ボーナスを有効化（1分以内に投稿すれば追加で1回投稿可能）
        UserDefaults.standard.set(true, forKey: hasActiveNotificationBonusKey)
        if !UserDefaults.standard.bool(forKey: respondedToNotificationKey) {
            UserDefaults.standard.set(false, forKey: respondedToNotificationKey)
        }
        resetDailyPostCountIfNeeded()
        print("🔔 通知ボーナスを有効化しました（1分以内に投稿すれば追加で1回投稿可能）")
    }
    
    // ============================================
    // 投稿時に呼び出す（1分以内に投稿したかチェック）
    // ============================================
    func recordPost() {
        let now = Date()
        
        // 日付が変わったらリセット
        resetDailyPostCountIfNeeded()
        
        var usedNotificationBonus = false
        
        // 通知が来て1分以内かチェック
        if let lastNotificationTime = UserDefaults.standard.object(forKey: lastNotificationTimeKey) as? Date {
            let timeSinceNotification = now.timeIntervalSince(lastNotificationTime)
            if timeSinceNotification <= 60.0 {
                // 1分以内に投稿した
                if !UserDefaults.standard.bool(forKey: respondedToNotificationKey) {
                    // 初めて1分以内に投稿したので、10回に設定
                    UserDefaults.standard.set(true, forKey: respondedToNotificationKey)
                    print("✅ 1分以内に投稿したので、今日の上限が10回になりました")
                }
                
                // 通知ボーナスを使った場合は消費
                if UserDefaults.standard.bool(forKey: hasActiveNotificationBonusKey) {
                    UserDefaults.standard.set(false, forKey: hasActiveNotificationBonusKey)
                    usedNotificationBonus = true
                    print("✅ 通知ボーナスを使用しました（上限を超えて投稿）")
                }
            }
        }
        
        // 通知ボーナスを使った場合は投稿回数を増やさない（追加枠として扱う）
        if !usedNotificationBonus {
            // 今日の投稿回数を増やす
            let currentCount = UserDefaults.standard.integer(forKey: todayPostCountKey)
            UserDefaults.standard.set(currentCount + 1, forKey: todayPostCountKey)
        }
        
        // 最終投稿日を更新
        UserDefaults.standard.set(now, forKey: lastPostDateKey)
    }
    
    // ============================================
    // ゲージ満タンボーナス：投稿上限自体を増やす
    // ============================================
    func addPostCountBonus(count: Int) {
        resetDailyPostCountIfNeeded()
        // 追加の投稿上限を増やす（例: 10回 → 11回）
        let currentBonus = UserDefaults.standard.integer(forKey: bonusPostLimitKey)
        let newBonus = currentBonus + count
        UserDefaults.standard.set(newBonus, forKey: bonusPostLimitKey)
        print("✅ 投稿上限ボーナス +\(count) (合計: +\(newBonus))")
    }

    /// Firestoreの「管理者付与 累計値」をもとに、未適用分だけ投稿上限ボーナスを反映する
    @discardableResult
    func applyAdminPostLimitBonus(totalGranted: Int) -> Int {
        resetDailyPostCountIfNeeded()
        let currentApplied = UserDefaults.standard.integer(forKey: appliedAdminPostLimitBonusTotalKey)
        let delta = max(0, totalGranted - currentApplied)
        guard delta > 0 else { return 0 }

        addPostCountBonus(count: delta)
        UserDefaults.standard.set(currentApplied + delta, forKey: appliedAdminPostLimitBonusTotalKey)
        print("✅ 管理者付与ボーナス適用: +\(delta)回（適用済み累計: \(currentApplied + delta)）")
        return delta
    }
    
    // ============================================
    // 今日の投稿可能回数を取得
    // ============================================
    // 基本：通知に1分以内に応答した日は10回、それ以外は5回
    // ボーナス：ゲージ満タン報酬などで追加
    var dailyPostLimit: Int {
        resetDailyPostCountIfNeeded()

        // 基本: 1分以内に投稿できた日は10回、それ以外は5回
        let baseLimit = UserDefaults.standard.bool(forKey: respondedToNotificationKey) ? 10 : 5
        
        // ボーナス分を加算（ゲージ満タン報酬など）
        let bonus = UserDefaults.standard.integer(forKey: bonusPostLimitKey)
        
        return baseLimit + bonus
    }
    
    // ============================================
    // 今日の投稿回数を取得
    // ============================================
    var todayPostCount: Int {
        resetDailyPostCountIfNeeded()
        return UserDefaults.standard.integer(forKey: todayPostCountKey)
    }
    
    // ============================================
    // 残りの投稿可能回数を取得
    // ============================================
    var remainingPosts: Int {
        max(0, dailyPostLimit - todayPostCount)
    }
    
    // ============================================
    // 投稿可能かチェック（投稿ボタンを押す前に呼ばれる）
    // ============================================
    func canPost() -> Bool {
        resetDailyPostCountIfNeeded()
        
        // 通常の制限内なら投稿可能
        if todayPostCount < dailyPostLimit {
            return true
        }
        
        // 上限に達している場合でも、通知ボーナスが有効なら投稿可能
        if hasActiveNotificationBonus() {
            print("✨ 通知ボーナスを使用して投稿可能です（上限に達していますが、1分以内なので追加で1回投稿可能）")
            return true
        }
        
        return false
    }
    
    // ============================================
    // 通知ボーナスが有効か（1分以内で未使用）
    // ============================================
    func hasActiveNotificationBonus() -> Bool {
        // ボーナスフラグがfalseなら無効
        guard UserDefaults.standard.bool(forKey: hasActiveNotificationBonusKey) else {
            return false
        }
        
        // 通知時刻を取得
        guard let lastNotificationTime = UserDefaults.standard.object(forKey: lastNotificationTimeKey) as? Date else {
            return false
        }
        
        // 1分以内かチェック
        let timeSinceNotification = Date().timeIntervalSince(lastNotificationTime)
        if timeSinceNotification <= 60.0 {
            return true
        } else {
            // 1分を過ぎたらボーナスを無効化
            UserDefaults.standard.set(false, forKey: hasActiveNotificationBonusKey)
            return false
        }
    }
    
    // ============================================
    // 通知ボーナスの残り時間を取得（秒）
    // ============================================
    func notificationBonusTimeRemaining() -> Int {
        guard hasActiveNotificationBonus() else {
            return 0
        }
        
        guard let lastNotificationTime = UserDefaults.standard.object(forKey: lastNotificationTimeKey) as? Date else {
            return 0
        }
        
        let timeSinceNotification = Date().timeIntervalSince(lastNotificationTime)
        let remaining = 60.0 - timeSinceNotification
        return max(0, Int(remaining))
    }
    
    // ============================================
    // 日付が変わったら投稿回数をリセット（自動）
    // ============================================
    private func resetDailyPostCountIfNeeded() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        if let lastPostDate = UserDefaults.standard.object(forKey: lastPostDateKey) as? Date {
            let lastPostDay = calendar.startOfDay(for: lastPostDate)
            
            if !calendar.isDate(today, inSameDayAs: lastPostDay) {
                // 日付が変わったのでリセット
                UserDefaults.standard.set(0, forKey: todayPostCountKey)
                UserDefaults.standard.set(Date(), forKey: lastPostDateKey)
                UserDefaults.standard.set(false, forKey: respondedToNotificationKey)
                UserDefaults.standard.set(false, forKey: hasActiveNotificationBonusKey)
                UserDefaults.standard.set(0, forKey: bonusPostLimitKey) // ボーナス上限もリセット
                print("🌅 日付が変わったので投稿回数とボーナスをリセットしました")
            }
        } else {
            // 初回実行時
            UserDefaults.standard.set(0, forKey: todayPostCountKey)
            UserDefaults.standard.set(Date(), forKey: lastPostDateKey)
            UserDefaults.standard.set(0, forKey: bonusPostLimitKey)
        }
    }
}

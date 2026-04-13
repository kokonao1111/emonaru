import Foundation
import FirebaseFirestore
import FirebaseStorage
import Darwin
import UIKit
import CoreLocation

// ============================================
// FirestoreService: データベース操作の中心
// ============================================
// このファイルの役割：
// - Firebase（データベース）とのやり取りを全て管理
// - 投稿、ユーザー、友達、通知などのデータを保存・取得・削除
// - アプリの他の部分から「FirestoreService」を呼び出して使う
// ============================================

final class FirestoreService {
    // Firebaseのデータベースに接続
    private let db = Firestore.firestore()
    
    // データの保存先の名前（Firebaseの「コレクション」という単位）
    private let collectionName = "emotions"  // 投稿データ
    private let usersCollectionName = "users"  // ユーザー情報
    private let blockedDevicesCollectionName = "blockedDevices" // BAN端末情報

    // エラーの種類を定義（凍結/BANアカウントのエラー）
    private enum AdminPostRestrictionError: LocalizedError {
        case frozen  // アカウント凍結
        case banned  // アカウントBAN
        case inappropriateComment

        var errorDescription: String? {
            switch self {
            case .frozen:
                return "アカウントが凍結されているため投稿できません"
            case .banned:
                return "アカウントがBANされているため利用できません"
            case .inappropriateComment:
                return "不適切な言葉が含まれているため投稿できません"
            }
        }
    }

    private let inappropriateWords = [
        "死ね", "しね", "氏ね", "殺す", "ころす", "殺害", "自殺",
        "消えろ", "消え失せろ", "ぶっころ", "ぶっ殺",
        "バカ", "ばか", "馬鹿", "アホ", "あほ", "間抜け", "クズ", "くず", "ゴミ",
        "うざい", "キモ", "きも", "気持ち悪",
        "クソ", "くそ", "糞", "ちんかす", "まんこ", "ちんこ",
        "fuck", "fxxk", "shit", "bitch", "die", "kill"
    ]

    // ============================================
    // ユーザーが凍結/BANされていないかチェック
    // ============================================
    // 投稿前に毎回呼ばれる
    // 凍結またはBANされている場合はエラーを投げて投稿を止める
    private func ensureUserNotFrozen() async throws {
        let currentUserID = UserService.shared.currentUserID
        let docRef = db.collection(usersCollectionName).document(currentUserID)
        // サーバーからユーザー情報を取得（待つ処理）
        let document = try await docRef.getDocument()
        guard document.exists else { return }
        let isFrozen = document.get("isFrozen") as? Bool ?? false
        let isBanned = document.get("isBanned") as? Bool ?? false
        if isBanned {
            throw AdminPostRestrictionError.banned
        }
        if isFrozen {
            // 凍結されていたらエラーを投げる
            throw AdminPostRestrictionError.frozen
        }
    }

    // ユーザーの利用端末情報を保存
    func addDeviceFingerprintToUser(userID: String, fingerprint: String) async throws {
        try await db.collection(usersCollectionName)
            .document(userID)
            .setData([
                "deviceFingerprints": FieldValue.arrayUnion([fingerprint]),
                "lastDeviceFingerprintUpdatedAt": Timestamp(date: Date())
            ], merge: true)
    }

    // 端末がBAN対象かを確認
    func isDeviceFingerprintBanned(_ fingerprint: String) async throws -> Bool {
        let doc = try await db.collection(blockedDevicesCollectionName)
            .document(fingerprint)
            .getDocument()
        guard doc.exists else { return false }
        return doc.get("isActive") as? Bool ?? true
    }

    // 指定ユーザーに紐づく端末をBAN対象に追加
    private func banKnownDevices(for userID: String, reason: String) async throws {
        let userDoc = try await db.collection(usersCollectionName).document(userID).getDocument()
        let fingerprints = userDoc.get("deviceFingerprints") as? [String] ?? []
        guard !fingerprints.isEmpty else { return }

        for fingerprint in fingerprints {
            try await db.collection(blockedDevicesCollectionName)
                .document(fingerprint)
                .setData([
                    "isActive": true,
                    "userID": userID,
                    "reason": reason,
                    "bannedAt": Timestamp(date: Date()),
                    "updatedAt": Timestamp(date: Date())
                ], merge: true)
        }
    }

    // 指定ユーザーに紐づく端末BANを解除
    private func unbanKnownDevices(for userID: String) async throws {
        let userDoc = try await db.collection(usersCollectionName).document(userID).getDocument()
        let fingerprints = userDoc.get("deviceFingerprints") as? [String] ?? []
        guard !fingerprints.isEmpty else { return }

        for fingerprint in fingerprints {
            try await db.collection(blockedDevicesCollectionName)
                .document(fingerprint)
                .setData([
                    "isActive": false,
                    "unbannedAt": Timestamp(date: Date()),
                    "updatedAt": Timestamp(date: Date())
                ], merge: true)
        }
    }

    private func normalizeForModeration(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        let katakanaUnified = folded.applyingTransform(.hiraganaToKatakana, reverse: false) ?? folded
        let noSeparators = katakanaUnified.replacingOccurrences(
            of: "[\\s\\p{P}\\p{S}ーｰ＿_]+",
            with: "",
            options: .regularExpression
        )
        return noSeparators.lowercased()
    }

    private func containsInappropriateText(_ text: String) -> Bool {
        let normalized = normalizeForModeration(text)
        return inappropriateWords.contains { word in
            let normalizedWord = normalizeForModeration(word)
            return !normalizedWord.isEmpty && normalized.contains(normalizedWord)
        }
    }
    private let spotCoordinates: [String: (Double, Double)] = [
        "北海道|札幌時計台": (43.0625537, 141.3536448),
        "北海道|小樽運河": (43.2020231, 141.0006005),
        "北海道|富良野・美瑛のラベンダー畑": (43.4172981, 142.4254766),
        "青森県|弘前城": (40.6079291, 140.4636605),
        "青森県|十和田湖・奥入瀬渓流": (40.5919977, 141.4079347),
        "青森県|三内丸山遺跡": (40.8110007, 140.6975615),
        "岩手県|中尊寺": (39.000941, 141.1020699),
        "岩手県|平泉世界遺産": (38.9641897, 141.1202559),
        "岩手県|浄土ヶ浜": (39.6524503, 141.9787366),
        "宮城県|仙台城址": (38.2514593, 140.8563901),
        "宮城県|松島湾・瑞巌寺": (38.3721758, 141.0595579),
        "宮城県|鳴子温泉郷": (38.743466, 140.716093),
        "秋田県|角館の武家屋敷通り": (40.1907363, 140.7919952),
        "秋田県|田沢湖": (39.724837, 140.6632728),
        "秋田県|男鹿半島のなまはげ館": (39.9292411, 139.7665485),
        "山形県|山寺の立石寺": (38.3125626, 140.4373997),
        "山形県|蔵王連峰・御釜": (38.1364301, 140.4495359),
        "山形県|銀山温泉": (38.5704194, 140.5300687),
        "福島県|会津若松城（鶴ヶ城）": (37.4908631, 139.9279581),
        "福島県|五色沼": (37.7406286, 140.2431745),
        "福島県|大内宿": (37.3336291, 139.8606616),
        "茨城県|偕楽園": (36.375135, 140.453545),
        "茨城県|日立海浜公園": (36.4025277, 140.5943473),
        "茨城県|鹿島神宮": (35.9687708, 140.6315435),
        "栃木県|日光東照宮": (36.7576378, 139.59911),
        "栃木県|華厳の滝": (36.737944, 139.5040485),
        "栃木県|那須どうぶつ王国": (37.1320456, 140.0404064),
        "群馬県|草津温泉": (36.6208447, 138.5963928),
        "群馬県|富岡製糸場": (36.2554386, 138.8876423),
        "群馬県|尾瀬ヶ原": (36.9398423, 139.2415966),
        "埼玉県|川越の蔵造りの街並み": (35.9237132, 139.4828468),
        "埼玉県|長瀞ライン下り": (36.0921105, 139.1168334),
        "埼玉県|秩父神社": (35.9975821, 139.0842446),
        "千葉県|東京ディズニーリゾート": (35.6308162, 139.8811452),
        "千葉県|鴨川シーワールド": (35.1152464, 140.1190315),
        "千葉県|成田山新勝寺": (35.7863311, 140.3172238),
        "東京都|東京スカイツリー": (35.7100543, 139.8107141),
        "東京都|浅草寺": (35.7134032, 139.7955265),
        "東京都|明治神宮": (35.6748417, 139.6996266),
        "東京都|東京タワー": (35.6584491, 139.745536),
        "東京都|コクーンタワー": (35.691667, 139.696944),
        "神奈川県|鎌倉大仏（高徳院）": (35.3194545, 139.5309218),
        "神奈川県|鶴岡八幡宮": (35.3251836, 139.5561787),
        "神奈川県|横浜・みなとみらい": (35.4656854, 139.6225042),
        "新潟県|佐渡金山": (38.0351723, 138.2409265),
        "新潟県|越後湯沢温泉エリア": (36.9359414, 138.8090456),
        "新潟県|弥彦山": (37.704725, 138.8090021),
        "富山県|黒部ダム": (36.5666941, 137.6636386),
        "富山県|立山黒部アルペンルート": (36.5771869, 137.4942412),
        "富山県|五箇山合掌造り集落": (36.426177, 136.9355622),
        "石川県|金沢城跡／兼六園": (36.5667352, 136.6604818),
        "石川県|21世紀美術館": (36.561088, 136.659375),
        "石川県|近江町市場": (36.564516, 136.6648286),
        "福井県|東尋坊": (36.2378867, 136.1256526),
        "福井県|恐竜博物館": (36.0823042, 136.5065708),
        "福井県|越前海岸": (35.980852, 135.961081),
        "山梨県|富士山（河口湖周辺・五合目エリア）": (35.5130603, 138.7448243),
        "山梨県|忍野八海": (35.4602407, 138.8327032),
        "山梨県|甲府城跡": (35.5993824, 138.5489558),
        "長野県|松本城": (36.2386353, 137.9688709),
        "長野県|善光寺": (36.6614233, 138.1876577),
        "長野県|上高地": (36.2539303, 137.6609406),
        "岐阜県|白川郷合掌造り集落": (36.2573454, 136.9068317),
        "岐阜県|高山の古い町並み": (36.1408745, 137.2596623),
        "岐阜県|郡上八幡城": (35.7530831, 136.9614453),
        "静岡県|富士山（世界遺産・周辺エリア）": (35.3628384, 138.7307677),
        "静岡県|熱海温泉": (35.1025681, 139.0775665),
        "静岡県|三保の松原": (34.9947415, 138.5238018),
        "愛知県|名古屋城": (35.1853191, 136.899177),
        "愛知県|熱田神宮": (35.1254307, 136.9092535),
        "愛知県|犬山城": (35.3883304, 136.9392776),
        "三重県|伊勢神宮": (34.4568901, 136.722978),
        "三重県|熊野古道": (33.9483471, 136.1886085),
        "三重県|鳥羽水族館": (34.4820148, 136.8453304),
        "滋賀県|琵琶湖": (35.2486461, 136.0825575),
        "滋賀県|彦根城": (35.2771013, 136.2517204),
        "滋賀県|比叡山延暦寺": (35.0710355, 135.8655837),
        "京都府|清水寺": (34.994303, 135.7844389),
        "京都府|金閣寺（鹿苑寺）": (34.9350961, 135.7637241),
        "京都府|伏見稲荷大社": (34.9675192, 135.7797101),
        "大阪府|大阪城": (34.6873735, 135.5258555),
        "大阪府|道頓堀": (34.6690306, 135.5015715),
        "大阪府|ユニバーサル・スタジオ・ジャパン": (34.6656393, 135.4324527),
        "兵庫県|姫路城": (34.8393313, 134.69402),
        "兵庫県|有馬温泉": (34.7992564, 135.2462748),
        "兵庫県|神戸・北野異人館街": (34.7012602, 135.1897321),
        "奈良県|東大寺": (34.6882437, 135.8397568),
        "奈良県|奈良公園": (34.6829008, 135.8545975),
        "奈良県|吉野山": (34.3604611, 135.867088),
        "和歌山県|熊野古道": (34.0770299, 135.1754914),
        "和歌山県|那智の滝": (34.2264879, 135.1672869),
        "和歌山県|高野山": (34.212105, 135.582004),
        "鳥取県|鳥取砂丘": (35.5412997, 134.2277259),
        "鳥取県|白兎神社": (35.5241947, 134.114756),
        "鳥取県|倉吉の白壁土蔵群": (35.4313456, 133.8248245),
        "島根県|出雲大社": (35.399803, 132.6851508),
        "島根県|石見銀山遺跡": (35.113757, 132.445335),
        "島根県|松江城": (35.4751405, 133.0507625),
        "岡山県|後楽園": (34.66633, 133.9373948),
        "岡山県|岡山城": (34.6651763, 133.9360446),
        "岡山県|倉敷美観地区": (34.596525, 133.7725863),
        "広島県|広島平和記念公園・原爆ドーム": (34.3931715, 132.4523008),
        "広島県|宮島（厳島神社）": (34.2965418, 132.3190077),
        "広島県|呉の大和ミュージアム": (34.2411847, 132.5558799),
        "山口県|秋吉台カルスト台地": (34.2341672, 131.3060432),
        "山口県|瑠璃光寺五重塔": (34.1901755, 131.4729196),
        "山口県|角島大橋": (34.3523746, 130.8872191),
        "徳島県|阿波おどり会館": (34.0701944, 134.5450768),
        "徳島県|渦の道": (34.2361791, 134.6421065),
        "徳島県|鳴門公園（大鳴門橋架橋記念公園）": (34.2365132, 134.6410668),
        "香川県|栗林公園": (34.3294971, 134.0439264),
        "香川県|金刀比羅宮": (34.1839885, 133.8093897),
        "香川県|小豆島・寒霞渓": (34.484731, 134.305919),
        "愛媛県|道後温泉": (33.8504258, 132.7850817),
        "愛媛県|松山城": (33.845651, 132.7657463),
        "愛媛県|しまなみ海道": (34.2579535, 133.0554965),
        "高知県|高知城": (33.560691, 133.5314588),
        "高知県|桂浜": (33.4971075, 133.5744564),
        "高知県|四万十川": (33.1930362, 132.9695409),
        "福岡県|太宰府天満宮": (33.5196499, 130.5329934),
        "福岡県|福岡タワー": (33.5932744, 130.3514862),
        "福岡県|大濠公園": (33.5861213, 130.3763612),
        "佐賀県|佐賀城跡": (33.3057911, 130.2459879),
        "佐賀県|虹の松原": (33.4410429, 130.0164662),
        "佐賀県|吉野ヶ里歴史公園": (33.3270916, 130.3842637),
        "長崎県|グラバー園": (32.7333666, 129.869055),
        "長崎県|稲佐山夜景": (32.753426, 129.8493382),
        "長崎県|長崎原爆資料館・平和公園": (32.7727742, 129.8643791),
        "熊本県|熊本城": (32.8052691, 130.7054642),
        "熊本県|阿蘇山": (32.8827019, 131.0947404),
        "熊本県|黒川温泉": (33.0777131, 131.1419381),
        "大分県|別府温泉": (33.2784567, 131.5055897),
        "大分県|湯布院": (33.2519414, 131.3547042),
        "大分県|高崎山自然動物園": (33.2583853, 131.530798),
        "宮崎県|高千穂峡": (32.7017851, 131.300939),
        "宮崎県|日南海岸": (31.7768245, 131.4821614),
        "宮崎県|青島神社": (31.8044125, 131.4750916),
        "鹿児島県|屋久島": (30.347925, 130.5244832),
        "鹿児島県|桜島": (31.5805744, 130.657984),
        "鹿児島県|指宿温泉": (31.2526556, 130.655128),
        "沖縄県|美ら海水族館": (26.6943689, 127.878038),
        "沖縄県|首里城": (26.2170014, 127.7193727),
        "沖縄県|今帰仁城跡": (26.6915191, 127.9291442)
    ]

    // ============================================
    // 【重要】投稿を作成してFirebaseに保存
    // ============================================
    // 引数の説明：
    // - level: 感情レベル（-5〜+5）
    // - visualType: 表示エフェクトの種類
    // - latitude/longitude: 投稿位置（任意）
    // - isPublicPost: 公開設定（true=みんなに見える、false=友達のみ）
    // - comment: コメント（任意）
    // - isMistCleanup: モヤ浄化投稿かどうか
    // 
    // 戻り値：観光スポットボーナスがあったか（true/false）
    // ============================================
    func postEmotion(
        level: EmotionLevel,
        visualType: EmotionVisualType = .glow,
        latitude: Double? = nil,
        longitude: Double? = nil,
        isPublicPost: Bool = true,
        comment: String? = nil,
        isMistCleanup: Bool = false
    ) async throws -> Bool {
        // ステップ1: アカウントが凍結されていないかチェック
        try await ensureUserNotFrozen()

        // ステップ1.5: コメントの不適切ワードチェック
        if let comment = comment,
           !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           containsInappropriateText(comment) {
            throw AdminPostRestrictionError.inappropriateComment
        }
        
        // ステップ2: 投稿データを準備
        let id = UUID()  // ランダムなID生成
        let currentUserID = UserService.shared.currentUserID
        let docID = id.uuidString
        
        // 保存するデータを辞書形式で作成
        var data: [String: Any] = [
            "id": docID,
            "level": level.rawValue,  // 感情レベル（数値）
            "visualType": visualType.rawValue,  // 表示エフェクト
            "createdAt": Timestamp(date: Date()),  // 投稿日時
            "likeCount": 0,  // いいね数（初期値0）
            "likedBy": [],  // いいねしたユーザーリスト（初期値空）
            "supports": [],  // 応援リスト（初期値空）
            "authorID": currentUserID,  // 投稿者のID
            "isPublicPost": isPublicPost,  // 公開設定
            "isMistCleanup": isMistCleanup  // モヤ浄化投稿かどうか
        ]
        
        // 位置情報があれば追加
        if let latitude = latitude, let longitude = longitude {
            data["latitude"] = latitude
            data["longitude"] = longitude
        }
        
        // コメントがあれば追加
        if let comment = comment, !comment.isEmpty {
            data["comment"] = comment
        }

        print("✅ 投稿を作成中: collection=\(collectionName), docID=\(docID)")
        print("✅ 投稿データ: \(data)")
        
        // ステップ3: Firebaseに保存（待つ処理）
        try await db.collection(collectionName)
            .document(docID)
            .setData(data)
        
        print("✅ 投稿の作成が完了しました: docID=\(docID)")

        // ステップ4: 観光スポットボーナスの判定
        var spotBonus = false
        if let latitude = latitude, let longitude = longitude {
            // 観光スポットの近く（50m以内）で投稿したかチェック
            if (try? await findNearestSpot(latitude: latitude, longitude: longitude)) != nil {
                spotBonus = true
                // スポットボーナス：経験値+20（通常10 + ボーナス20 = 合計30）
                UserService.shared.addExperience(points: 20)
                // 投稿回数+3回のボーナス
                UserService.shared.addPostCountBonus(count: 3)
            }
        }
        
        // ステップ5: 通常の経験値を加算（投稿ごとに+10）
        UserService.shared.addExperience(points: 10)

        // ステップ6: 投稿回数に応じた報酬チェック（称号やフレーム獲得）
        try? await incrementEmotionPostCountAndAward(userID: currentUserID)
        
        // 都道府県ゲージを更新
        if let latitude = latitude, let longitude = longitude {
            do {
                try await updatePrefectureGauge(
                    latitude: latitude,
                    longitude: longitude,
                    emotionLevel: level,
                    authorID: currentUserID
                )
                print("✅ ゲージ更新成功: 座標(\(latitude), \(longitude))")
            } catch {
                print("❌ ゲージ更新エラー: \(error.localizedDescription)")
            }
            
            // モヤイベントの処理
            if level.rawValue < 0 {
                // 負の感情の場合：イベント発生チェック
                try? await checkAndCreateMistEvent(latitude: latitude, longitude: longitude)
            } else if level.rawValue > 0 {
                // 正の感情の場合：モヤを減らす
                try? await reduceMistEventHP(
                    latitude: latitude,
                    longitude: longitude,
                    emotionLevel: level,
                    authorID: currentUserID,
                    isMistCleanupPost: isMistCleanup
                )
            }
        }
        
        return spotBonus
    }

    // 感情投稿回数をカウントし、節目で称号/フレーム付与
    private func incrementEmotionPostCountAndAward(userID: String) async throws {
        let docRef = db.collection(userRegistrationsCollectionName).document(userID)
        let document = try await docRef.getDocument()
        let current = (document.get("emotionPostCount") as? Int) ?? 0
        let newCount = current + 1

        try await docRef.setData([
            "emotionPostCount": newCount
        ], merge: true)

        let milestones = [10, 20, 40, 50, 100]
        if milestones.contains(newCount) {
            let title = "感情投稿\(newCount)回達成"
            let frameID = "post_\(newCount)"
            try await addUserTitle(userID: userID, title: title)
            try await addUserIconFrame(userID: userID, frameID: frameID)
            
            // 報酬を計算（投稿回数に応じて増加）
            let expReward = newCount * 5  // 10回=50 XP, 20回=100 XP, など
            let postBonusReward = max(1, newCount / 50)  // 50回=1回, 100回=2回
            
            // 報酬を付与
            UserService.shared.addExperience(points: expReward)
            UserService.shared.addPostCountBonus(count: postBonusReward)
            
            print("🎉 投稿\(newCount)回達成報酬: 経験値+\(expReward), 投稿回数+\(postBonusReward)")
            
            try? await createNotification(
                type: .missionCleared,
                title: "ミッション達成",
                body: "感情投稿\(newCount)回達成！経験値+\(expReward), 投稿回数+\(postBonusReward)回を獲得",
                relatedID: "post_\(newCount)",
                toUserID: userID
            )
        }
    }

    // モヤ浄化専用の投稿（履歴・地図・ミニゲームに影響しない）
    @available(*, deprecated, message: "Use postEmotion with isMistCleanup parameter instead")
    func postMistCleanup(level: EmotionLevel, latitude: Double, longitude: Double) async throws {
        _ = try await postEmotion(
            level: level,
            visualType: .glow,
            latitude: latitude,
            longitude: longitude,
            isPublicPost: true,
            comment: nil,
            isMistCleanup: true
        )
    }

    // ミニゲーム専用の投稿（履歴・地図に残らない）
    func postMiniGame(level: EmotionLevel, latitude: Double, longitude: Double) async throws {
        try await ensureUserNotFrozen()
        let currentUserID = UserService.shared.currentUserID
        try await updatePrefectureGauge(
            latitude: latitude,
            longitude: longitude,
            emotionLevel: level,
            authorID: currentUserID
        )
    }

    func fetchRecentEmotions(lastHours: Int = 6, includeOnlyFriends: Bool = false) async throws -> [EmotionPost] {
        let currentUserID = UserService.shared.currentUserID
        let since = Date().addingTimeInterval(-Double(lastHours) * 60 * 60)
        
        // みんな+友達モードの場合は100件までに制限（パフォーマンス向上のため）
        let limitCount = includeOnlyFriends ? nil : 200 // フィルタリング後に100件になるように多めに取得
        var query = db.collection(collectionName)
            .whereField("createdAt", isGreaterThanOrEqualTo: Timestamp(date: since))
            .order(by: "createdAt", descending: true)
        
        if let limit = limitCount {
            query = query.limit(to: limit)
        }
        
        let snapshot = try await query.getDocuments()

        // 友達一覧を取得（友達のみのフィルタリングに必要）
        var friendIDs: Set<String> = []
        if includeOnlyFriends {
            let friends = try await fetchFriends()
            friendIDs = Set(friends.map { $0.userID })
        } else {
            // みんな+友達モードの場合も、公開設定を確認するために友達一覧を取得
            let friends = try await fetchFriends()
            friendIDs = Set(friends.map { $0.userID })
        }
        
        // ユーザーの公開設定を一括取得
        let authorIDs = snapshot.documents.compactMap { $0.get("authorID") as? String }
        let uniqueAuthorIDs = Array(Set(authorIDs))
        let publicSettings = try await getUsersPublicSettings(userIDs: uniqueAuthorIDs)
        
        // ブロックされたユーザーIDのリストを取得
        let blockedUserIDs = try await getBlockedUserIDs()
        let blockedSet = Set(blockedUserIDs)

        let visibilityCutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let filteredPosts = snapshot.documents.compactMap { doc -> EmotionPost? in
            guard
                let idString = doc.get("id") as? String,
                let id = UUID(uuidString: idString),
                let levelValue = doc.get("level") as? Int,
                let visualRaw = doc.get("visualType") as? String,
                let createdAt = (doc.get("createdAt") as? Timestamp)?.dateValue(),
                createdAt >= visibilityCutoff
            else {
                return nil
            }
            
            // デバッグ：ドキュメントIDとIDフィールドを比較
            let docID = doc.documentID
            if docID.lowercased() != idString.lowercased() {
                print("⚠️ IDの不一致: ドキュメントID=\(docID), IDフィールド=\(idString)")
            }

            let level = EmotionLevel.clamped(levelValue)
            guard let visualType = EmotionVisualType(rawValue: visualRaw) else { return nil }
            
            let latitude = doc.get("latitude") as? Double
            let longitude = doc.get("longitude") as? Double
            let likeCount = doc.get("likeCount") as? Int ?? 0
            let likedBy = doc.get("likedBy") as? [String] ?? []
            let authorID = doc.get("authorID") as? String
            let isPublicPost = doc.get("isPublicPost") as? Bool ?? true // デフォルトは公開
            let postComment = doc.get("comment") as? String
            let isMistCleanup = doc.get("isMistCleanup") as? Bool ?? false
            
            // 公開設定によるフィルタリング
            if let authorID = authorID {
                // ブロックされたユーザーの投稿を除外
                if blockedSet.contains(authorID) {
                    return nil
                }
                
                // 自分の投稿は常に表示
                if authorID == currentUserID {
                    // そのまま続行
                } else if includeOnlyFriends {
                    // 友達のみモード：友達の投稿のみ表示
                    if !friendIDs.contains(authorID) {
                        return nil
                    }
                } else {
                    // みんな+友達モード：投稿が公開設定で、かつ（アカウントが公開または友達）の場合に表示
                    let isPublicAccount = publicSettings[authorID] ?? true // デフォルトは公開
                    if !isPublicPost {
                        // 投稿が非公開の場合、友達のみ表示
                        if !friendIDs.contains(authorID) {
                            return nil
                        }
                    } else {
                        // 投稿が公開の場合、アカウントが公開または友達の場合に表示
                        if !isPublicAccount && !friendIDs.contains(authorID) {
                            return nil
                        }
                    }
                }
            } else {
                // authorIDがない投稿は非表示（安全のため）
                return nil
            }
            
            // 応援情報を取得
            var supports: [SupportInfo] = []
            if let supportsData = doc.get("supports") as? [[String: Any]] {
                supports = supportsData.compactMap { supportDict in
                    guard
                        let emojiRaw = supportDict["emoji"] as? String,
                        let emoji = SupportEmoji(rawValue: emojiRaw),
                        let userID = supportDict["userID"] as? String,
                        let timestamp = (supportDict["timestamp"] as? Timestamp)?.dateValue()
                    else {
                        return nil
                    }
                    return SupportInfo(emoji: emoji, userID: userID, timestamp: timestamp)
                }
            }

            return EmotionPost(id: id, level: level, visualType: visualType, createdAt: createdAt, latitude: latitude, longitude: longitude, likeCount: likeCount, likedBy: likedBy, supports: supports, authorID: authorID, isPublicPost: isPublicPost, comment: postComment, isMistCleanup: isMistCleanup)
        }
        
        // みんな+友達モードの場合は100件までに制限
        if !includeOnlyFriends {
            return Array(filteredPosts.prefix(100))
        }
        
        return filteredPosts
    }

    // 管理者用：全投稿を取得（公開設定フィルタなし）
    func fetchAllPosts(limit: Int = 200) async throws -> [EmotionPost] {
        let snapshot = try await db.collection(collectionName)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap { doc -> EmotionPost? in
            guard
                let idString = doc.get("id") as? String,
                let id = UUID(uuidString: idString),
                let levelValue = doc.get("level") as? Int,
                let visualRaw = doc.get("visualType") as? String,
                let createdAt = (doc.get("createdAt") as? Timestamp)?.dateValue()
            else {
                return nil
            }

            let level = EmotionLevel.clamped(levelValue)
            guard let visualType = EmotionVisualType(rawValue: visualRaw) else { return nil }

            let latitude = doc.get("latitude") as? Double
            let longitude = doc.get("longitude") as? Double
            let likeCount = doc.get("likeCount") as? Int ?? 0
            let likedBy = doc.get("likedBy") as? [String] ?? []
            let authorID = doc.get("authorID") as? String
            let isPublicPost = doc.get("isPublicPost") as? Bool ?? true
            let postComment = doc.get("comment") as? String

            var supports: [SupportInfo] = []
            if let supportsData = doc.get("supports") as? [[String: Any]] {
                supports = supportsData.compactMap { supportDict in
                    guard
                        let emojiRaw = supportDict["emoji"] as? String,
                        let emoji = SupportEmoji(rawValue: emojiRaw),
                        let userID = supportDict["userID"] as? String,
                        let timestamp = (supportDict["timestamp"] as? Timestamp)?.dateValue()
                    else {
                        return nil
                    }
                    return SupportInfo(emoji: emoji, userID: userID, timestamp: timestamp)
                }
            }

            let isMistCleanup = doc.get("isMistCleanup") as? Bool ?? false
            return EmotionPost(
                id: id,
                level: level,
                visualType: visualType,
                createdAt: createdAt,
                latitude: latitude,
                longitude: longitude,
                likeCount: likeCount,
                likedBy: likedBy,
                supports: supports,
                authorID: authorID,
                isPublicPost: isPublicPost,
                comment: postComment,
                isMistCleanup: isMistCleanup
            )
        }
    }

    // 投稿を取得（ID指定）
    func fetchPost(postID: UUID) async throws -> EmotionPost {
        // IDフィールドでクエリ検索（大文字小文字両方対応）
        let lowercaseID = postID.uuidString.lowercased()
        let normalID = postID.uuidString
        
        var snapshot = try await db.collection(collectionName)
            .whereField("id", isEqualTo: lowercaseID)
            .limit(to: 1)
            .getDocuments()
        
        if snapshot.documents.isEmpty {
            snapshot = try await db.collection(collectionName)
                .whereField("id", isEqualTo: normalID)
                .limit(to: 1)
                .getDocuments()
        }
        
        guard let doc = snapshot.documents.first, doc.exists else {
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "投稿が見つかりません"])
        }
        
        guard
            let idString = doc.get("id") as? String,
            let id = UUID(uuidString: idString),
            let levelValue = doc.get("level") as? Int,
            let visualRaw = doc.get("visualType") as? String,
            let createdAt = (doc.get("createdAt") as? Timestamp)?.dateValue()
        else {
            throw NSError(domain: "FirestoreService", code: 500, userInfo: [NSLocalizedDescriptionKey: "投稿データの取得に失敗しました"])
        }
        
        let level = EmotionLevel.clamped(levelValue)
        guard let visualType = EmotionVisualType(rawValue: visualRaw) else {
            throw NSError(domain: "FirestoreService", code: 500, userInfo: [NSLocalizedDescriptionKey: "visualTypeの変換に失敗しました"])
        }
        
        let latitude = doc.get("latitude") as? Double
        let longitude = doc.get("longitude") as? Double
        let likeCount = doc.get("likeCount") as? Int ?? 0
        let likedBy = doc.get("likedBy") as? [String] ?? []
        let authorID = doc.get("authorID") as? String ?? ""
        let isPublicPost = doc.get("isPublicPost") as? Bool ?? true
        let postComment = doc.get("comment") as? String
        
        // 応援情報を取得
        var supports: [SupportInfo] = []
        if let supportsData = doc.get("supports") as? [[String: Any]] {
            supports = supportsData.compactMap { supportDict in
                guard
                    let emojiRaw = supportDict["emoji"] as? String,
                    let emoji = SupportEmoji(rawValue: emojiRaw),
                    let userID = supportDict["userID"] as? String,
                    let timestamp = (supportDict["timestamp"] as? Timestamp)?.dateValue()
                else {
                    return nil
                }
                return SupportInfo(emoji: emoji, userID: userID, timestamp: timestamp)
            }
        }
        
        let isMistCleanup = doc.get("isMistCleanup") as? Bool ?? false
        return EmotionPost(
            id: id,
            level: level,
            visualType: visualType,
            createdAt: createdAt,
            latitude: latitude,
            longitude: longitude,
            likeCount: likeCount,
            likedBy: likedBy,
            supports: supports,
            authorID: authorID,
            isPublicPost: isPublicPost,
            comment: postComment,
            isMistCleanup: isMistCleanup
        )
    }
    
    // 管理者用：投稿を削除
    func adminDeletePost(postID: UUID) async throws {
        // IDフィールドでクエリ検索（大文字小文字両方対応）
        let lowercaseID = postID.uuidString.lowercased()
        let normalID = postID.uuidString
        
        var snapshot = try await db.collection(collectionName)
            .whereField("id", isEqualTo: lowercaseID)
            .limit(to: 1)
            .getDocuments()
        
        if snapshot.documents.isEmpty {
            snapshot = try await db.collection(collectionName)
                .whereField("id", isEqualTo: normalID)
                .limit(to: 1)
                .getDocuments()
        }
        
        guard let doc = snapshot.documents.first else {
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "投稿が見つかりません"])
        }
        
        try await doc.reference.delete()
        print("✅ 管理者が投稿を削除しました: \(doc.documentID)")
    }
    
    // 自分の投稿を削除
    func deletePost(postID: UUID) async throws {
        let currentUserID = UserService.shared.currentUserID
        
        // IDフィールドでクエリ検索（大文字小文字両方対応）
        let lowercaseID = postID.uuidString.lowercased()
        let normalID = postID.uuidString
        
        var snapshot = try await db.collection(collectionName)
            .whereField("id", isEqualTo: lowercaseID)
            .limit(to: 1)
            .getDocuments()
        
        if snapshot.documents.isEmpty {
            snapshot = try await db.collection(collectionName)
                .whereField("id", isEqualTo: normalID)
                .limit(to: 1)
                .getDocuments()
        }
        
        guard let document = snapshot.documents.first, document.exists else {
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "投稿が見つかりません"])
        }
        
        let postRef = document.reference
        
        // 自分の投稿か確認
        if let authorID = document.get("authorID") as? String, authorID == currentUserID {
            try await postRef.delete()
            print("✅ 投稿を削除しました: \(postID.uuidString)")
        } else {
            throw NSError(domain: "FirestoreService", code: 403, userInfo: [NSLocalizedDescriptionKey: "自分の投稿のみ削除できます"])
        }
    }
    
    func fetchMyPosts() async throws -> [EmotionPost] {
        let currentUserID = UserService.shared.currentUserID
        
        // 24時間以内の投稿のみを取得
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        
        // インデックスが不要になるように、まずauthorIDでフィルタリングしてから
        // クライアント側でソートする
        let snapshot = try await db.collection(collectionName)
            .whereField("authorID", isEqualTo: currentUserID)
            .getDocuments()

        let posts = snapshot.documents.compactMap { doc -> EmotionPost? in
            guard
                let idString = doc.get("id") as? String,
                let id = UUID(uuidString: idString),
                let levelValue = doc.get("level") as? Int,
                let visualRaw = doc.get("visualType") as? String,
                let createdAt = (doc.get("createdAt") as? Timestamp)?.dateValue(),
                let authorID = doc.get("authorID") as? String,
                authorID == currentUserID
            else {
                return nil
            }
            
            // 12時間以内の投稿のみをフィルタリング
            guard createdAt >= cutoff else {
                return nil
            }

            let level = EmotionLevel.clamped(levelValue)
            guard let visualType = EmotionVisualType(rawValue: visualRaw) else { return nil }
            
            let latitude = doc.get("latitude") as? Double
            let longitude = doc.get("longitude") as? Double
            let likeCount = doc.get("likeCount") as? Int ?? 0
            let likedBy = doc.get("likedBy") as? [String] ?? []
            
            // 応援情報を取得
            var supports: [SupportInfo] = []
            if let supportsData = doc.get("supports") as? [[String: Any]] {
                supports = supportsData.compactMap { supportDict in
                    guard
                        let emojiRaw = supportDict["emoji"] as? String,
                        let emoji = SupportEmoji(rawValue: emojiRaw),
                        let userID = supportDict["userID"] as? String,
                        let timestamp = (supportDict["timestamp"] as? Timestamp)?.dateValue()
                    else {
                        return nil
                    }
                    return SupportInfo(emoji: emoji, userID: userID, timestamp: timestamp)
                }
            }
            
            let isPublicPost = doc.get("isPublicPost") as? Bool ?? true // デフォルトは公開
            let comment = doc.get("comment") as? String
            let isMistCleanup = doc.get("isMistCleanup") as? Bool ?? false
            
            return EmotionPost(id: id, level: level, visualType: visualType, createdAt: createdAt, latitude: latitude, longitude: longitude, likeCount: likeCount, likedBy: likedBy, supports: supports, authorID: authorID, isPublicPost: isPublicPost, comment: comment, isMistCleanup: isMistCleanup)
        }
        
        // クライアント側で作成日時の降順にソート（新着順）
        return posts.sorted { $0.createdAt > $1.createdAt }
    }
    
    func fetchEmotionsInRegion(centerLatitude: Double, centerLongitude: Double, radiusKm: Double = 10.0, includeOnlyFriends: Bool = false) async throws -> [EmotionPost] {
        // 簡易的な範囲検索（実際の実装ではGeoFirestoreなどを使うとより正確）
        // ここでは全件取得してフィルタリング（小規模なデータ向け）
        let allPosts = try await fetchRecentEmotions(lastHours: 24, includeOnlyFriends: includeOnlyFriends)
        
        return allPosts.filter { post in
            guard let lat = post.latitude, let lon = post.longitude else { return false }
            
            let distance = calculateDistance(
                lat1: centerLatitude, lon1: centerLongitude,
                lat2: lat, lon2: lon
            )
            
            return distance <= radiusKm
        }
    }
    
    // 投稿IDで投稿を取得
    func fetchPostByID(postID: UUID) async throws -> EmotionPost {
        // IDフィールドでクエリ検索（大文字小文字両方対応）
        let lowercaseID = postID.uuidString.lowercased()
        let normalID = postID.uuidString
        
        var snapshot = try await db.collection(collectionName)
            .whereField("id", isEqualTo: lowercaseID)
            .limit(to: 1)
            .getDocuments()
        
        if snapshot.documents.isEmpty {
            snapshot = try await db.collection(collectionName)
                .whereField("id", isEqualTo: normalID)
                .limit(to: 1)
                .getDocuments()
        }
        
        guard let doc = snapshot.documents.first,
              doc.exists,
              let levelValue = doc.get("level") as? Int,
              let visualRaw = doc.get("visualType") as? String,
              let createdAtTimestamp = doc.get("createdAt") as? Timestamp else {
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "投稿が見つかりません"])
        }
        
        let level = EmotionLevel.clamped(levelValue)
        let visualType = EmotionVisualType(rawValue: visualRaw) ?? .glow
        let createdAt = createdAtTimestamp.dateValue()
        let latitude = doc.get("latitude") as? Double
        let longitude = doc.get("longitude") as? Double
        let likeCount = doc.get("likeCount") as? Int ?? 0
        let likedBy = doc.get("likedBy") as? [String] ?? []
        
        // 応援データを取得
        let supportsData = doc.get("supports") as? [[String: Any]] ?? []
        let supports = supportsData.compactMap { data -> SupportInfo? in
            guard let emojiRaw = data["emoji"] as? String,
                  let emoji = SupportEmoji(rawValue: emojiRaw),
                  let userID = data["userID"] as? String,
                  let timestamp = data["timestamp"] as? Timestamp else {
                return nil
            }
            return SupportInfo(emoji: emoji, userID: userID, timestamp: timestamp.dateValue())
        }
        
        let authorID = doc.get("authorID") as? String
        let isPublicPost = doc.get("isPublicPost") as? Bool ?? true
        let comment = doc.get("comment") as? String
        
        let isMistCleanup = doc.get("isMistCleanup") as? Bool ?? false
        return EmotionPost(
            id: postID,
            level: level,
            visualType: visualType,
            createdAt: createdAt,
            latitude: latitude,
            longitude: longitude,
            likeCount: likeCount,
            likedBy: likedBy,
            supports: supports,
            authorID: authorID,
            isPublicPost: isPublicPost,
            comment: comment,
            isMistCleanup: isMistCleanup
        )
    }
    
    private func calculateDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371.0 // 地球の半径（km）
        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180.0) * cos(lat2 * .pi / 180.0) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }
    
    func toggleLike(postID: UUID) async throws {
        let currentUserID = UserService.shared.currentUserID
        
        // IDフィールドでクエリ検索（大文字小文字両方対応）
        let lowercaseID = postID.uuidString.lowercased()
        let normalID = postID.uuidString
        
        var snapshot = try await db.collection(collectionName)
            .whereField("id", isEqualTo: lowercaseID)
            .limit(to: 1)
            .getDocuments()
        
        if snapshot.documents.isEmpty {
            snapshot = try await db.collection(collectionName)
                .whereField("id", isEqualTo: normalID)
                .limit(to: 1)
                .getDocuments()
        }
        
        guard let document = snapshot.documents.first, document.exists else {
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "投稿が見つかりません"])
        }
        
        let postRef = document.reference
        
        let authorID = document.get("authorID") as? String
        var likedBy = document.get("likedBy") as? [String] ?? []
        var likeCount = document.get("likeCount") as? Int ?? 0
        
        if let index = likedBy.firstIndex(of: currentUserID) {
            // いいねを削除
            likedBy.remove(at: index)
            likeCount = max(0, likeCount - 1)
        } else {
            // いいねを追加
            likedBy.append(currentUserID)
            likeCount += 1
            
            // 通知を保存（自分の投稿でない場合のみ）
            if let authorID = authorID, authorID != currentUserID {
                do {
                    try await createNotification(
                        type: .like,
                        title: "いいね",
                        body: "\(likeCount)人がいいねしました",
                        relatedID: postID.uuidString,
                        toUserID: authorID
                    )
                } catch {
                    print("❌ いいね通知の作成に失敗: \(error.localizedDescription)")
                }
            }
        }
        
        // 更新
        try await postRef.updateData([
            "likedBy": likedBy,
            "likeCount": likeCount
        ])
    }
    
    func addSupport(postID: UUID, emoji: SupportEmoji, post: EmotionPost? = nil) async throws -> Int {
        let currentUserID = UserService.shared.currentUserID
        
        print("🔍 投稿を検索中: postID=\(postID.uuidString)")
        print("🔍 検索するコレクション: \(collectionName)")
        
        var foundDocument: DocumentSnapshot? = nil
        
        // もし投稿オブジェクトが渡されていれば、その情報を使って検索
        if let post = post, let createdAt = post.createdAt as Date? {
            print("🔍 投稿オブジェクトから検索: createdAt=\(createdAt)")
            
            // 作成日時の前後1時間の範囲で検索（より確実）
            let before = createdAt.addingTimeInterval(-3600)
            let after = createdAt.addingTimeInterval(3600)
            
            let snapshot = try await db.collection(collectionName)
                .whereField("createdAt", isGreaterThan: Timestamp(date: before))
                .whereField("createdAt", isLessThan: Timestamp(date: after))
                .getDocuments()
            
            print("🔍 作成日時での検索結果: \(snapshot.documents.count)件")
            
            // IDが一致する投稿を探す
            let targetIDLower = postID.uuidString.lowercased()
            
            for doc in snapshot.documents {
                let storedID = doc.get("id") as? String ?? ""
                let docID = doc.documentID
                
                if storedID.lowercased() == targetIDLower || docID.lowercased() == targetIDLower {
                    print("✅ 投稿を発見: ドキュメントID=\(docID), IDフィールド=\(storedID)")
                    foundDocument = doc
                    break
                }
            }
        }
        
        // 投稿オブジェクトが渡されていないか、見つからなかった場合は従来の方法で検索
        if foundDocument == nil {
            print("🔍 従来の方法で検索中...")
            
            // 24時間以内の投稿から検索（制限なし）
            let since = Date().addingTimeInterval(-24 * 60 * 60)
            let allSnapshot = try await db.collection(collectionName)
                .whereField("createdAt", isGreaterThanOrEqualTo: Timestamp(date: since))
                .getDocuments()
            
            print("🔍 取得した投稿数（12時間以内）: \(allSnapshot.documents.count)件")
            
            let targetIDLower = postID.uuidString.lowercased()
            
            for doc in allSnapshot.documents {
                let storedID = doc.get("id") as? String ?? ""
                let docID = doc.documentID
                
                if storedID.lowercased() == targetIDLower || docID.lowercased() == targetIDLower {
                    print("✅ 投稿を発見: ドキュメントID=\(docID), IDフィールド=\(storedID)")
                    foundDocument = doc
                    break
                }
            }
            
            // それでも見つからない場合、24時間以内で検索
            if foundDocument == nil {
                print("🔍 12時間以内で見つからないため、24時間以内で検索...")
                let since24h = Date().addingTimeInterval(-24 * 60 * 60)
                let snapshot24h = try await db.collection(collectionName)
                    .whereField("createdAt", isGreaterThanOrEqualTo: Timestamp(date: since24h))
                    .getDocuments()
                
                print("🔍 取得した投稿数（24時間以内）: \(snapshot24h.documents.count)件")
                
                for doc in snapshot24h.documents {
                    let storedID = doc.get("id") as? String ?? ""
                    let docID = doc.documentID
                    
                    if storedID.lowercased() == targetIDLower || docID.lowercased() == targetIDLower {
                        print("✅ 投稿を発見（24時間以内）: ドキュメントID=\(docID), IDフィールド=\(storedID)")
                        foundDocument = doc
                        break
                    }
                }
            }
        }
        
        guard let document = foundDocument, document.exists else {
            print("❌ 投稿が見つかりません: postID=\(postID.uuidString)")
            print("❌ 検索したコレクション: \(collectionName)")
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "投稿が見つかりません"])
        }
        
        let postRef = document.reference
        
        let authorID = document.get("authorID") as? String
        let levelValue = document.get("level") as? Int ?? 0
        let level = EmotionLevel.clamped(levelValue)
        let isSadEmotion = level.rawValue < 0
        
        var supports: [SupportInfo] = []
        if let supportsData = document.get("supports") as? [[String: Any]] {
            supports = supportsData.compactMap { supportDict in
                guard
                    let emojiRaw = supportDict["emoji"] as? String,
                    let emoji = SupportEmoji(rawValue: emojiRaw),
                    let userID = supportDict["userID"] as? String,
                    let timestamp = (supportDict["timestamp"] as? Timestamp)?.dateValue()
                else {
                    return nil
                }
                return SupportInfo(emoji: emoji, userID: userID, timestamp: timestamp)
            }
        }
        
        // 既に応援している場合は何もせずに現在のカウントを返す（一人一回まで）
        let wasAlreadySupporting = supports.contains { $0.userID == currentUserID }
        if wasAlreadySupporting {
            print("⚠️ ユーザー\(currentUserID)は既にこの投稿を応援済みです")
            return supports.count
        }
        
        // 新しい応援を追加
        let newSupport = SupportInfo(emoji: emoji, userID: currentUserID, timestamp: Date())
        supports.append(newSupport)
        
        print("✅ 新しい応援を追加: postID=\(postID.uuidString), userID=\(currentUserID), emoji=\(emoji.rawValue)")
        print("✅ 現在の応援数: \(supports.count)")
        
        // Firestore用のデータ形式に変換
        let supportsData: [[String: Any]] = supports.map { support in
            [
                "emoji": support.emoji.rawValue,
                "userID": support.userID,
                "timestamp": Timestamp(date: support.timestamp)
            ]
        }
        
        print("✅ Firestoreに保存するデータ: \(supportsData)")
        
        // 更新
        try await postRef.updateData([
            "supports": supportsData
        ])
        
        print("✅ Firestoreへの保存が完了しました")
        
        // 通知を保存（自分の投稿でない場合のみ）
        if let authorID = authorID, authorID != currentUserID {
            do {
                // 共感/応援したユーザーの名前を取得
                let supporterDoc = try await db.collection(usersCollectionName).document(currentUserID).getDocument()
                // 複数のフィールド名をチェック
                let supporterName = supporterDoc.data()?["userName"] as? String 
                    ?? supporterDoc.data()?["username"] as? String
                    ?? supporterDoc.data()?["name"] as? String
                    ?? "ユーザー"
                
                print("🔍 共感通知作成: ユーザーID=\(currentUserID), 取得した名前=\(supporterName)")
                print("   - Firestoreデータ: \(supporterDoc.data() ?? [:])")
                
                try await createNotification(
                    type: .support,
                    title: isSadEmotion ? "応援されました" : "共感されました",
                    body: isSadEmotion ? "\(supporterName)さんがあなたの投稿を応援しました" : "\(supporterName)さんがあなたの投稿に共感しました",
                    relatedID: document.documentID,
                    toUserID: authorID
                )
            } catch {
                print("❌ 応援通知の作成に失敗: \(error.localizedDescription)")
            }
        }
        
        return supports.count
    }
    
    func removeSupport(postID: UUID, post: EmotionPost? = nil) async throws -> Int {
        let currentUserID = UserService.shared.currentUserID
        
        print("🔍 共感削除：投稿を検索中: postID=\(postID.uuidString)")
        
        var foundDocument: DocumentSnapshot? = nil
        
        // もし投稿オブジェクトが渡されていれば、その情報を使って検索
        if let post = post, let createdAt = post.createdAt as Date? {
            print("🔍 投稿オブジェクトから検索: createdAt=\(createdAt)")
            
            // 作成日時の前後1時間の範囲で検索
            let before = createdAt.addingTimeInterval(-3600)
            let after = createdAt.addingTimeInterval(3600)
            
            let snapshot = try await db.collection(collectionName)
                .whereField("createdAt", isGreaterThan: Timestamp(date: before))
                .whereField("createdAt", isLessThan: Timestamp(date: after))
                .getDocuments()
            
            print("🔍 作成日時での検索結果: \(snapshot.documents.count)件")
            
            // IDが一致する投稿を探す
            let targetIDLower = postID.uuidString.lowercased()
            
            for doc in snapshot.documents {
                let storedID = doc.get("id") as? String ?? ""
                let docID = doc.documentID
                
                if storedID.lowercased() == targetIDLower || docID.lowercased() == targetIDLower {
                    print("✅ 投稿を発見: ドキュメントID=\(docID), IDフィールド=\(storedID)")
                    foundDocument = doc
                    break
                }
            }
        }
        
        // 投稿オブジェクトが渡されていないか、見つからなかった場合は従来の方法で検索
        if foundDocument == nil {
            print("🔍 従来の方法で検索中...")
            
            // 24時間以内の投稿から検索
            let since = Date().addingTimeInterval(-24 * 60 * 60)
            let allSnapshot = try await db.collection(collectionName)
                .whereField("createdAt", isGreaterThanOrEqualTo: Timestamp(date: since))
                .getDocuments()
            
            print("🔍 取得した投稿数（12時間以内）: \(allSnapshot.documents.count)件")
            
            let targetIDLower = postID.uuidString.lowercased()
            
            for doc in allSnapshot.documents {
                let storedID = doc.get("id") as? String ?? ""
                let docID = doc.documentID
                
                if storedID.lowercased() == targetIDLower || docID.lowercased() == targetIDLower {
                    print("✅ 投稿を発見: ドキュメントID=\(docID), IDフィールド=\(storedID)")
                    foundDocument = doc
                    break
                }
            }
        }
        
        guard let document = foundDocument, document.exists else {
            print("❌ 投稿が見つかりません: postID=\(postID.uuidString)")
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "投稿が見つかりません"])
        }
        
        let postRef = document.reference
        
        var supports: [SupportInfo] = []
        if let supportsData = document.get("supports") as? [[String: Any]] {
            supports = supportsData.compactMap { supportDict in
                guard
                    let emojiRaw = supportDict["emoji"] as? String,
                    let emoji = SupportEmoji(rawValue: emojiRaw),
                    let userID = supportDict["userID"] as? String,
                    let timestamp = (supportDict["timestamp"] as? Timestamp)?.dateValue()
                else {
                    return nil
                }
                return SupportInfo(emoji: emoji, userID: userID, timestamp: timestamp)
            }
        }
        
        // 現在のユーザーの応援を削除
        supports.removeAll { $0.userID == currentUserID }
        
        // Firestore用のデータ形式に変換
        let supportsData: [[String: Any]] = supports.map { support in
            [
                "emoji": support.emoji.rawValue,
                "userID": support.userID,
                "timestamp": Timestamp(date: support.timestamp)
            ]
        }
        
        // 更新
        try await postRef.updateData([
            "supports": supportsData
        ])
        
        return supports.count
    }
    
    // MARK: - 友達機能
    
    // 友達申請を送信
    func sendFriendRequest(to userID: String) async throws {
        let currentUserID = UserService.shared.currentUserID
        
        // 既に友達関係があるかチェック（双方向）
        let friendshipSnapshot1 = try await db.collection("friendships")
            .whereField("userID1", isEqualTo: currentUserID)
            .whereField("userID2", isEqualTo: userID)
            .limit(to: 1)
            .getDocuments()
        
        let friendshipSnapshot2 = try await db.collection("friendships")
            .whereField("userID1", isEqualTo: userID)
            .whereField("userID2", isEqualTo: currentUserID)
            .limit(to: 1)
            .getDocuments()
        
        if !friendshipSnapshot1.documents.isEmpty || !friendshipSnapshot2.documents.isEmpty {
            throw NSError(domain: "FirestoreService", code: 400, userInfo: [NSLocalizedDescriptionKey: "既に友達関係があります"])
        }
        
        // 既に保留中の申請があるかチェック（自分から相手への申請）
        let pendingSentSnapshot = try await db.collection("friendRequests")
            .whereField("fromUserID", isEqualTo: currentUserID)
            .whereField("toUserID", isEqualTo: userID)
            .whereField("status", isEqualTo: "pending")
            .limit(to: 1)
            .getDocuments()
        
        if !pendingSentSnapshot.documents.isEmpty {
            throw NSError(domain: "FirestoreService", code: 400, userInfo: [NSLocalizedDescriptionKey: "既に友達申請を送信しています"])
        }
        
        // 以前の申請（accepted/rejected）を削除してから新しい申請を作成
        // 友達解除後は、以前の申請レコードを削除して新しい申請を送信できるようにする
        let existingRequestsSnapshot = try await db.collection("friendRequests")
            .whereField("fromUserID", isEqualTo: currentUserID)
            .whereField("toUserID", isEqualTo: userID)
            .getDocuments()
        
        // 既存の申請レコードを削除（友達解除後、新しい申請を送信できるようにするため）
        for doc in existingRequestsSnapshot.documents {
            try await doc.reference.delete()
        }
        
        let requestID = UUID().uuidString
        
        let data: [String: Any] = [
            "id": requestID,
            "fromUserID": currentUserID,
            "toUserID": userID,
            "status": "pending",
            "createdAt": Timestamp(date: Date())
        ]
        
        try await db.collection("friendRequests")
            .document(requestID)
            .setData(data)
        
        print("✅ 友達申請を送信しました: \(requestID)")
        // 注意: 通知はFriendRequestNotificationServiceのリアルタイムリスナーが自動的に作成します
        // ここで通知を作成すると重複するため、削除しました
    }
    
    // 友達申請を取り消す（改善版: 通知も確実に削除）
    func cancelFriendRequest(to userID: String) async throws {
        let currentUserID = UserService.shared.currentUserID
        
        print("🔄 友達申請を取り消し中: fromUserID=\(currentUserID), toUserID=\(userID)")
        
        // 1. 自分が送った保留中の申請を取得
        let snapshot = try await db.collection("friendRequests")
            .whereField("fromUserID", isEqualTo: currentUserID)
            .whereField("toUserID", isEqualTo: userID)
            .whereField("status", isEqualTo: "pending")
            .getDocuments()
        
        // 申請が見つからない場合
        if snapshot.documents.isEmpty {
            print("⚠️ 取り消す友達申請が見つかりません")
            return
        }
        
        // 2. 友達申請を削除
        var deletedRequestIDs: [String] = []
        for doc in snapshot.documents {
            let requestID = doc.documentID
            deletedRequestIDs.append(requestID)
            try await doc.reference.delete()
            print("✅ 友達申請を削除しました: \(requestID)")
        }
        
        // 3. 相手に送信された友達申請の通知を削除
        // 複数の条件で検索して、確実に削除
        let notificationQueries = [
            // パターン1: type=friendRequest, toUserID=相手, relatedID=自分
            db.collection("notifications")
                .whereField("type", isEqualTo: "friendRequest")
                .whereField("toUserID", isEqualTo: userID)
                .whereField("relatedID", isEqualTo: currentUserID),
            
            // パターン2: type=friendRequest, toUserID=相手, fromUserID=自分
            db.collection("notifications")
                .whereField("type", isEqualTo: "friendRequest")
                .whereField("toUserID", isEqualTo: userID)
                .whereField("fromUserID", isEqualTo: currentUserID)
        ]
        
        var totalDeletedNotifications = 0
        for query in notificationQueries {
            do {
                let notificationSnapshot = try await query.getDocuments()
                
                for notificationDoc in notificationSnapshot.documents {
                    try await notificationDoc.reference.delete()
                    totalDeletedNotifications += 1
                    print("✅ 通知を削除しました: \(notificationDoc.documentID)")
                }
            } catch {
                print("⚠️ 通知の検索/削除中にエラー: \(error.localizedDescription)")
            }
        }
        
        print("✅ 友達申請の取り消し完了: 申請\(deletedRequestIDs.count)件、通知\(totalDeletedNotifications)件を削除")
    }
    
    // 友達申請を承認
    func acceptFriendRequest(requestID: String) async throws {
        let requestRef = db.collection("friendRequests").document(requestID)
        let document = try await requestRef.getDocument()
        
        guard document.exists,
              let fromUserID = document.get("fromUserID") as? String,
              let toUserID = document.get("toUserID") as? String else {
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "友達申請が見つかりません"])
        }
        
        // 既に友達関係があるかチェック
        let existingFriendship1 = try await db.collection("friendships")
            .whereField("userID1", isEqualTo: fromUserID)
            .whereField("userID2", isEqualTo: toUserID)
            .limit(to: 1)
            .getDocuments()
        
        let existingFriendship2 = try await db.collection("friendships")
            .whereField("userID1", isEqualTo: toUserID)
            .whereField("userID2", isEqualTo: fromUserID)
            .limit(to: 1)
            .getDocuments()
        
        // 既に友達関係がある場合は、申請のステータスだけ更新して終了
        if !existingFriendship1.documents.isEmpty || !existingFriendship2.documents.isEmpty {
            try await requestRef.updateData([
                "status": "accepted",
                "acceptedAt": Timestamp(date: Date())
            ])
            return
        }
        
        // 申請のステータスを更新
        try await requestRef.updateData([
            "status": "accepted",
            "acceptedAt": Timestamp(date: Date())
        ])
        
        // 友達関係を両方向に作成
        let currentUserID = UserService.shared.currentUserID
        let friend1ID = UUID().uuidString
        let friend2ID = UUID().uuidString
        
        // 申請者から承認者への友達関係
        try await db.collection("friendships")
            .document(friend1ID)
            .setData([
                "id": friend1ID,
                "userID1": fromUserID,
                "userID2": toUserID,
                "createdAt": Timestamp(date: Date())
            ])
        
        // 承認者から申請者への友達関係（双方向）
        try await db.collection("friendships")
            .document(friend2ID)
            .setData([
                "id": friend2ID,
                "userID1": toUserID,
                "userID2": fromUserID,
                "createdAt": Timestamp(date: Date())
            ])
        
        // 元の友達申請の通知を削除（requestIDで検索して確実に削除）
        print("🔍 友達申請通知を削除中: requestID=\(requestID), toUserID=\(toUserID)")
        
        var totalDeletedNotifications = 0
        
        // パターン1: requestIDで検索（最も確実）
        do {
            let notificationSnapshot = try await db.collection("notifications")
                .whereField("type", isEqualTo: "friendRequest")
                .whereField("requestID", isEqualTo: requestID)
                .getDocuments()
            
            if !notificationSnapshot.documents.isEmpty {
                for notificationDoc in notificationSnapshot.documents {
                    try await notificationDoc.reference.delete()
                    totalDeletedNotifications += 1
                    print("✅ requestIDで友達申請通知を削除: \(notificationDoc.documentID)")
                }
            } else {
                print("⚠️ requestIDで通知が見つかりませんでした: \(requestID)")
            }
        } catch {
            print("⚠️ requestIDでの通知削除エラー: \(error.localizedDescription)")
        }
        
        // パターン2: 念のため、toUserIDとrelatedIDでも検索
        if totalDeletedNotifications == 0 {
            print("🔍 relatedIDでも検索します")
            do {
                let notificationSnapshot = try await db.collection("notifications")
                    .whereField("type", isEqualTo: "friendRequest")
                    .whereField("toUserID", isEqualTo: toUserID)
                    .whereField("relatedID", isEqualTo: fromUserID)
                    .getDocuments()
                
                for notificationDoc in notificationSnapshot.documents {
                    try await notificationDoc.reference.delete()
                    totalDeletedNotifications += 1
                    print("✅ relatedIDで友達申請通知を削除: \(notificationDoc.documentID)")
                }
            } catch {
                print("⚠️ relatedIDでの通知削除エラー: \(error.localizedDescription)")
            }
        }
        
        // 新しい友達承認通知を保存（申請者に通知）
        do {
            // 承認したユーザーの名前を取得
            let accepterDoc = try await db.collection(usersCollectionName).document(toUserID).getDocument()
            // 複数のフィールド名をチェック
            let accepterName = accepterDoc.data()?["userName"] as? String
                ?? accepterDoc.data()?["username"] as? String
                ?? accepterDoc.data()?["name"] as? String
                ?? "ユーザー"
            
            print("🔍 友達承認通知作成: ユーザーID=\(toUserID), 取得した名前=\(accepterName)")
            print("   - Firestoreデータ: \(accepterDoc.data() ?? [:])")
            print("📝 友達承認通知作成: 承認者=\(accepterName), 申請者ID=\(fromUserID)")
            
            try await createNotification(
                type: .friendAccepted,
                title: "\(accepterName)さんと友達になりました",
                body: "プロフィールから確認できます",
                relatedID: toUserID,
                toUserID: fromUserID
            )
            
            print("✅ 友達承認完了: requestID=\(requestID), 削除した通知=\(totalDeletedNotifications)件")
        } catch {
            print("❌ 友達承認通知の作成に失敗: \(error.localizedDescription)")
        }
    }
    
    // 友達申請を拒否（改善版: 通知も削除）
    func rejectFriendRequest(requestID: String) async throws {
        // 1. 友達申請のデータを取得
        let requestRef = db.collection("friendRequests").document(requestID)
        let document = try await requestRef.getDocument()
        
        guard document.exists,
              let fromUserID = document.get("fromUserID") as? String,
              let toUserID = document.get("toUserID") as? String
        else {
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "友達申請が見つかりません"])
        }
        
        print("🔄 友達申請を拒否中: requestID=\(requestID), fromUserID=\(fromUserID), toUserID=\(toUserID)")
        
        // 2. ステータスを更新
        try await requestRef.updateData([
            "status": "rejected",
            "rejectedAt": Timestamp(date: Date())
        ])
        
        // 3. 関連する通知を削除（requestIDで検索して確実に削除）
        print("🔍 友達申請通知を削除中（拒否）: requestID=\(requestID), toUserID=\(toUserID)")
        
        var totalDeletedNotifications = 0
        
        // パターン1: requestIDで検索（最も確実）
        do {
            let notificationSnapshot = try await db.collection("notifications")
                .whereField("type", isEqualTo: "friendRequest")
                .whereField("requestID", isEqualTo: requestID)
                .getDocuments()
            
            if !notificationSnapshot.documents.isEmpty {
                for notificationDoc in notificationSnapshot.documents {
                    try await notificationDoc.reference.delete()
                    totalDeletedNotifications += 1
                    print("✅ requestIDで友達申請通知を削除（拒否）: \(notificationDoc.documentID)")
                }
            } else {
                print("⚠️ requestIDで通知が見つかりませんでした（拒否）: \(requestID)")
            }
        } catch {
            print("⚠️ requestIDでの通知削除エラー（拒否）: \(error.localizedDescription)")
        }
        
        // パターン2: 念のため、toUserIDとrelatedIDでも検索
        if totalDeletedNotifications == 0 {
            print("🔍 relatedIDでも検索します（拒否）")
            do {
                let notificationSnapshot = try await db.collection("notifications")
                    .whereField("type", isEqualTo: "friendRequest")
                    .whereField("toUserID", isEqualTo: toUserID)
                    .whereField("relatedID", isEqualTo: fromUserID)
                    .getDocuments()
                
                for notificationDoc in notificationSnapshot.documents {
                    try await notificationDoc.reference.delete()
                    totalDeletedNotifications += 1
                    print("✅ relatedIDで友達申請通知を削除（拒否）: \(notificationDoc.documentID)")
                }
            } catch {
                print("⚠️ relatedIDでの通知削除エラー（拒否）: \(error.localizedDescription)")
            }
        }
        
        print("✅ 友達申請の拒否完了: requestID=\(requestID), 削除した通知=\(totalDeletedNotifications)件")
    }
    
    // 友達関係を解除
    func removeFriendship(with userID: String) async throws {
        let currentUserID = UserService.shared.currentUserID
        
        // 双方向の友達関係を削除
        // 方向1: currentUserID -> userID
        let snapshot1 = try await db.collection("friendships")
            .whereField("userID1", isEqualTo: currentUserID)
            .whereField("userID2", isEqualTo: userID)
            .getDocuments()
        
        for doc in snapshot1.documents {
            try await doc.reference.delete()
        }
        
        // 方向2: userID -> currentUserID
        let snapshot2 = try await db.collection("friendships")
            .whereField("userID1", isEqualTo: userID)
            .whereField("userID2", isEqualTo: currentUserID)
            .getDocuments()
        
        for doc in snapshot2.documents {
            try await doc.reference.delete()
        }
        
        print("✅ 友達関係を解除しました: \(currentUserID) <-> \(userID)")
    }
    
    // 友達申請の一覧を取得（自分宛ての保留中の申請）
    func fetchPendingFriendRequests() async throws -> [FriendRequest] {
        let currentUserID = UserService.shared.currentUserID
        
        let snapshot = try await db.collection("friendRequests")
            .whereField("toUserID", isEqualTo: currentUserID)
            .whereField("status", isEqualTo: "pending")
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc -> FriendRequest? in
            guard
                let id = doc.get("id") as? String,
                let fromUserID = doc.get("fromUserID") as? String,
                let toUserID = doc.get("toUserID") as? String,
                let status = doc.get("status") as? String,
                let createdAt = (doc.get("createdAt") as? Timestamp)?.dateValue()
            else {
                return nil
            }
            
            return FriendRequest(
                id: id,
                fromUserID: fromUserID,
                toUserID: toUserID,
                status: status,
                createdAt: createdAt
            )
        }
    }
    
    // 友達申請の状態を確認（特定のユーザーとの間）
    func getFriendRequestStatus(with userID: String) async throws -> FriendRequestStatus? {
        let currentUserID = UserService.shared.currentUserID
        
        print("🔍 友達関係を確認: currentUserID=\(currentUserID), targetUserID=\(userID)")
        
        // まず友達関係を確認（最優先）
        let friendshipSnapshot1 = try await db.collection("friendships")
            .whereField("userID1", isEqualTo: currentUserID)
            .whereField("userID2", isEqualTo: userID)
            .limit(to: 1)
            .getDocuments()
        
        print("🔍 友達関係チェック1: \(friendshipSnapshot1.documents.count)件")
        
        if !friendshipSnapshot1.documents.isEmpty {
            print("✅ 友達関係が見つかりました（方向1）")
            return FriendRequestStatus(status: "friends", isFromMe: nil)
        }
        
        // 逆方向もチェック
        let friendshipSnapshot2 = try await db.collection("friendships")
            .whereField("userID1", isEqualTo: userID)
            .whereField("userID2", isEqualTo: currentUserID)
            .limit(to: 1)
            .getDocuments()
        
        print("🔍 友達関係チェック2: \(friendshipSnapshot2.documents.count)件")
        
        if !friendshipSnapshot2.documents.isEmpty {
            print("✅ 友達関係が見つかりました（方向2）")
            return FriendRequestStatus(status: "friends", isFromMe: nil)
        }
        
        print("⚠️ 友達関係が見つかりませんでした")
        
        // 友達関係がない場合のみ、申請の状態を確認
        // 自分から相手への申請を確認
        let sentSnapshot = try await db.collection("friendRequests")
            .whereField("fromUserID", isEqualTo: currentUserID)
            .whereField("toUserID", isEqualTo: userID)
            .limit(to: 1)
            .getDocuments()
        
        if let doc = sentSnapshot.documents.first,
           let status = doc.get("status") as? String {
            return FriendRequestStatus(status: status, isFromMe: true)
        }
        
        // 相手から自分への申請を確認
        let receivedSnapshot = try await db.collection("friendRequests")
            .whereField("fromUserID", isEqualTo: userID)
            .whereField("toUserID", isEqualTo: currentUserID)
            .limit(to: 1)
            .getDocuments()
        
        if let doc = receivedSnapshot.documents.first,
           let status = doc.get("status") as? String {
            return FriendRequestStatus(status: status, isFromMe: false)
        }
        
        return nil
    }
    
    // 連続投稿日数を計算
    func calculateStreakDays(userID: String) async throws -> Int {
        // ユーザーの全投稿を取得（日付でグループ化するため）
        let snapshot = try await db.collection(collectionName)
            .whereField("authorID", isEqualTo: userID)
            .getDocuments()
        
        // 投稿日を日付単位でグループ化（時刻を無視）
        var postedDates: Set<String> = []
        let calendar = Calendar.current
        
        for doc in snapshot.documents {
            if let timestamp = doc.get("createdAt") as? Timestamp {
                let date = timestamp.dateValue()
                let dateString = calendar.dateComponents([.year, .month, .day], from: date)
                if let dateOnly = calendar.date(from: dateString) {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    postedDates.insert(formatter.string(from: dateOnly))
                }
            }
        }
        
        // 今日から遡って連続投稿日数をカウント
        var streakDays = 0
        var currentDate = Date()
        
        while true {
            let dateString = {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.string(from: currentDate)
            }()
            
            if postedDates.contains(dateString) {
                streakDays += 1
                // 前日に移動
                if let previousDate = calendar.date(byAdding: .day, value: -1, to: currentDate) {
                    currentDate = previousDate
                } else {
                    break
                }
            } else {
                // 今日投稿していない場合は連続が途切れる
                if streakDays == 0 {
                    // 今日投稿していない場合は0を返す
                    return 0
                }
                break
            }
        }
        
        return streakDays
    }
    
    // 特定のユーザーの投稿を取得
    func fetchUserPosts(userID: String) async throws -> [EmotionPost] {
        // order(by:)を使うとインデックスが必要な場合があるため、まずはソートなしで取得
        let snapshot = try await db.collection(collectionName)
            .whereField("authorID", isEqualTo: userID)
            .getDocuments()
        
        print("🔍 ユーザー\(userID)の投稿ドキュメント数: \(snapshot.documents.count)")
        
        let posts = snapshot.documents.compactMap { doc -> EmotionPost? in
            guard
                let idString = doc.get("id") as? String,
                let id = UUID(uuidString: idString),
                let levelValue = doc.get("level") as? Int,
                let visualRaw = doc.get("visualType") as? String,
                let createdAt = (doc.get("createdAt") as? Timestamp)?.dateValue(),
                let authorID = doc.get("authorID") as? String,
                authorID == userID
            else {
                return nil
            }
            
            let level = EmotionLevel.clamped(levelValue)
            guard let visualType = EmotionVisualType(rawValue: visualRaw) else { return nil }
            
            let latitude = doc.get("latitude") as? Double
            let longitude = doc.get("longitude") as? Double
            let likeCount = doc.get("likeCount") as? Int ?? 0
            let likedBy = doc.get("likedBy") as? [String] ?? []
            let isPublicPost = doc.get("isPublicPost") as? Bool ?? true // デフォルトは公開
            
            var supports: [SupportInfo] = []
            if let supportsData = doc.get("supports") as? [[String: Any]] {
                supports = supportsData.compactMap { supportDict in
                    guard
                        let emojiRaw = supportDict["emoji"] as? String,
                        let emoji = SupportEmoji(rawValue: emojiRaw),
                        let userID = supportDict["userID"] as? String,
                        let timestamp = (supportDict["timestamp"] as? Timestamp)?.dateValue()
                    else {
                        return nil
                    }
                    return SupportInfo(emoji: emoji, userID: userID, timestamp: timestamp)
                }
            }
            
            let comment = doc.get("comment") as? String
            
            let isMistCleanup = doc.get("isMistCleanup") as? Bool ?? false
            return EmotionPost(
                id: id,
                level: level,
                visualType: visualType,
                createdAt: createdAt,
                latitude: latitude,
                longitude: longitude,
                likeCount: likeCount,
                likedBy: likedBy,
                supports: supports,
                authorID: authorID,
                isPublicPost: isPublicPost,
                comment: comment,
                isMistCleanup: isMistCleanup
            )
        }
        
        // メモリ上でソート（作成日時の降順）
        return posts.sorted { $0.createdAt > $1.createdAt }
    }
    
    // 友達数を取得
    func fetchFriendCount() async throws -> Int {
        let currentUserID = UserService.shared.currentUserID
        
        let snapshot = try await db.collection("friendships")
            .whereField("userID1", isEqualTo: currentUserID)
            .getDocuments()
        
        return snapshot.documents.count
    }
    
    // 友達一覧を取得
    func fetchFriends() async throws -> [Friend] {
        let currentUserID = UserService.shared.currentUserID
        var friends: [Friend] = []
        var processedUserIDs = Set<String>() // 重複を防ぐ
        
        // 1. 新バージョン: userID1/userID2フィールドを使った検索
        // userID1が自分の場合
        let snapshot1 = try await db.collection("friendships")
            .whereField("userID1", isEqualTo: currentUserID)
            .getDocuments()
        
        print("🔍 友達関係(userID1): \(snapshot1.documents.count)件")
        
        for doc in snapshot1.documents {
            guard
                let userID2 = doc.get("userID2") as? String,
                let createdAt = (doc.get("createdAt") as? Timestamp)?.dateValue(),
                !processedUserIDs.contains(userID2)
            else {
                continue
            }
            
            processedUserIDs.insert(userID2)
            
            // ユーザー名を取得
            var username = "ユーザー"
            do {
                let userDoc = try await db.collection("users").document(userID2).getDocument()
                
                if userDoc.exists {
                    print("📄 ユーザードキュメント存在: \(userID2)")
                    print("📄 ドキュメントデータ: \(userDoc.data() ?? [:])")
                    
                    // 複数のフィールド名をチェック（userNameが正式なフィールド名）
                    if let fetchedUsername = userDoc.data()?["userName"] as? String {
                        username = fetchedUsername
                        print("✅ ユーザー名取得成功(userName): \(userID2) -> \(username)")
                    } else if let fetchedUsername = userDoc.data()?["name"] as? String {
                        username = fetchedUsername
                        print("✅ ユーザー名取得成功(name): \(userID2) -> \(username)")
                    } else if let fetchedUsername = userDoc.data()?["username"] as? String {
                        username = fetchedUsername
                        print("✅ ユーザー名取得成功(username): \(userID2) -> \(username)")
                    } else if let fetchedUsername = userDoc.data()?["userName"] as? String {
                        username = fetchedUsername
                        print("✅ ユーザー名取得成功(userName): \(userID2) -> \(username)")
                    } else {
                        print("⚠️ ユーザー名フィールドが見つからない: \(userID2)")
                    }
                } else {
                    print("⚠️ ユーザードキュメントが存在しない: \(userID2)")
                }
            } catch {
                print("⚠️ ユーザー名の取得に失敗: \(userID2), error: \(error.localizedDescription)")
            }
            
            friends.append(Friend(
                id: doc.documentID,
                userID: userID2,
                username: username,
                createdAt: createdAt
            ))
        }
        
        // userID2が自分の場合
        let snapshot2 = try await db.collection("friendships")
            .whereField("userID2", isEqualTo: currentUserID)
            .getDocuments()
        
        print("🔍 友達関係(userID2): \(snapshot2.documents.count)件")
        
        for doc in snapshot2.documents {
            guard
                let userID1 = doc.get("userID1") as? String,
                let createdAt = (doc.get("createdAt") as? Timestamp)?.dateValue(),
                !processedUserIDs.contains(userID1)
            else {
                continue
            }
            
            processedUserIDs.insert(userID1)
            
            // ユーザー名を取得
            var username = "ユーザー"
            do {
                let userDoc = try await db.collection("users").document(userID1).getDocument()
                
                if userDoc.exists {
                    print("📄 ユーザードキュメント存在: \(userID1)")
                    print("📄 ドキュメントデータ: \(userDoc.data() ?? [:])")
                    
                    // 複数のフィールド名をチェック（userNameが正式なフィールド名）
                    if let fetchedUsername = userDoc.data()?["userName"] as? String {
                        username = fetchedUsername
                        print("✅ ユーザー名取得成功(userName): \(userID1) -> \(username)")
                    } else if let fetchedUsername = userDoc.data()?["name"] as? String {
                        username = fetchedUsername
                        print("✅ ユーザー名取得成功(name): \(userID1) -> \(username)")
                    } else if let fetchedUsername = userDoc.data()?["username"] as? String {
                        username = fetchedUsername
                        print("✅ ユーザー名取得成功(username): \(userID1) -> \(username)")
                    } else if let fetchedUsername = userDoc.data()?["userName"] as? String {
                        username = fetchedUsername
                        print("✅ ユーザー名取得成功(userName): \(userID1) -> \(username)")
                    } else {
                        print("⚠️ ユーザー名フィールドが見つからない: \(userID1)")
                    }
                } else {
                    print("⚠️ ユーザードキュメントが存在しない: \(userID1)")
                }
            } catch {
                print("⚠️ ユーザー名の取得に失敗: \(userID1), error: \(error.localizedDescription)")
            }
            
            friends.append(Friend(
                id: doc.documentID,
                userID: userID1,
                username: username,
                createdAt: createdAt
            ))
        }
        
        print("✅ 友達一覧取得完了: \(friends.count)人")
        
        // メモリ上でソート
        return friends.sorted { $0.createdAt > $1.createdAt }
    }
    
    // MARK: - 通知機能
    
    // 友達申請通知を作成（requestID付き）
    func createFriendRequestNotification(
        requestID: String,
        fromUserID: String,
        toUserID: String,
        fromUserName: String
    ) async throws {
        let notificationID = UUID().uuidString
        
        let data: [String: Any] = [
            "id": notificationID,
            "type": NotificationType.friendRequest.rawValue,
            "title": "友達申請",
            "body": "\(fromUserName)さんが友達になりたがっています",
            "fromUserID": fromUserID,
            "toUserID": toUserID,
            "relatedID": fromUserID,
            "requestID": requestID,  // ★ requestIDを追加
            "createdAt": Timestamp(date: Date()),
            "isRead": false
        ]
        
        try await db.collection("notifications")
            .document(notificationID)
            .setData(data)
        
        print("✅ 友達申請通知を保存しました: requestID=\(requestID), toUserID=\(toUserID)")
    }
    
    // 通知をFirestoreに保存
    func createNotification(
        type: NotificationType,
        title: String,
        body: String,
        relatedID: String? = nil,
        toUserID: String
    ) async throws {
        let notificationID = UUID().uuidString
        let currentUserID = UserService.shared.currentUserID
        
        print("💾 Firestoreに通知を保存開始")
        print("   - 通知ID: \(notificationID)")
        print("   - タイプ: \(type.rawValue)")
        print("   - タイトル: \(title)")
        print("   - 送信先: \(toUserID)")
        print("   - 送信元: \(currentUserID)")
        
        let data: [String: Any] = [
            "id": notificationID,
            "type": type.rawValue,
            "title": title,
            "body": body,
            "fromUserID": currentUserID,
            "toUserID": toUserID,
            "relatedID": relatedID ?? "",
            "createdAt": Timestamp(date: Date()),
            "isRead": false
        ]
        
        print("📤 Firestoreへの書き込みを実行中...")
        try await db.collection("notifications")
            .document(notificationID)
            .setData(data)
        
        print("✅ Firestoreへの通知保存完了: \(type.rawValue) -> \(toUserID)")
        print("   → Cloud Functions (sendNotificationOnCreateV2) がトリガーされます")
    }
    
    // 全ユーザーにアップデート通知を送信（管理者用）
    func sendUpdateNotificationToAllUsers(title: String, message: String) async throws {
        // 全ユーザーのIDを取得
        let snapshot = try await db.collection("users").getDocuments()
        let userIDs = snapshot.documents.map { $0.documentID }
        
        print("📢 \(userIDs.count) 人のユーザーにアップデート通知を送信開始...")
        
        // 各ユーザーに通知を送信
        for userID in userIDs {
            let notificationID = UUID().uuidString
            let data: [String: Any] = [
                "id": notificationID,
                "type": NotificationType.systemUpdate.rawValue,
                "title": title,
                "body": message,
                "fromUserID": "system",
                "toUserID": userID,
                "relatedID": "",
                "createdAt": Timestamp(date: Date()),
                "isRead": false
            ]
            
            try? await db.collection("notifications")
                .document(notificationID)
                .setData(data)
        }
        
        print("✅ \(userIDs.count) 人のユーザーに通知を送信しました")
    }
    
    // ミッション報酬の補償（過去にミッションを達成したが報酬がもらえなかったユーザー向け）
    func compensateMissionRewards() async throws -> (affectedUsers: Int, totalExp: Int, totalPostBonus: Int) {
        print("🎁 ミッション報酬の補償を開始...")
        
        // 全ユーザーを取得
        let usersSnapshot = try await db.collection(usersCollectionName).getDocuments()
        let registrationsSnapshot = try await db.collection(userRegistrationsCollectionName).getDocuments()
        
        var affectedUsers = 0
        var totalExpAwarded = 0
        var totalPostBonusAwarded = 0
        
        for userDoc in usersSnapshot.documents {
            let userID = userDoc.documentID
            
            // ユーザーの現在の経験値からレベルを計算
            let currentExp = userDoc.get("experiencePoints") as? Int ?? 0
            let currentLevel = UserService.calculateLevel(fromExp: currentExp)
            
            // ユーザーの投稿回数を取得
            let registrationDoc = registrationsSnapshot.documents.first(where: { $0.documentID == userID })
            let postCount = registrationDoc?.get("emotionPostCount") as? Int ?? 0
            let mistClearCount = registrationDoc?.get("mistClearCount") as? Int ?? 0
            
            // 既に付与した報酬を確認
            let levelRewardsReceived = registrationDoc?.get("levelRewards") as? [Int] ?? []
            
            var userExpReward = 0
            var userPostBonus = 0
            var titlesAwarded: [String] = []
            var framesAwarded: [String] = []
            
            // レベルミッション報酬の補償
            let levelMilestones = [10, 20, 40, 50, 100]
            for milestone in levelMilestones where currentLevel >= milestone && !levelRewardsReceived.contains(milestone) {
                let exp = milestone * 10
                let post = max(1, milestone / 20)
                userExpReward += exp
                userPostBonus += post
                
                // 称号とアイコンフレームを追加
                let title = "レベル\(milestone)達成"
                let frameID = "level_\(milestone)"
                titlesAwarded.append(title)
                framesAwarded.append(frameID)
                
                print("  - レベル\(milestone): 経験値+\(exp), 投稿+\(post), 称号+フレーム")
            }
            
            // 投稿回数ミッション報酬の補償
            let postMilestones = [10, 20, 40, 50, 100]
            for milestone in postMilestones where postCount >= milestone {
                let exp = milestone * 5
                let post = max(1, milestone / 50)
                userExpReward += exp
                userPostBonus += post
                
                // 称号とアイコンフレームを追加
                let title = "感情投稿\(milestone)回達成"
                let frameID = "post_\(milestone)"
                titlesAwarded.append(title)
                framesAwarded.append(frameID)
                
                print("  - 感情投稿\(milestone)回: 経験値+\(exp), 投稿+\(post), 称号+フレーム")
            }
            
            // モヤ討伐ミッション報酬の補償
            let mistMilestones = [10: (80, 1), 20: (150, 1), 30: (220, 2), 40: (300, 2), 50: (400, 3), 100: (800, 5)]
            for (milestone, rewards) in mistMilestones where mistClearCount >= milestone {
                userExpReward += rewards.0
                userPostBonus += rewards.1
                
                // 称号とアイコンフレームを追加
                let title = "モヤ討伐\(milestone)回達成"
                let frameID = "mist_clear_\(milestone)"
                titlesAwarded.append(title)
                framesAwarded.append(frameID)
                
                print("  - モヤ討伐\(milestone)回: 経験値+\(rewards.0), 投稿+\(rewards.1), 称号+フレーム")
            }
            
            // お詫びの経験値50を追加
            if userExpReward > 0 {
                userExpReward += 50
                affectedUsers += 1
                totalExpAwarded += userExpReward
                totalPostBonusAwarded += userPostBonus
                
                print("🎁 \(userID)に補償: 経験値+\(userExpReward), 投稿+\(userPostBonus), 称号x\(titlesAwarded.count), フレームx\(framesAwarded.count)")
                
                // Firestoreに経験値を追加
                try await db.collection(usersCollectionName).document(userID).setData([
                    "experiencePoints": FieldValue.increment(Int64(userExpReward))
                ], merge: true)
                
                // 称号とアイコンフレームを追加
                if !titlesAwarded.isEmpty || !framesAwarded.isEmpty {
                    var updateData: [String: Any] = [:]
                    if !titlesAwarded.isEmpty {
                        updateData["titles"] = FieldValue.arrayUnion(titlesAwarded)
                    }
                    if !framesAwarded.isEmpty {
                        updateData["iconFrames"] = FieldValue.arrayUnion(framesAwarded)
                    }
                    try await db.collection(userRegistrationsCollectionName).document(userID).setData(updateData, merge: true)
                }
                
                // 投稿回数ボーナスを追加（ローカルではないので、通知で伝える）
                
                // レベル報酬記録を更新（重複防止）
                let allLevelRewards = levelMilestones.filter { currentLevel >= $0 }
                if !allLevelRewards.isEmpty {
                    try await db.collection(userRegistrationsCollectionName).document(userID).setData([
                        "levelRewards": allLevelRewards
                    ], merge: true)
                }
                
                // お詫びの通知を送信
                let notificationID = UUID().uuidString
                var bodyText = "アップデートにより、過去のミッション報酬が未付与でした。お詫びとして以下を付与しました:\n\n"
                bodyText += "・経験値: +\(userExpReward)\n"
                bodyText += "・投稿回数: +\(userPostBonus)回\n"
                if !titlesAwarded.isEmpty {
                    bodyText += "・称号: \(titlesAwarded.joined(separator: "、"))\n"
                }
                if !framesAwarded.isEmpty {
                    bodyText += "・アイコンフレーム: \(framesAwarded.count)個\n"
                }
                bodyText += "\nご迷惑をおかけして申し訳ございませんでした。"
                
                let notificationData: [String: Any] = [
                    "id": notificationID,
                    "type": NotificationType.systemUpdate.rawValue,
                    "title": "お詫びと報酬のお知らせ",
                    "body": bodyText,
                    "fromUserID": "system",
                    "toUserID": userID,
                    "relatedID": "compensation",
                    "createdAt": Timestamp(date: Date()),
                    "isRead": false
                ]
                
                try? await db.collection("notifications")
                    .document(notificationID)
                    .setData(notificationData)
            }
        }
        
        print("✅ 報酬補償完了: \(affectedUsers)人, 総経験値+\(totalExpAwarded), 総投稿+\(totalPostBonusAwarded)")
        return (affectedUsers, totalExpAwarded, totalPostBonusAwarded)
    }
    
    // 投稿の閲覧を記録し、友達が閲覧した場合に通知を送る
    func recordPostView(postID: UUID, authorID: String) async {
        let currentUserID = UserService.shared.currentUserID
        
        // 自分の投稿の場合は何もしない
        guard authorID != currentUserID else {
            return
        }
        
        // 友達関係を確認
        do {
            let isFriend = try await checkFriendship(with: authorID)
            
            // 友達の場合のみ通知を送る
            if isFriend {
                // 同じ投稿を一定時間内に複数回見ても、1回だけ通知を送る（スパム防止）
                // 最後に閲覧通知を送った時刻を確認
                let lastViewKey = "lastViewNotification_\(postID.uuidString)_\(authorID)"
                let lastViewTime = UserDefaults.standard.object(forKey: lastViewKey) as? Date
                let now = Date()
                
                // 1時間以内に既に通知を送っている場合はスキップ
                if let lastTime = lastViewTime,
                   now.timeIntervalSince(lastTime) < 3600 {
                    return
                }
                
                // 友達が何人閲覧したかを集計
                // まず、この投稿に対する閲覧通知の数を取得
                let viewNotificationsSnapshot = try await db.collection("notifications")
                    .whereField("type", isEqualTo: "view")
                    .whereField("relatedID", isEqualTo: postID.uuidString)
                    .whereField("toUserID", isEqualTo: authorID)
                    .getDocuments()
                
                // 過去1時間以内の閲覧通知数をカウント
                let oneHourAgo = Date().addingTimeInterval(-3600)
                let recentViews = viewNotificationsSnapshot.documents.filter { doc in
                    if let createdAt = (doc.get("createdAt") as? Timestamp)?.dateValue() {
                        return createdAt >= oneHourAgo
                    }
                    return false
                }
                
                let viewCount = recentViews.count + 1 // 今回の閲覧を含める
                
                // 通知を送る
                try await createNotification(
                    type: .view,
                    title: "投稿を見られました",
                    body: viewCount == 1 ? "友達1人があなたの投稿を見ました" : "友達\(viewCount)人があなたの投稿を見ました",
                    relatedID: postID.uuidString,
                    toUserID: authorID
                )
                
                // 最後に閲覧通知を送った時刻を記録
                UserDefaults.standard.set(now, forKey: lastViewKey)
                
                print("✅ 投稿閲覧通知を送信しました: postID=\(postID.uuidString), authorID=\(authorID), viewCount=\(viewCount)")
            }
        } catch {
            print("❌ 投稿閲覧の記録に失敗: \(error.localizedDescription)")
        }
    }
    
    // 友達関係を確認する（簡易版）
    private func checkFriendship(with userID: String) async throws -> Bool {
        let currentUserID = UserService.shared.currentUserID
        
        // 双方向の友達関係を確認
        let snapshot1 = try await db.collection("friendships")
            .whereField("userID1", isEqualTo: currentUserID)
            .whereField("userID2", isEqualTo: userID)
            .limit(to: 1)
            .getDocuments()
        
        if !snapshot1.documents.isEmpty {
            return true
        }
        
        let snapshot2 = try await db.collection("friendships")
            .whereField("userID1", isEqualTo: userID)
            .whereField("userID2", isEqualTo: currentUserID)
            .limit(to: 1)
            .getDocuments()
        
        return !snapshot2.documents.isEmpty
    }
    
    // 全ての通知を取得（Firestoreから）
    func fetchAllNotifications() async throws -> [AppNotification] {
        let currentUserID = UserService.shared.currentUserID
        
        print("🔔 通知を取得中: toUserID=\(currentUserID)")
        
        // 自分宛ての通知を取得
        // インデックスエラーを避けるため、まずはフィルタのみで取得してからメモリでソート
        let snapshot = try await db.collection("notifications")
            .whereField("toUserID", isEqualTo: currentUserID)
            .getDocuments()
        
        print("🔔 通知の取得結果: \(snapshot.documents.count)件")
        
        let notifications = snapshot.documents.compactMap { doc -> AppNotification? in
            guard
                let id = doc.get("id") as? String,
                let typeRaw = doc.get("type") as? String,
                let type = NotificationType(rawValue: typeRaw),
                let title = doc.get("title") as? String,
                let body = doc.get("body") as? String,
                let createdAt = (doc.get("createdAt") as? Timestamp)?.dateValue(),
                let isRead = doc.get("isRead") as? Bool
            else {
                return nil
            }
            
            let relatedID = doc.get("relatedID") as? String
            
            return AppNotification(
                id: id,
                type: type,
                title: title,
                body: body,
                createdAt: createdAt,
                isRead: isRead,
                relatedID: relatedID
            )
        }
        
        // メモリ上でソート（作成日時の降順、最大100件）
        return Array(notifications.sorted { $0.createdAt > $1.createdAt }.prefix(100))
    }
    
    // 承認された友達申請を取得（自分が送った申請）
    private func fetchAcceptedFriendRequests() async throws -> [FriendRequest] {
        let currentUserID = UserService.shared.currentUserID
        
        let snapshot = try await db.collection("friendRequests")
            .whereField("fromUserID", isEqualTo: currentUserID)
            .whereField("status", isEqualTo: "accepted")
            .order(by: "acceptedAt", descending: true)
            .limit(to: 50)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc -> FriendRequest? in
            guard
                let id = doc.get("id") as? String,
                let fromUserID = doc.get("fromUserID") as? String,
                let toUserID = doc.get("toUserID") as? String,
                let status = doc.get("status") as? String,
                let createdAt = (doc.get("createdAt") as? Timestamp)?.dateValue()
            else {
                return nil
            }
            
            let acceptedAt = (doc.get("acceptedAt") as? Timestamp)?.dateValue()
            
            return FriendRequest(
                id: id,
                fromUserID: fromUserID,
                toUserID: toUserID,
                status: status,
                createdAt: createdAt,
                acceptedAt: acceptedAt
            )
        }
    }
    
    // 通知を既読にする
    func markNotificationAsRead(notificationID: String) async throws {
        try await db.collection("notifications")
            .document(notificationID)
            .updateData(["isRead": true])
    }
    
    // 通知を削除
    func deleteNotification(notificationID: String) async throws {
        try await db.collection("notifications")
            .document(notificationID)
            .delete()
        print("✅ 通知を削除しました: \(notificationID)")
    }
    
    // 古い友達申請通知を一括削除（管理者用）
    func cleanupOldFriendRequestNotifications() async throws {
        let currentUserID = UserService.shared.currentUserID
        
        print("🧹 古い友達申請通知をクリーンアップ中...")
        
        // 自分が受け取った友達申請通知を取得
        let snapshot = try await db.collection("notifications")
            .whereField("type", isEqualTo: "friendRequest")
            .whereField("toUserID", isEqualTo: currentUserID)
            .getDocuments()
        
        var deletedCount = 0
        
        for doc in snapshot.documents {
            guard let relatedID = doc.get("relatedID") as? String ?? doc.get("fromUserID") as? String else {
                continue
            }
            
            // 該当する友達申請が存在するか確認
            let requestSnapshot = try await db.collection("friendRequests")
                .whereField("fromUserID", isEqualTo: relatedID)
                .whereField("toUserID", isEqualTo: currentUserID)
                .whereField("status", isEqualTo: "pending")
                .getDocuments()
            
            // 申請が存在しない（取り消し済み/承認済み/拒否済み）場合は通知を削除
            if requestSnapshot.documents.isEmpty {
                try await doc.reference.delete()
                deletedCount += 1
                print("✅ 古い通知を削除: \(doc.documentID)")
            }
        }
        
        print("✅ クリーンアップ完了: \(deletedCount)件の通知を削除しました")
    }
    
    // 無効な投稿に関する通知を削除
    func cleanupInvalidPostNotifications() async throws {
        let currentUserID = UserService.shared.currentUserID
        
        print("🧹 無効な投稿通知をクリーンアップ中...")
        
        // 自分が受け取った投稿関連通知を取得
        let types = ["comment", "support", "like"]
        var allNotifications: [QueryDocumentSnapshot] = []
        
        for type in types {
            let snapshot = try await db.collection("notifications")
                .whereField("type", isEqualTo: type)
                .whereField("toUserID", isEqualTo: currentUserID)
                .getDocuments()
            allNotifications.append(contentsOf: snapshot.documents)
        }
        
        var deletedCount = 0
        
        for doc in allNotifications {
            guard let relatedID = doc.get("relatedID") as? String else {
                continue
            }
            
            // relatedIDがUUID形式でない場合はスキップ
            guard UUID(uuidString: relatedID) != nil else {
                print("⚠️ 無効なUUID形式: \(relatedID)")
                continue
            }
            
            // 投稿が存在するか確認
            let postDoc = try await db.collection(collectionName)
                .document(relatedID.lowercased())
                .getDocument()
            
            // 投稿が存在しない場合は通知を削除
            if !postDoc.exists {
                try await doc.reference.delete()
                deletedCount += 1
                print("✅ 無効な通知を削除: \(doc.documentID) (投稿ID: \(relatedID))")
            }
        }
        
        print("✅ クリーンアップ完了: \(deletedCount)件の通知を削除しました")
    }
    
    // MARK: - ユーザー設定
    
    // ユーザー設定を保存
    func saveUserSettings(isPublicAccount: Bool) async throws {
        let currentUserID = UserService.shared.currentUserID
        
        let data: [String: Any] = [
            "userID": currentUserID,
            "userName": UserService.shared.userName,
            "isPublicAccount": isPublicAccount,
            "updatedAt": Timestamp(date: Date())
        ]
        
        try await db.collection(usersCollectionName)
            .document(currentUserID)
            .setData(data, merge: true)
        
        print("✅ ユーザー設定を保存しました: isPublicAccount=\(isPublicAccount)")
    }
    
    // ユーザー名の重複チェック
    func checkUserNameExists(userName: String, excludeUserID: String? = nil) async throws -> Bool {
        let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 空の場合はチェックしない
        if trimmedName.isEmpty {
            return false
        }
        
        print("🔍 ユーザー名の重複チェック: \(trimmedName)")
        
        let snapshot = try await db.collection(usersCollectionName)
            .whereField("userName", isEqualTo: trimmedName)
            .getDocuments()
        
        // 自分自身を除外してチェック
        if let excludeUserID = excludeUserID {
            let otherUsers = snapshot.documents.filter { $0.documentID != excludeUserID }
            let exists = !otherUsers.isEmpty
            print(exists ? "⚠️ ユーザー名が既に使用されています" : "✅ ユーザー名は使用可能です")
            return exists
        } else {
            let exists = !snapshot.documents.isEmpty
            print(exists ? "⚠️ ユーザー名が既に使用されています" : "✅ ユーザー名は使用可能です")
            return exists
        }
    }
    
    // ユーザー検索
    func searchUsers(query: String) async throws -> [(userID: String, userName: String, level: Int, profileImageURL: String?)] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // 空の場合は空の結果を返す
        if trimmedQuery.isEmpty {
            return []
        }
        
        print("🔍 ユーザー検索: \(trimmedQuery)")
        
        // すべてのユーザーを取得（Firestoreでは部分一致検索が難しいため）
        let snapshot = try await db.collection(usersCollectionName)
            .getDocuments()
        
        // ブロックリストを取得
        let currentUserID = UserService.shared.currentUserID
        let blockList = try? await getBlockedUserIDs()
        let blockedUserIDs = Set(blockList ?? [])
        
        var results: [(userID: String, userName: String, level: Int, profileImageURL: String?)] = []
        
        for doc in snapshot.documents {
            let userID = doc.documentID
            
            // 自分自身とブロックしているユーザーを除外
            if userID == currentUserID || blockedUserIDs.contains(userID) {
                continue
            }
            
            guard let userName = doc.get("userName") as? String else {
                continue
            }
            
            // 部分一致検索（大文字小文字を区別しない）
            if userName.lowercased().contains(trimmedQuery) {
                let experiencePoints = doc.get("experiencePoints") as? Int ?? 0
                let level = UserService.calculateLevel(fromExp: experiencePoints)
                let profileImageURL = doc.get("profileImageURL") as? String
                
                results.append((userID: userID, userName: userName, level: level, profileImageURL: profileImageURL))
            }
        }
        
        // ユーザー名でソート
        results.sort { $0.userName < $1.userName }
        
        print("✅ 検索結果: \(results.count)件")
        return results
    }
    
    // ユーザー情報全体をFirestoreに保存（年齢、性別、居住地なども含む）
    func saveUserProfile() async throws {
        let currentUserID = UserService.shared.currentUserID
        
        var data: [String: Any] = [
            "userID": currentUserID,
            "userName": UserService.shared.userName,
            "isPublicAccount": UserService.shared.isPublicAccount,
            "updatedAt": Timestamp(date: Date())
        ]
        
        // 居住地
        if !UserService.shared.homePrefectureName.isEmpty {
            data["homePrefecture"] = UserService.shared.homePrefectureName
        }
        
        // 年齢
        if let age = UserService.shared.userAge {
            data["age"] = age
        }
        
        // 性別
        data["gender"] = UserService.shared.userGender
        
        try await db.collection(usersCollectionName)
            .document(currentUserID)
            .setData(data, merge: true)
        
        print("✅ ユーザープロフィールをFirestoreに保存しました")
    }
    
    // プロフィール画像をFirebase Storageにアップロード
    func uploadProfileImage(_ image: UIImage, userID: String) async throws -> String {
        print("\n📤 プロフィール画像のアップロード開始")
        print("   - ユーザーID: \(userID)")
        print("   - 画像サイズ: \(image.size.width) x \(image.size.height)")
        
        let storage = Storage.storage()
        let storageRef = storage.reference()
        let profileImageRef = storageRef.child("profile_images/\(userID).jpg")
        
        // 画像をJPEG形式に変換（圧縮率0.8）
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("❌ 画像の変換に失敗")
            throw NSError(domain: "FirestoreService", code: 400, userInfo: [NSLocalizedDescriptionKey: "画像の変換に失敗しました"])
        }
        print("✅ 画像をJPEG形式に変換: \(imageData.count) bytes")
        
        // メタデータを設定
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        // アップロード
        print("📤 Firebase Storageにアップロード中...")
        let _ = try await profileImageRef.putDataAsync(imageData, metadata: metadata)
        print("✅ Firebase Storageへのアップロード完了")
        
        // ダウンロードURLを取得
        let downloadURL = try await profileImageRef.downloadURL()
        print("✅ ダウンロードURL取得: \(downloadURL.absoluteString)")
        
        // FirestoreにダウンロードURLを保存
        print("💾 FirestoreにURL保存中...")
        print("   - コレクション: \(usersCollectionName)")
        print("   - ドキュメントID: \(userID)")
        print("   - フィールド: profileImageURL")
        print("   - 値: \(downloadURL.absoluteString)")
        
        try await db.collection(usersCollectionName)
            .document(userID)
            .setData(["profileImageURL": downloadURL.absoluteString], merge: true)
        
        print("✅ FirestoreへのURL保存完了")
        
        // 保存されたか確認（デバッグ用）
        let docRef = db.collection(usersCollectionName).document(userID)
        let verifyDoc = try await docRef.getDocument(source: .server)
        if let savedURL = verifyDoc.get("profileImageURL") as? String {
            print("✅ 保存確認成功: \(savedURL)")
        } else {
            print("⚠️ 保存確認: profileImageURLフィールドが見つかりません")
        }
        
        print("✅ プロフィール画像のアップロード完了\n")
        return downloadURL.absoluteString
    }
    
    // プロフィール画像をFirebase Storageからダウンロード
    func downloadProfileImage(userID: String, forceServerFetch: Bool = true) async throws -> UIImage? {
        print("📸 プロフィール画像ダウンロード開始")
        print("   - ユーザーID: \(userID)")
        print("   - キャッシュバイパス: \(forceServerFetch)")
        
        // まずFirestoreからダウンロードURLを取得
        let docRef = db.collection(usersCollectionName).document(userID)
        
        do {
            // forceServerFetchがtrueの場合、キャッシュをバイパスしてサーバーから直接取得
            let document = forceServerFetch 
                ? try await docRef.getDocument(source: .server)
                : try await docRef.getDocument()
            
            guard document.exists else {
                print("ℹ️ ユーザードキュメントが存在しません: \(userID)")
                return nil
            }
            
            print("✅ Firestoreからユーザードキュメント取得成功")
            
            // ドキュメントの全データをログ出力（デバッグ用）
            if let data = document.data() {
                print("📄 ユーザードキュメントの内容:")
                print("   - フィールド数: \(data.keys.count)")
                print("   - フィールド一覧: \(data.keys.joined(separator: ", "))")
                if let urlValue = data["profileImageURL"] {
                    print("   - profileImageURL フィールドの型: \(type(of: urlValue))")
                    print("   - profileImageURL の値: \(urlValue)")
                } else {
                    print("   - ⚠️ profileImageURL フィールドが存在しません")
                }
            }
            
            // profileImageURLが存在しない場合、Firebase Storageから直接取得を試みる
            var urlString: String? = document.get("profileImageURL") as? String
            
            if urlString == nil || urlString?.isEmpty == true {
                print("⚠️ profileImageURLフィールドが存在しないため、Storageから直接取得を試みます")
                
                // Firebase Storageから直接URLを取得
                let storage = Storage.storage()
                let storageRef = storage.reference()
                let profileImageRef = storageRef.child("profile_images/\(userID).jpg")
                
                do {
                    let storageURL = try await profileImageRef.downloadURL()
                    urlString = storageURL.absoluteString
                    print("✅ Storageから画像URL取得成功: \(storageURL.absoluteString)")
                    
                    // Firestoreに保存（次回からはこちらを使用）
                    print("💾 FirestoreにURLを保存して修復します...")
                    try await db.collection(usersCollectionName)
                        .document(userID)
                        .setData(["profileImageURL": storageURL.absoluteString], merge: true)
                    print("✅ Firestoreへの保存完了（修復成功）")
                } catch {
                    print("ℹ️ Storageにも画像が存在しません: \(error.localizedDescription)")
                    return nil
                }
            }
            
            guard let finalURLString = urlString, !finalURLString.isEmpty else {
                print("ℹ️ プロフィール画像URLが設定されていません: \(userID)")
                return nil
            }
            
            print("✅ プロフィール画像URL取得: \(finalURLString.prefix(50))...")
            
            guard let url = URL(string: finalURLString) else {
                print("❌ URLの変換に失敗: \(finalURLString)")
                return nil
            }
            
            // URLから画像をダウンロード（キャッシュをバイパス）
            var request = URLRequest(url: url)
            request.cachePolicy = forceServerFetch ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad
            
            print("📥 画像データのダウンロード開始...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ HTTPレスポンス: \(httpResponse.statusCode)")
            }
            print("✅ ダウンロードサイズ: \(data.count) bytes")
            
            guard let image = UIImage(data: data) else {
                print("❌ 画像データの変換に失敗: \(userID)")
                return nil
            }
            
            print("✅ プロフィール画像のダウンロード完全成功!")
            print("   - 画像サイズ: \(image.size.width) x \(image.size.height)")
            return image
        } catch {
            // ネットワークエラーなど、実際のエラーの場合のみログ出力
            print("❌ プロフィール画像のダウンロードエラー")
            print("   - エラー: \(error.localizedDescription)")
            return nil
        }
    }
    
    // Firestoreからユーザー情報を読み込んで復元
    // 管理者用：ユーザープロフィールを辞書で取得
    func fetchUserProfile(userID: String) async throws -> [String: Any] {
        let docRef = db.collection(usersCollectionName).document(userID)
        let document = try await docRef.getDocument()
        
        guard document.exists, let data = document.data() else {
            return [:]
        }
        
        return data
    }
    
    // 現在のユーザーのプロフィールを読み込む
    func loadCurrentUserProfile() async throws {
        let targetUserID = UserService.shared.currentUserID
        let docRef = db.collection(usersCollectionName).document(targetUserID)
        let document = try await docRef.getDocument()
        
        guard document.exists else {
            print("⚠️ ユーザー情報が見つかりません")
            return
        }
        
        // ユーザー名
        if let userName = document.get("userName") as? String {
            UserService.shared.userName = userName
        }
        
        // 公開/非公開
        if let isPublicAccount = document.get("isPublicAccount") as? Bool {
            UserService.shared.isPublicAccount = isPublicAccount
        }
        
        // 居住地
        if let homePrefecture = document.get("homePrefecture") as? String {
            UserService.shared.homePrefectureName = homePrefecture
        }
        
        // 年齢
        if let age = document.get("age") as? Int {
            UserService.shared.userAge = age
        }
        
        // 性別
        if let gender = document.get("gender") as? String {
            UserService.shared.userGender = gender
        }

        // 管理者付与の投稿可能回数（累計）を、未適用分だけローカルに反映
        // 旧データ互換のため pending も足し込んで扱う
        let totalGranted = document.get("adminPostLimitBonusTotal") as? Int ?? 0
        let legacyPending = document.get("adminPostLimitBonusPending") as? Int ?? 0
        let effectiveTotalGranted = totalGranted + legacyPending
        let appliedDelta = UserService.shared.applyAdminPostLimitBonus(totalGranted: effectiveTotalGranted)
        if appliedDelta > 0 {
            print("✅ 管理者付与の投稿可能回数ボーナスを適用: +\(appliedDelta)回")
        }
        
        print("✅ ユーザープロフィールをFirestoreから読み込みました")
    }

    // 管理者用：ユーザー一覧を取得
    func fetchAllUsers() async throws -> [AdminUser] {
        let snapshot = try await db.collection(usersCollectionName).getDocuments()
        let bannedDeviceCounts = try await fetchActiveBannedDeviceCountsByUser()
        return snapshot.documents.map { doc in
            let isPublicAccount = doc.get("isPublicAccount") as? Bool ?? true
            let isFrozen = doc.get("isFrozen") as? Bool ?? false
            let isBanned = doc.get("isBanned") as? Bool ?? false
            let totalGranted = doc.get("adminPostLimitBonusTotal") as? Int ?? 0
            let legacyPending = doc.get("adminPostLimitBonusPending") as? Int ?? 0
            let updatedAt = (doc.get("updatedAt") as? Timestamp)?.dateValue()
            let userName = doc.get("userName") as? String
            let fcmToken = doc.get("fcmToken") as? String
            return AdminUser(
                id: doc.documentID,
                isPublicAccount: isPublicAccount,
                isFrozen: isFrozen,
                isBanned: isBanned,
                bannedDeviceCount: bannedDeviceCounts[doc.documentID] ?? 0,
                grantedPostLimitBonusTotal: totalGranted + legacyPending,
                updatedAt: updatedAt,
                userName: userName,
                fcmToken: fcmToken
            )
        }
    }

    // 管理者用：BAN中端末のユーザー別カウントを取得
    private func fetchActiveBannedDeviceCountsByUser() async throws -> [String: Int] {
        let snapshot = try await db.collection(blockedDevicesCollectionName)
            .whereField("isActive", isEqualTo: true)
            .getDocuments()

        var counts: [String: Int] = [:]
        for doc in snapshot.documents {
            guard let userID = doc.get("userID") as? String, !userID.isEmpty else { continue }
            counts[userID, default: 0] += 1
        }
        return counts
    }
    
    // 管理者用：都道府県別ユーザー数を取得
    func fetchPrefectureUserStats() async throws -> [String: Int] {
        let snapshot = try await db.collection(usersCollectionName).getDocuments()
        var stats: [String: Int] = [:]
        
        for doc in snapshot.documents {
            let homePrefecture = doc.get("homePrefecture") as? String ?? ""
            let prefectureName = homePrefecture.isEmpty ? "未設定" : homePrefecture
            stats[prefectureName, default: 0] += 1
        }
        
        print("✅ 都道府県別ユーザー数: \(stats)")
        return stats
    }

    // 管理者用：ユーザー公開設定を更新
    func updateUserPublicAccount(userID: String, isPublicAccount: Bool) async throws {
        try await db.collection(usersCollectionName)
            .document(userID)
            .setData([
                "isPublicAccount": isPublicAccount,
                "updatedAt": Timestamp(date: Date())
            ], merge: true)
    }

    // 管理者用：ユーザー凍結を更新
    func updateUserFrozen(userID: String, isFrozen: Bool) async throws {
        try await db.collection(usersCollectionName)
            .document(userID)
            .setData([
                "isFrozen": isFrozen,
                "updatedAt": Timestamp(date: Date())
            ], merge: true)
    }

    // 管理者用：ユーザーBANを更新
    func updateUserBanned(userID: String, isBanned: Bool) async throws {
        let reason = "管理者画面でBANされました"
        try await db.collection(usersCollectionName)
            .document(userID)
            .setData([
                "isBanned": isBanned,
                "banReason": isBanned ? reason : NSNull(),
                "bannedAt": isBanned ? Timestamp(date: Date()) : NSNull(),
                "unbannedAt": isBanned ? NSNull() : Timestamp(date: Date()),
                "updatedAt": Timestamp(date: Date())
            ], merge: true)

        if isBanned {
            try await banKnownDevices(for: userID, reason: reason)
        } else {
            try await unbanKnownDevices(for: userID)
        }
    }

    // 管理者用：ユーザーを削除
    func deleteUser(userID: String) async throws {
        try await db.collection(usersCollectionName).document(userID).delete()
    }
    
    // ユーザー自身がアカウントを削除（包括的）
    func deleteUserAccount(userID: String, username: String) async throws {
        // 1. ユーザーの投稿をすべて削除
        let postsSnapshot = try await db.collection(collectionName)
            .whereField("authorID", isEqualTo: userID)
            .getDocuments()
        for doc in postsSnapshot.documents {
            try await doc.reference.delete()
        }
        
        // 2. 友達関係をすべて削除
        let friendshipsSnapshot1 = try await db.collection("friendships")
            .whereField("userID1", isEqualTo: userID)
            .getDocuments()
        for doc in friendshipsSnapshot1.documents {
            try await doc.reference.delete()
        }
        
        let friendshipsSnapshot2 = try await db.collection("friendships")
            .whereField("userID2", isEqualTo: userID)
            .getDocuments()
        for doc in friendshipsSnapshot2.documents {
            try await doc.reference.delete()
        }
        
        // 3. 友達申請をすべて削除
        let requestsSnapshot1 = try await db.collection("friendRequests")
            .whereField("fromUserID", isEqualTo: userID)
            .getDocuments()
        for doc in requestsSnapshot1.documents {
            try await doc.reference.delete()
        }
        
        let requestsSnapshot2 = try await db.collection("friendRequests")
            .whereField("toUserID", isEqualTo: userID)
            .getDocuments()
        for doc in requestsSnapshot2.documents {
            try await doc.reference.delete()
        }
        
        // 4. 認証情報を削除
        try await db.collection(authCollectionName).document(username).delete()
        
        // 5. ユーザープロファイルを削除
        try await db.collection(usersCollectionName).document(userID).delete()
        
        // 6. 通知データを削除（該当する場合）
        let notificationsSnapshot = try await db.collection("notifications")
            .whereField("userID", isEqualTo: userID)
            .getDocuments()
        for doc in notificationsSnapshot.documents {
            try await doc.reference.delete()
        }
        
        print("✅ アカウントと関連データをすべて削除しました")
    }

    // 経験値を取得（Firestore）
    func fetchUserExperiencePoints(userID: String? = nil) async throws -> Int? {
        let targetUserID = userID ?? UserService.shared.currentUserID
        let docRef = db.collection(usersCollectionName).document(targetUserID)
        let document = try await docRef.getDocument()
        guard document.exists else { return nil }
        return document.get("experiencePoints") as? Int
    }

    // 経験値を加算（Firestore）
    func incrementUserExperiencePoints(points: Int, userID: String? = nil) async {
        guard points > 0 else { return }
        let targetUserID = userID ?? UserService.shared.currentUserID
        do {
            try await db.collection(usersCollectionName)
                .document(targetUserID)
                .setData([
                    "experiencePoints": FieldValue.increment(Int64(points)),
                    "experienceUpdatedAt": Timestamp(date: Date())
                ], merge: true)
        } catch {
            print("❌ 経験値の加算に失敗: \(error.localizedDescription)")
        }
    }
    
    // ユーザー設定を取得
    func getUserSettings(userID: String) async throws -> Bool? {
        let docRef = db.collection(usersCollectionName).document(userID)
        let document = try await docRef.getDocument()
        
        guard document.exists else {
            return nil
        }
        
        return document.get("isPublicAccount") as? Bool
    }

    // ユーザー名を取得
    func fetchUserName(userID: String) async throws -> String? {
        let docRef = db.collection(usersCollectionName).document(userID)
        let document = try await docRef.getDocument()
        guard document.exists else { return nil }
        
        // 複数のフィールド名をチェック（nameが正式なフィールド名）
        if let name = document.get("name") as? String {
            return name
        } else if let userName = document.get("userName") as? String {
            return userName
        } else if let username = document.get("username") as? String {
            return username
        }
        
        return nil
    }

    // FCMトークンを保存（改善版: リトライとログ追加）
    func updateUserFCMToken(token: String) async {
        let currentUserID = UserService.shared.currentUserID
        
        // 空のユーザーIDの場合は保存しない
        guard !currentUserID.isEmpty else {
            print("⚠️ ユーザーIDが空のため、FCMトークンを保存できません")
            return
        }
        
        // 最大3回までリトライ
        for attempt in 1...3 {
            do {
                try await db.collection(usersCollectionName)
                    .document(currentUserID)
                    .setData([
                        "fcmToken": token,
                        "fcmTokens": FieldValue.arrayUnion([token]),
                        "fcmTokenUpdatedAt": Timestamp(date: Date())
                    ], merge: true)
                
                print("✅ FCMトークンの保存に成功しました (ユーザーID: \(currentUserID))")
                return
            } catch {
                print("❌ FCMトークンの保存に失敗 (試行\(attempt)/3): \(error.localizedDescription)")
                
                // 最後の試行でない場合は待機してリトライ
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000) // 1秒、2秒と段階的に待機
                    print("🔄 FCMトークンの保存を再試行します...")
                }
            }
        }
        
        print("❌ FCMトークンの保存が3回とも失敗しました")
    }
    
    // 複数のユーザーの公開設定を一括取得
    func getUsersPublicSettings(userIDs: [String]) async throws -> [String: Bool] {
        var settings: [String: Bool] = [:]
        
        // バッチで取得（Firestoreの制限は10件までなので、分割して取得）
        let batchSize = 10
        for i in stride(from: 0, to: userIDs.count, by: batchSize) {
            let endIndex = min(i + batchSize, userIDs.count)
            let batch = Array(userIDs[i..<endIndex])
            
            for userID in batch {
                if let isPublic = try? await getUserSettings(userID: userID) {
                    settings[userID] = isPublic
                } else {
                    // 設定がない場合はデフォルトで公開とみなす
                    settings[userID] = true
                }
            }
        }
        
        return settings
    }
    
    // MARK: - 認証情報管理
    
    private let authCollectionName = "auth"
    
    // ユーザー名の重複チェック
    func checkUsernameExists(username: String) async throws -> Bool {
        let docRef = db.collection(authCollectionName).document(username)
        let document = try await docRef.getDocument()
        return document.exists
    }
    
    // 認証情報を保存
    func saveAuthInfo(username: String, userID: String, passwordHash: String) async throws {
        try await db.collection(authCollectionName)
            .document(username)
            .setData([
                "userID": userID,
                "passwordHash": passwordHash,
                "createdAt": Timestamp(date: Date()),
                "updatedAt": Timestamp(date: Date())
            ])
    }
    
    // 認証情報を取得
    func getAuthInfo(username: String) async throws -> (userID: String, passwordHash: String)? {
        let docRef = db.collection(authCollectionName).document(username)
        let document = try await docRef.getDocument()
        
        guard document.exists,
              let userID = document.get("userID") as? String,
              let passwordHash = document.get("passwordHash") as? String else {
            return nil
        }
        
        return (userID: userID, passwordHash: passwordHash)
    }

    // ユーザーがBANされているかチェック
    func isUserBanned(userID: String) async throws -> Bool {
        let docRef = db.collection(usersCollectionName).document(userID)
        let document = try await docRef.getDocument()
        guard document.exists else { return false }
        return document.get("isBanned") as? Bool ?? false
    }
    
    // MARK: - 都道府県ゲージ管理
    
    private let prefectureGaugesCollectionName = "prefectureGauges"
    private let userRegistrationsCollectionName = "userPrefectureRegistrations"
    
    // 座標から都道府県を判定（逆ジオコーディングを使用）
    private func findPrefectureByCoordinate(latitude: Double, longitude: Double) async -> Prefecture? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: latitude, longitude: longitude)
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first,
                  let prefectureName = placemark.administrativeArea else {
                print("❌ 逆ジオコーディング: 都道府県名を取得できませんでした")
                return nil
            }
            
            // Prefecture enumにマッピング
            let prefecture = Prefecture(rawValue: prefectureName)
            if prefecture == nil {
                print("❌ 都道府県名のマッピング失敗: \(prefectureName)")
            } else {
                print("✅ 逆ジオコーディング成功: \(prefectureName)")
            }
            return prefecture
        } catch {
            print("❌ 逆ジオコーディングエラー: \(error.localizedDescription)")
            return nil
        }
    }
    
    // 投稿時に都道府県ゲージを更新
    // ゲージをリセットする（リザルト画面を閉じた後に呼ばれる）
    func resetPrefectureGauge(prefecture: Prefecture, currentValue: Int, maxValue: Int, completedDate: Date?) async throws {
        let prefectureName = prefecture.rawValue
        let gaugeRef = db.collection(prefectureGaugesCollectionName).document(prefectureName)
        
        try await gaugeRef.setData([
            "id": prefectureName,
            "currentValue": currentValue,
            "maxValue": maxValue,
            "lastUpdated": Timestamp(date: Date()),
            "completedDate": completedDate != nil ? Timestamp(date: completedDate!) : NSNull()
        ], merge: true)
        
        print("✅ Firestoreにゲージリセットを保存: \(prefectureName) - \(currentValue)/\(maxValue)")
    }
    
    func updatePrefectureGauge(latitude: Double, longitude: Double, emotionLevel: EmotionLevel, authorID: String? = nil) async throws {
        print("🔍 ゲージ更新開始: 座標(\(latitude), \(longitude))")
        
        guard let prefecture = await findPrefectureByCoordinate(latitude: latitude, longitude: longitude) else {
            print("❌ 都道府県を特定できませんでした: 座標(\(latitude), \(longitude))")
            return
        }
        
        let prefectureName = prefecture.rawValue
        let contributorID = authorID ?? UserService.shared.currentUserID
        
        print("✅ 都道府県特定: \(prefectureName)")
        
        // 共有ゲージを更新
        let gaugeRef = db.collection(prefectureGaugesCollectionName).document(prefectureName)
        let gaugeDoc = try await gaugeRef.getDocument()
        let currentValue = gaugeDoc.get("currentValue") as? Int ?? 0
        let existingContributors = gaugeDoc.get("contributorIDs") as? [String] ?? []
        let updatedContributors = Array(Set(existingContributors + [contributorID]))
        
        print("📊 現在のゲージ値: \(currentValue)")
        
        // 感情レベルの絶対値 + レベル補正でゲージを増やす
        let levelBonus = max(0, UserService.shared.level - 1)
        let gaugeIncrease = abs(emotionLevel.rawValue) + 1 + levelBonus
        
        print("➕ ゲージ増加量: \(gaugeIncrease) (感情レベル: \(emotionLevel.rawValue), レベルボーナス: \(levelBonus))")
        
        // 共有ゲージを更新（上限なし、無限に増える）
        let newValue = currentValue + gaugeIncrease
        
        print("📈 新しいゲージ値: \(newValue)")
        
        try await gaugeRef.setData([
            "id": prefectureName,
            "currentValue": newValue,
            "lastUpdated": Timestamp(date: Date()),
            "contributorIDs": updatedContributors
        ], merge: true)
        
        print("✅ Firestoreに共有ゲージを保存成功: \(prefectureName) - \(newValue)")
        
        // この都道府県に登録している全ユーザーのゲージ完了状態をチェック
        let registrationsRef = db.collection(userRegistrationsCollectionName)
        let snapshot = try await registrationsRef.getDocuments()
        
        print("🔍 登録ユーザー数: \(snapshot.documents.count)")
        
        for doc in snapshot.documents {
            guard var registrations = doc.get("registrations") as? [[String: Any]] else {
                continue
            }
            
            var updated = false
            var foundUserRegistration = false
            for index in registrations.indices {
                let reg = registrations[index]
                guard let regPrefecture = reg["prefecture"] as? String, regPrefecture == prefectureName else {
                    continue
                }
                
                foundUserRegistration = true
                
                let userID = doc.documentID
                let baseValue = reg["baseGaugeValue"] as? Int ?? 0
                let maxValue = reg["maxGaugeValue"] as? Int ?? 100
                let completedCount = reg["completedCount"] as? Int ?? 0
                let lastCompletedAt = (reg["lastCompletedAt"] as? Timestamp)?.dateValue()
                
                // ユーザーの相対的なゲージ値を計算
                let userRelativeValue = newValue - baseValue
                
                print("👤 ユーザー \(userID) のゲージ: \(userRelativeValue)/\(maxValue) (共有値: \(newValue), 基準値: \(baseValue))")
                
                // ゲージが満タンになったかチェック
                if userRelativeValue >= maxValue {
                    // 前回の完了から新しい完了かチェック
                    let previousRelativeValue = currentValue - baseValue
                    let isNewCompletion = previousRelativeValue < maxValue
                    
                    if isNewCompletion {
                        // 新しいゲージ完了
                        let nextMaxValue = max(maxValue + 20, Int(ceil(Double(maxValue) * 1.2)))
                        registrations[index]["baseGaugeValue"] = newValue  // 新しい基準値
                        registrations[index]["maxGaugeValue"] = nextMaxValue
                        registrations[index]["completedCount"] = completedCount + 1
                        registrations[index]["lastCompletedAt"] = Timestamp(date: Date())
                        updated = true
                        
                        print("🎉 \(prefectureName)ゲージ満タン！")
                        print("   旧基準値: \(baseValue) → 新基準値: \(newValue)")
                        print("   旧最大値: \(maxValue) → 新最大値: \(nextMaxValue)")
                        print("   完了回数: \(completedCount) → \(completedCount + 1)")
                        
                        // 報酬と通知
                        let userID = doc.documentID
                        let newCompletedCount = completedCount + 1
                        
                        // 完了回数に応じた報酬を計算
                        let rewards = calculateRewards(completedCount: newCompletedCount)
                        
                        // 報酬付与（共有ゲージなので全員同じ）
                        if userID == UserService.shared.currentUserID {
                            // 経験値
                            UserService.shared.addExperience(points: rewards.experience)
                            // 投稿回数
                            UserService.shared.addPostCountBonus(count: rewards.postBonus)
                            print("✅ レベル\(newCompletedCount)報酬: 経験値+\(rewards.experience), 投稿回数+\(rewards.postBonus)")
                        }
                        
                        // 通知を送信
                        try? await createNotification(
                            type: .gaugeFilled,
                            title: "ゲージがたまりました！",
                            body: "\(prefectureName)のゲージが満タン！経験値+\(rewards.experience)、投稿回数+\(rewards.postBonus)を獲得",
                            relatedID: prefectureName,
                            toUserID: userID
                        )
                        
                        // 報酬を配布
                        try? await distributeRewardsToUser(userID: userID, prefecture: prefectureName, registrationIndex: index)
                    }
                }
            }
            
            if !foundUserRegistration && doc.documentID == UserService.shared.currentUserID {
                print("⚠️ 現在のユーザーは \(prefectureName) に登録されていません")
            }
            
            if updated {
                try await doc.reference.setData([
                    "registrations": registrations
                ], merge: true)
                print("✅ ユーザー \(doc.documentID) のゲージ完了状態を更新しました")
            }
        }
        
        print("✅ ゲージ更新処理完了: \(prefectureName)")
    }
    
    // 完了回数に応じた報酬を計算
    private func calculateRewards(completedCount: Int) -> (experience: Int, postBonus: Int) {
        // 10回ごとに報酬が増える
        let tier = completedCount / 10
        
        // 経験値: 基本100 + (tier * 50)
        let experience = 100 + (tier * 50)
        
        // 投稿回数ボーナス: 基本1 + (tier / 2)
        let postBonus = 1 + (tier / 2)
        
        return (experience, postBonus)
    }
    
    // ゲージ満タン時にユーザーに報酬を配布
    private func distributeRewardsToUser(userID: String, prefecture: String, registrationIndex: Int? = nil) async throws {
        // 報酬は updatePrefectureGauge() 内で処理される
        print("✅ \(prefecture)のゲージ満タン報酬を配布しました")
    }
    
    // 都道府県ゲージ一覧を取得
    // ユーザーごとのゲージを取得（新システム：共有ゲージから基準値を引いた相対値）
    func fetchUserPrefectureGauges(userID: String? = nil, forceServerFetch: Bool = false) async throws -> [PrefectureGauge] {
        let targetUserID = userID ?? UserService.shared.currentUserID
        let docRef = db.collection(userRegistrationsCollectionName).document(targetUserID)
        
        // forceServerFetchがtrueの場合、キャッシュをバイパスしてサーバーから直接取得
        let document = forceServerFetch 
            ? try await docRef.getDocument(source: .server)
            : try await docRef.getDocument()
        
        print("📊 fetchUserPrefectureGauges 開始 - userID: \(targetUserID), forceServer: \(forceServerFetch)")
        
        guard document.exists else {
            print("⚠️ ユーザー登録ドキュメントが存在しません")
            return []
        }
        
        guard let registrations = document.get("registrations") as? [[String: Any]] else {
            print("⚠️ registrations フィールドが存在しないか、形式が不正です")
            return []
        }
        
        print("✅ 登録数: \(registrations.count)")
        
        // 共有ゲージの値を取得（forceServerFetchの場合はキャッシュをバイパス）
        let gaugesSnapshot = forceServerFetch 
            ? try await db.collection(prefectureGaugesCollectionName).getDocuments(source: .server)
            : try await db.collection(prefectureGaugesCollectionName).getDocuments()
        var sharedGauges: [String: Int] = [:]
        for doc in gaugesSnapshot.documents {
            if let id = doc.get("id") as? String,
               let currentValue = doc.get("currentValue") as? Int {
                sharedGauges[id] = currentValue
            }
        }
        
        print("✅ 共有ゲージ数: \(sharedGauges.count)")
        
        return registrations.compactMap { registration -> PrefectureGauge? in
            guard
                let prefectureName = registration["prefecture"] as? String,
                let prefecture = Prefecture.allCases.first(where: { $0.rawValue == prefectureName })
            else {
                print("⚠️ 都道府県名の取得に失敗")
                return nil
            }
            
            let baseValue = registration["baseGaugeValue"] as? Int ?? 0
            let sharedCurrentValue = sharedGauges[prefectureName] ?? 0
            let maxValue = registration["maxGaugeValue"] as? Int ?? 100
            let completedCount = registration["completedCount"] as? Int ?? 0
            let lastUpdated = (registration["lastUpdated"] as? Timestamp)?.dateValue() ?? Date()
            let completedDate = (registration["lastCompletedAt"] as? Timestamp)?.dateValue()
            
            // ユーザーの相対的なゲージ値を計算（共有ゲージ - 基準値）
            let userRelativeValue = max(0, sharedCurrentValue - baseValue)
            
            print("📊 \(prefectureName): 共有=\(sharedCurrentValue), 基準=\(baseValue), 相対=\(userRelativeValue)/\(maxValue)")
            
            return PrefectureGauge(
                prefecture: prefecture,
                currentValue: userRelativeValue,
                maxValue: maxValue,
                lastUpdated: lastUpdated,
                completedDate: completedDate,
                completedCount: completedCount
            )
        }
    }
    
    // 旧システム：全ユーザー共通のゲージ（互換性のために残す）
    func fetchPrefectureGauges(forceServerFetch: Bool = false) async throws -> [PrefectureGauge] {
        // 新システムを使用
        return try await fetchUserPrefectureGauges(forceServerFetch: forceServerFetch)
    }
    
    // 全国ランキング用：全都道府県の共有ゲージを取得
    func fetchAllSharedGauges() async throws -> [PrefectureGauge] {
        let snapshot = try await db.collection(prefectureGaugesCollectionName).getDocuments()
        
        var gauges: [PrefectureGauge] = []
        
        for doc in snapshot.documents {
            guard
                let id = doc.get("id") as? String,
                let prefecture = Prefecture.allCases.first(where: { $0.rawValue == id })
            else {
                continue
            }
            
            let currentValue = doc.get("currentValue") as? Int ?? 0
            let lastUpdated = (doc.get("lastUpdated") as? Timestamp)?.dateValue() ?? Date()
            
            // 共有ゲージの値をそのまま使用
            // completedCountは共有ゲージには存在しないので、currentValue / 100 で概算
            let estimatedCompletedCount = currentValue / 100
            
            gauges.append(PrefectureGauge(
                prefecture: prefecture,
                currentValue: currentValue,
                maxValue: 100,
                lastUpdated: lastUpdated,
                completedDate: nil,
                completedCount: estimatedCompletedCount
            ))
        }
        
        // 登録されていない都道府県も0で追加
        for prefecture in Prefecture.allCases {
            if !gauges.contains(where: { $0.id == prefecture.rawValue }) {
                gauges.append(PrefectureGauge(prefecture: prefecture, currentValue: 0, maxValue: 100))
            }
        }
        
        return gauges
    }
    
    // 旧実装（参考用にコメントアウト）
    /*
    func fetchPrefectureGauges() async throws -> [PrefectureGauge] {
        let snapshot = try await db.collection(prefectureGaugesCollectionName).getDocuments()
        
        return snapshot.documents.compactMap { doc -> PrefectureGauge? in
            guard
                let id = doc.get("id") as? String,
                let currentValue = doc.get("currentValue") as? Int,
                let maxValue = doc.get("maxValue") as? Int,
                let lastUpdated = (doc.get("lastUpdated") as? Timestamp)?.dateValue()
            else {
                return nil
            }
            
            let completedDate = (doc.get("completedDate") as? Timestamp)?.dateValue()
            let completedCount = doc.get("completedCount") as? Int ?? 0
            
            guard let prefecture = Prefecture.allCases.first(where: { $0.rawValue == id }) else {
                return nil
            }
            
            return PrefectureGauge(
                prefecture: prefecture,
                currentValue: currentValue,
                maxValue: maxValue,
                lastUpdated: lastUpdated,
                completedDate: completedDate,
                completedCount: completedCount
            )
        }
    }
    */
    
    // ユーザーの都道府県登録情報を取得
    func fetchUserPrefectureRegistrations(forceServerFetch: Bool = false) async throws -> [UserPrefectureRegistration] {
        let currentUserID = UserService.shared.currentUserID
        let docRef = db.collection(userRegistrationsCollectionName).document(currentUserID)
        
        // forceServerFetchがtrueの場合、キャッシュをバイパスしてサーバーから直接取得
        let document = forceServerFetch 
            ? try await docRef.getDocument(source: .server)
            : try await docRef.getDocument()
        
        guard document.exists,
              let data = document.data(),
              let registrationsData = data["registrations"] as? [[String: Any]] else {
            return []
        }
        
        // ユーザーごとに複数の都道府県を登録できる構造
        var registrations: [UserPrefectureRegistration] = []
        
        for regData in registrationsData {
            guard
                let prefecture = regData["prefecture"] as? String,
                let registeredAt = (regData["registeredAt"] as? Timestamp)?.dateValue()
            else {
                continue
            }
            
            let stars = regData["stars"] as? Int ?? 0
            let titles = regData["titles"] as? [String] ?? []
            let baseGaugeValue = regData["baseGaugeValue"] as? Int ?? 0
            let maxGaugeValue = regData["maxGaugeValue"] as? Int ?? 100
            let completedCount = regData["completedCount"] as? Int ?? 0
            let lastCompletedAt = (regData["lastCompletedAt"] as? Timestamp)?.dateValue()
            
            registrations.append(UserPrefectureRegistration(
                prefecture: prefecture,
                registeredAt: registeredAt,
                stars: stars,
                titles: titles,
                baseGaugeValue: baseGaugeValue,
                maxGaugeValue: maxGaugeValue,
                completedCount: completedCount,
                lastCompletedAt: lastCompletedAt
            ))
        }
        
        return registrations
    }

    // ユーザーの称号一覧を取得（都道府県登録と共通称号を統合）
    func fetchUserTitles(userID: String? = nil) async throws -> [String] {
        let targetUserID = userID ?? UserService.shared.currentUserID
        let docRef = db.collection(userRegistrationsCollectionName).document(targetUserID)
        let document = try await docRef.getDocument()
        guard document.exists, let data = document.data() else {
            return []
        }
        
        var titles: [String] = data["titles"] as? [String] ?? []
        
        if let registrationsData = data["registrations"] as? [[String: Any]] {
            for regData in registrationsData {
                let regTitles = regData["titles"] as? [String] ?? []
                titles.append(contentsOf: regTitles)
            }
        }
        
        return Array(Set(titles)).sorted()
    }

    // ユーザーに称号を追加（共通称号）
    func addUserTitle(userID: String, title: String) async throws {
        let docRef = db.collection(userRegistrationsCollectionName).document(userID)
        try await docRef.setData([
            "titles": FieldValue.arrayUnion([title])
        ], merge: true)
    }

    // アイコンフレームを追加
    func addUserIconFrame(userID: String, frameID: String) async throws {
        let docRef = db.collection(userRegistrationsCollectionName).document(userID)
        try await docRef.setData([
            "iconFrames": FieldValue.arrayUnion([frameID])
        ], merge: true)
    }

    // レベルアップ報酬を付与
    func awardLevelRewards(from oldLevel: Int, to newLevel: Int, userID: String? = nil) async throws {
        let targetUserID = userID ?? UserService.shared.currentUserID
        let milestones = [10, 20, 40, 50, 100]
        let achieved = milestones.filter { $0 > oldLevel && $0 <= newLevel }
        guard !achieved.isEmpty else { return }

        let docRef = db.collection(userRegistrationsCollectionName).document(targetUserID)
        let document = try await docRef.getDocument()
        let rewarded = document.get("levelRewards") as? [Int] ?? []

        for level in achieved where !rewarded.contains(level) {
            let title = "レベル\(level)達成"
            let frameID = "level_\(level)"
            try await addUserTitle(userID: targetUserID, title: title)
            try await addUserIconFrame(userID: targetUserID, frameID: frameID)
            
            // 報酬を計算（レベルに応じて増加）
            let expReward = level * 10  // レベル10=100 XP, レベル20=200 XP, など
            let postBonusReward = max(1, level / 20)  // レベル20=1回, レベル40=2回, など
            
            // 報酬を付与（自分自身の場合のみUserServiceを使用）
            if targetUserID == UserService.shared.currentUserID {
                UserService.shared.addExperience(points: expReward)
                UserService.shared.addPostCountBonus(count: postBonusReward)
            } else {
                // 他のユーザーの場合はFirestoreに直接追加
                try await db.collection(usersCollectionName).document(targetUserID).setData([
                    "experiencePoints": FieldValue.increment(Int64(expReward)),
                    "experienceUpdatedAt": Timestamp(date: Date())
                ], merge: true)
                
                // 投稿回数ボーナスもFirestoreに保存（仮実装：実際にはユーザーごとの管理が必要）
                print("⚠️ 他のユーザーへの投稿回数ボーナスは未実装")
            }
            
            print("🎉 ユーザー \(targetUserID) のレベル\(level)達成報酬: 経験値+\(expReward), 投稿回数+\(postBonusReward)")
            
            try? await createNotification(
                type: .missionCleared,
                title: "ミッション達成",
                body: "レベル\(level)達成！経験値+\(expReward), 投稿回数+\(postBonusReward)回を獲得",
                relatedID: "level_\(level)",
                toUserID: targetUserID
            )
        }

        let newRewarded = Array(Set(rewarded + achieved))
        try await docRef.setData([
            "levelRewards": newRewarded
        ], merge: true)
    }

    // アイコンフレーム一覧と選択中のフレームを取得
    func fetchUserIconFrames(userID: String? = nil) async throws -> (frames: [String], selected: String?) {
        let targetUserID = userID ?? UserService.shared.currentUserID
        let docRef = db.collection(userRegistrationsCollectionName).document(targetUserID)
        let document = try await docRef.getDocument()
        guard document.exists, let data = document.data() else {
            return ([], nil)
        }
        let frames = data["iconFrames"] as? [String] ?? []
        let selected = data["selectedIconFrame"] as? String
        return (frames, selected)
    }

    // 選択中のアイコンフレームを更新
    func setSelectedIconFrame(userID: String, frameID: String?) async throws {
        let docRef = db.collection(userRegistrationsCollectionName).document(userID)
        try await docRef.setData([
            "selectedIconFrame": frameID ?? ""
        ], merge: true)
    }

    // モヤ討伐回数をカウントし、節目で称号を付与
    private func incrementMistClearCountAndAward(userID: String) async throws {
        let docRef = db.collection(userRegistrationsCollectionName).document(userID)
        let document = try await docRef.getDocument()
        let current = (document.get("mistClearCount") as? Int) ?? 0
        let newCount = current + 1

        try await docRef.setData([
            "mistClearCount": newCount
        ], merge: true)

        switch newCount {
        case 10:
            try await addUserTitle(userID: userID, title: "モヤ討伐10回達成")
            try await addUserIconFrame(userID: userID, frameID: "mist_clear_10")
            let selected = document.get("selectedIconFrame") as? String
            if selected == nil || selected == "" {
                try await setSelectedIconFrame(userID: userID, frameID: "mist_clear_10")
            }
            // 報酬付与
            let expReward = 80
            let postBonus = 1
            UserService.shared.addExperience(points: expReward)
            UserService.shared.addPostCountBonus(count: postBonus)
            print("🎉 モヤ討伐10回達成報酬: 経験値+\(expReward), 投稿回数+\(postBonus)")
            
            try? await createNotification(
                type: .missionCleared,
                title: "ミッション達成",
                body: "モヤ討伐10回達成！経験値+\(expReward), 投稿回数+\(postBonus)回を獲得",
                relatedID: "mist_clear_10",
                toUserID: userID
            )
        case 20:
            try await addUserTitle(userID: userID, title: "モヤ討伐20回達成")
            try await addUserIconFrame(userID: userID, frameID: "mist_clear_20")
            // 報酬付与
            let expReward = 150
            let postBonus = 1
            UserService.shared.addExperience(points: expReward)
            UserService.shared.addPostCountBonus(count: postBonus)
            print("🎉 モヤ討伐20回達成報酬: 経験値+\(expReward), 投稿回数+\(postBonus)")
            
            try? await createNotification(
                type: .missionCleared,
                title: "ミッション達成",
                body: "モヤ討伐20回達成！経験値+\(expReward), 投稿回数+\(postBonus)回を獲得",
                relatedID: "mist_clear_20",
                toUserID: userID
            )
        case 30:
            try await addUserTitle(userID: userID, title: "モヤ討伐30回達成")
            try await addUserIconFrame(userID: userID, frameID: "mist_clear_30")
            // 報酬付与
            let expReward = 220
            let postBonus = 2
            UserService.shared.addExperience(points: expReward)
            UserService.shared.addPostCountBonus(count: postBonus)
            print("🎉 モヤ討伐30回達成報酬: 経験値+\(expReward), 投稿回数+\(postBonus)")
            
            try? await createNotification(
                type: .missionCleared,
                title: "ミッション達成",
                body: "モヤ討伐30回達成！経験値+\(expReward), 投稿回数+\(postBonus)回を獲得",
                relatedID: "mist_clear_30",
                toUserID: userID
            )
        case 40:
            try await addUserTitle(userID: userID, title: "モヤ討伐40回達成")
            try await addUserIconFrame(userID: userID, frameID: "mist_clear_40")
            // 報酬付与
            let expReward = 300
            let postBonus = 2
            UserService.shared.addExperience(points: expReward)
            UserService.shared.addPostCountBonus(count: postBonus)
            print("🎉 モヤ討伐40回達成報酬: 経験値+\(expReward), 投稿回数+\(postBonus)")
            
            try? await createNotification(
                type: .missionCleared,
                title: "ミッション達成",
                body: "モヤ討伐40回達成！経験値+\(expReward), 投稿回数+\(postBonus)回を獲得",
                relatedID: "mist_clear_40",
                toUserID: userID
            )
        case 50:
            try await addUserTitle(userID: userID, title: "モヤ討伐50回達成")
            try await addUserIconFrame(userID: userID, frameID: "mist_clear_50")
            // 報酬付与
            let expReward = 400
            let postBonus = 3
            UserService.shared.addExperience(points: expReward)
            UserService.shared.addPostCountBonus(count: postBonus)
            print("🎉 モヤ討伐50回達成報酬: 経験値+\(expReward), 投稿回数+\(postBonus)")
            
            try? await createNotification(
                type: .missionCleared,
                title: "ミッション達成",
                body: "モヤ討伐50回達成！経験値+\(expReward), 投稿回数+\(postBonus)回を獲得",
                relatedID: "mist_clear_50",
                toUserID: userID
            )
        case 100:
            try await addUserTitle(userID: userID, title: "モヤ討伐100回達成")
            try await addUserIconFrame(userID: userID, frameID: "mist_clear_100")
            // 報酬付与
            let expReward = 800
            let postBonus = 5
            UserService.shared.addExperience(points: expReward)
            UserService.shared.addPostCountBonus(count: postBonus)
            print("🎉 モヤ討伐100回達成報酬: 経験値+\(expReward), 投稿回数+\(postBonus)")
            
            try? await createNotification(
                type: .missionCleared,
                title: "ミッション達成",
                body: "モヤ討伐100回達成！経験値+\(expReward), 投稿回数+\(postBonus)回を獲得",
                relatedID: "mist_clear_100",
                toUserID: userID
            )
        default:
            break
        }
    }
    
    // 都道府県に登録
    func registerToPrefecture(_ prefecture: Prefecture) async throws {
        let currentUserID = UserService.shared.currentUserID
        let docRef = db.collection(userRegistrationsCollectionName).document(currentUserID)
        let document = try await docRef.getDocument()
        
        var registrations: [[String: Any]] = []
        
        if document.exists, let existingRegistrations = document.get("registrations") as? [[String: Any]] {
            registrations = existingRegistrations
        }
        
        // 既に登録されているかチェック
        let prefectureName = prefecture.rawValue
        if registrations.contains(where: { ($0["prefecture"] as? String) == prefectureName }) {
            print("ℹ️ \(prefectureName)は既に登録済みです")
            return // 既に登録済み
        }
        
        // 共有ゲージの現在値を取得（存在しない場合は0）
        let gaugeRef = db.collection(prefectureGaugesCollectionName).document(prefectureName)
        let gaugeDoc = try await gaugeRef.getDocument()
        let currentSharedValue = gaugeDoc.get("currentValue") as? Int ?? 0
        
        print("📍 \(prefectureName)に登録 - 共有ゲージ値: \(currentSharedValue)")
        
        // 共有ゲージが存在しない場合は作成
        if !gaugeDoc.exists {
            try await gaugeRef.setData([
                "id": prefectureName,
                "currentValue": 0,
                "lastUpdated": Timestamp(date: Date()),
                "contributorIDs": []
            ])
            print("✅ \(prefectureName)の共有ゲージを作成しました")
        }
        
        // 新しい登録を追加（登録時点の共有ゲージ値を基準値として記録）
        registrations.append([
            "prefecture": prefectureName,
            "registeredAt": Timestamp(date: Date()),
            "stars": 0,
            "titles": [],
            "baseGaugeValue": currentSharedValue,  // 登録時点の共有ゲージ値を基準値として記録
            "maxGaugeValue": 100,
            "completedCount": 0
        ])
        
        try await docRef.setData([
            "registrations": registrations
        ], merge: true)
        
        print("✅ \(prefectureName)に登録完了（基準値: \(currentSharedValue)）")
    }
}

// MARK: - 友達関連のモデル

struct FriendRequest: Identifiable {
    let id: String
    let fromUserID: String
    let toUserID: String
    let status: String // pending, accepted, rejected
    let createdAt: Date
    let acceptedAt: Date?
    
    init(id: String, fromUserID: String, toUserID: String, status: String, createdAt: Date, acceptedAt: Date? = nil) {
        self.id = id
        self.fromUserID = fromUserID
        self.toUserID = toUserID
        self.status = status
        self.createdAt = createdAt
        self.acceptedAt = acceptedAt
    }
}

struct FriendRequestStatus {
    let status: String
    let isFromMe: Bool? // nilの場合は友達関係
}

// MARK: - モヤイベント管理

extension FirestoreService {
    private var mistEventsCollectionName: String { "mistEvents" }
    private var eventDetectionRadius: Double { 3.0 } // 3km
    private var negativeEmotionsRequired: Int { 4 } // イベント発生に必要な負の感情の数
    private var mistDamagePerPost: Int { 10 } // モヤ投稿1回あたりのダメージ
    // 体力は自然回復させるが、投稿効果を打ち消さないように1分あたり1回復にする
    private var mistHPRegenPerSecond: Int { 1 }

    // 負の感情が4つ集まったかチェックしてイベントを作成
    private func checkAndCreateMistEvent(latitude: Double, longitude: Double) async throws {
        // 最近24時間以内の投稿を取得
        let recentPosts = try await fetchRecentEmotions(lastHours: 24, includeOnlyFriends: false)
        
        // 指定位置の周囲（500m）の負の感情をカウント
        let negativePosts = recentPosts.filter { post in
            guard let postLat = post.latitude,
                  let postLon = post.longitude,
                  post.level.rawValue < 0 else {
                return false
            }
            
            let distance = calculateDistance(
                lat1: latitude, lon1: longitude,
                lat2: postLat, lon2: postLon
            )
            return distance <= eventDetectionRadius
        }
        
        // 負の感情が4つ以上ある場合、イベントを作成
        if negativePosts.count >= negativeEmotionsRequired {
            // 既存のイベントがあるかチェック
            let existingEvents = try await fetchActiveMistEvents()
            let hasExistingEvent = existingEvents.contains { event in
                event.containsInExpandedArea(
                    latitude: latitude,
                    longitude: longitude,
                    growthPerMinuteKm: 0.1
                )
            }
            
            if !hasExistingEvent {
                // 負の感情の中心座標を計算
                let avgLat = negativePosts.compactMap { $0.latitude }.reduce(0, +) / Double(negativePosts.count)
                let avgLon = negativePosts.compactMap { $0.longitude }.reduce(0, +) / Double(negativePosts.count)
                let prefectureName = await findPrefectureByCoordinate(latitude: avgLat, longitude: avgLon)?.rawValue ?? "不明"
                
                // イベントを作成
                let event = MistEvent(
                    centerLatitude: avgLat,
                    centerLongitude: avgLon,
                    prefectureName: prefectureName,
                    radius: eventDetectionRadius,
                    currentHP: 150,
                    maxHP: 150
                )
                
                try await createMistEvent(event)

                // 通知を送信
                NotificationService.shared.sendMistEventNotification(
                    prefectureName: prefectureName,
                    latitude: avgLat,
                    longitude: avgLon
                )
            }
        }
    }
    
    // 正の感情でモヤのHPを減らす
    private func reduceMistEventHP(
        latitude: Double,
        longitude: Double,
        emotionLevel: EmotionLevel,
        authorID: String,
        isMistCleanupPost: Bool
    ) async throws {
        let activeEvents = try await fetchActiveMistEvents()
        
        // この位置を含むイベントを探す
        for event in activeEvents {
            if event.containsInExpandedArea(
                latitude: latitude,
                longitude: longitude,
                growthPerMinuteKm: 0.1
            ) {
                let eventRef = db.collection(mistEventsCollectionName).document(event.id)
                try await eventRef.setData([
                    "contributorIDs": FieldValue.arrayUnion([authorID])
                ], merge: true)
                
                // 時間経過でHPが自然回復する（lastUpdated基準）
                let now = Date()
                let elapsedSeconds = max(0, now.timeIntervalSince(event.lastUpdated))
                // 自然回復は秒単位ではなく分単位で計算（回復が速すぎるのを防ぐ）
                let regenElapsedSeconds = elapsedSeconds / 60.0
                let combatResult = MistCombatMath.applyPositivePost(
                    currentHP: event.currentHP,
                    maxHP: event.maxHP,
                    currentHappyPostCount: event.happyPostCount,
                    isMistCleanupPost: isMistCleanupPost,
                    elapsedSeconds: regenElapsedSeconds,
                    regenPerSecond: mistHPRegenPerSecond,
                    damagePerPost: mistDamagePerPost,
                    clearCountThreshold: 5
                )
                let clearByCount = combatResult.clearByCount
                let clearByHP = combatResult.clearByHP

                // モヤ浄化投稿はHP0でのみ消滅。通常投稿は5回達成でも消滅可能。
                if clearByCount || clearByHP {
                    // イベント終了
                    let clearReason = clearByCount ? "通常投稿5回で浄化" : "HP0で浄化"
                    print("✨ モヤイベント終了: \(clearReason)")
                    
                    try await eventRef.setData([
                        "currentHP": 0,
                        "happyPostCount": combatResult.nextHappyPostCount,
                        "isActive": false,
                        "lastUpdated": Timestamp(date: now)
                    ], merge: true)
                    UserService.shared.addExperience(points: 50)
                    let contributors = Array(Set(event.contributorIDs + [authorID]))
                    for userID in contributors {
                        try? await incrementMistClearCountAndAward(userID: userID)
                        let bodyMessage = clearByCount
                            ? "\(event.prefectureName)のモヤを通常投稿5回で浄化しました！"
                            : "\(event.prefectureName)のモヤを浄化しました！"
                        try await createNotification(
                            type: .mistCleared,
                            title: "モヤを倒しました！",
                            body: bodyMessage,
                            relatedID: event.id,
                            toUserID: userID
                        )
                    }
                    // ローカル通知（この端末のユーザーにだけ表示）
                    if authorID == UserService.shared.currentUserID {
                        NotificationService.shared.sendMistClearedNotification(prefectureName: event.prefectureName)
                    }
                } else {
                    // HPと嬉しい投稿カウントを更新
                    try await eventRef.setData([
                        "currentHP": combatResult.nextHP,
                        "happyPostCount": combatResult.nextHappyPostCount,
                        "lastUpdated": Timestamp(date: now)
                    ], merge: true)
                }
                
                break // 1つのイベントのみ処理
            }
        }
    }
    
    // モヤイベントを作成
    private func createMistEvent(_ event: MistEvent) async throws {
        let eventRef = db.collection(mistEventsCollectionName).document(event.id)
        
        try await eventRef.setData([
            "id": event.id,
            "centerLatitude": event.centerLatitude,
            "centerLongitude": event.centerLongitude,
            "prefectureName": event.prefectureName,
            "radius": event.radius,
            "currentHP": event.currentHP,
            "maxHP": event.maxHP,
            "happyPostCount": event.happyPostCount,
            "createdAt": Timestamp(date: event.createdAt),
            "lastUpdated": Timestamp(date: event.lastUpdated),
            "isActive": event.isActive,
            "contributorIDs": event.contributorIDs
        ])
    }

    // テスト用モヤイベントを作成（開発中のみ）
    func createTestMistEvent(_ event: MistEvent) async throws {
        try await createMistEvent(event)
    }
    
    // アクティブなモヤイベントを取得
    func fetchActiveMistEvents() async throws -> [MistEvent] {
        let snapshot = try await db.collection(mistEventsCollectionName)
            .whereField("isActive", isEqualTo: true)
            .getDocuments()
        
        let events = snapshot.documents.compactMap { doc -> MistEvent? in
            guard
                let id = doc.get("id") as? String,
                let centerLatitude = doc.get("centerLatitude") as? Double,
                let centerLongitude = doc.get("centerLongitude") as? Double,
                let prefectureName = doc.get("prefectureName") as? String,
                let radius = doc.get("radius") as? Double,
                let currentHP = doc.get("currentHP") as? Int,
                let maxHP = doc.get("maxHP") as? Int,
                let createdAt = (doc.get("createdAt") as? Timestamp)?.dateValue(),
                let lastUpdated = (doc.get("lastUpdated") as? Timestamp)?.dateValue(),
                let isActive = doc.get("isActive") as? Bool
            else {
                return nil
            }
            
            let contributorIDs = doc.get("contributorIDs") as? [String] ?? []
            let happyPostCount = doc.get("happyPostCount") as? Int ?? 0
            
            // 時間経過でHPを自然回復表示（サーバー保存は投稿時に実施）
            let now = Date()
            // 表示上の自然回復も分単位で統一
            let elapsedSeconds = max(0, now.timeIntervalSince(lastUpdated))
            let regenHP = Int(elapsedSeconds / 60.0) * mistHPRegenPerSecond
            let effectiveHP = min(maxHP, currentHP + regenHP)

            return MistEvent(
                id: id,
                centerLatitude: centerLatitude,
                centerLongitude: centerLongitude,
                prefectureName: prefectureName,
                radius: radius,
                currentHP: effectiveHP,
                maxHP: maxHP,
                happyPostCount: happyPostCount,
                createdAt: createdAt,
                lastUpdated: lastUpdated,
                isActive: isActive,
                contributorIDs: contributorIDs
            )
        }

        // 取得順のブレで表示対象が入れ替わらないよう、更新日時の新しい順に固定
        return events.sorted { $0.lastUpdated > $1.lastUpdated }
    }
}

// MARK: - スポット管理

extension FirestoreService {
    private var spotsCollectionName: String { "spots" }
    private var seededSpotsVersionKey: String { "com.nao.hyu.seededSpotsVersion.v6" }
    private var currentSpotsVersion: Int { 15 } // コクーンタワー追加
    
    // アクティブなスポットを取得
    func fetchActiveSpots() async throws -> [Spot] {
        let snapshot = try await db.collection(spotsCollectionName)
            .whereField("isActive", isEqualTo: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc -> Spot? in
            guard
                let id = doc.get("id") as? String,
                let name = doc.get("name") as? String,
                let latitude = doc.get("latitude") as? Double,
                let longitude = doc.get("longitude") as? Double,
                let radius = doc.get("radius") as? Double,
                let isActive = doc.get("isActive") as? Bool
            else {
                return nil
            }
            
            return Spot(
                id: id,
                name: name,
                latitude: latitude,
                longitude: longitude,
                radius: radius,
                isActive: isActive
            )
        }
    }

    // 管理者用：全スポットを取得
    func fetchAllSpots() async throws -> [Spot] {
        let snapshot = try await db.collection(spotsCollectionName).getDocuments()
        return snapshot.documents.compactMap { doc -> Spot? in
            guard
                let id = doc.get("id") as? String,
                let name = doc.get("name") as? String,
                let latitude = doc.get("latitude") as? Double,
                let longitude = doc.get("longitude") as? Double,
                let radius = doc.get("radius") as? Double,
                let isActive = doc.get("isActive") as? Bool
            else {
                return nil
            }

            return Spot(
                id: id,
                name: name,
                latitude: latitude,
                longitude: longitude,
                radius: radius,
                isActive: isActive
            )
        }
    }

    // 管理者用：スポットの有効/無効を更新
    func updateSpotActive(spotID: String, isActive: Bool) async throws {
        try await db.collection(spotsCollectionName)
            .document(spotID)
            .setData(["isActive": isActive], merge: true)
    }

    // 管理者用：スポットを更新
    func updateSpot(
        spotID: String,
        name: String,
        latitude: Double,
        longitude: Double,
        radius: Double,
        isActive: Bool
    ) async throws {
        try await db.collection(spotsCollectionName)
            .document(spotID)
            .setData([
                "id": spotID,
                "name": name,
                "latitude": latitude,
                "longitude": longitude,
                "radius": radius,
                "isActive": isActive
            ], merge: true)
    }

    // 管理者用：スポットを削除
    func deleteSpot(spotID: String) async throws {
        try await db.collection(spotsCollectionName).document(spotID).delete()
    }
    
    // 指定位置に最も近いスポットを取得（範囲内の場合のみ）
    func findNearestSpot(latitude: Double, longitude: Double) async throws -> Spot? {
        let spots = try await fetchActiveSpots()
        return spots.first { $0.contains(latitude: latitude, longitude: longitude) }
    }
    
    // スポットを作成（管理用）
    func createSpot(_ spot: Spot) async throws {
        let spotRef = db.collection(spotsCollectionName).document(spot.id)
        
        try await spotRef.setData([
            "id": spot.id,
            "name": spot.name,
            "latitude": spot.latitude,
            "longitude": spot.longitude,
            "radius": spot.radius,
            "isActive": spot.isActive
        ])
    }

    private func deactivateAllActiveSpots() async {
        do {
            // すべてのスポットを取得（isActiveフィルタなし）
            let snapshot = try await db.collection(spotsCollectionName).getDocuments()
            for doc in snapshot.documents {
                let spotRef = db.collection(spotsCollectionName).document(doc.documentID)
                try await spotRef.setData([
                    "isActive": false
                ], merge: true)
            }
            print("✅ すべてのスポットを無効化しました: \(snapshot.documents.count)件")
        } catch {
            print("❌ スポットの無効化に失敗: \(error.localizedDescription)")
        }
    }

    private func deleteAllSpots() async {
        do {
            let snapshot = try await db.collection(spotsCollectionName).getDocuments()
            for doc in snapshot.documents {
                try await db.collection(spotsCollectionName).document(doc.documentID).delete()
            }
            print("✅ すべてのスポットを削除しました: \(snapshot.documents.count)件")
        } catch {
            print("❌ スポットの削除に失敗: \(error.localizedDescription)")
        }
    }

    private var spotDefinitions: [(prefecture: String, name: String)] {
        [
            ("北海道", "札幌時計台"),
            ("北海道", "小樽運河"),
            ("北海道", "富良野・美瑛のラベンダー畑"),
            ("青森県", "弘前城"),
            ("青森県", "十和田湖・奥入瀬渓流"),
            ("青森県", "三内丸山遺跡"),
            ("岩手県", "中尊寺"),
            ("岩手県", "平泉世界遺産"),
            ("岩手県", "浄土ヶ浜"),
            ("宮城県", "仙台城址"),
            ("宮城県", "松島湾・瑞巌寺"),
            ("宮城県", "鳴子温泉郷"),
            ("秋田県", "角館の武家屋敷通り"),
            ("秋田県", "田沢湖"),
            ("秋田県", "男鹿半島のなまはげ館"),
            ("山形県", "山寺の立石寺"),
            ("山形県", "蔵王連峰・御釜"),
            ("山形県", "銀山温泉"),
            ("福島県", "会津若松城（鶴ヶ城）"),
            ("福島県", "五色沼"),
            ("福島県", "大内宿"),
            ("茨城県", "偕楽園"),
            ("茨城県", "日立海浜公園"),
            ("茨城県", "鹿島神宮"),
            ("栃木県", "日光東照宮"),
            ("栃木県", "華厳の滝"),
            ("栃木県", "那須どうぶつ王国"),
            ("群馬県", "草津温泉"),
            ("群馬県", "富岡製糸場"),
            ("群馬県", "尾瀬ヶ原"),
            ("埼玉県", "川越の蔵造りの街並み"),
            ("埼玉県", "長瀞ライン下り"),
            ("埼玉県", "秩父神社"),
            ("千葉県", "東京ディズニーリゾート"),
            ("千葉県", "鴨川シーワールド"),
            ("千葉県", "成田山新勝寺"),
            ("東京都", "東京スカイツリー"),
            ("東京都", "浅草寺"),
            ("東京都", "明治神宮"),
            ("東京都", "東京タワー"),
            ("東京都", "コクーンタワー"),
            ("神奈川県", "鎌倉大仏（高徳院）"),
            ("神奈川県", "鶴岡八幡宮"),
            ("神奈川県", "横浜・みなとみらい"),
            ("新潟県", "佐渡金山"),
            ("新潟県", "越後湯沢温泉エリア"),
            ("新潟県", "弥彦山"),
            ("富山県", "黒部ダム"),
            ("富山県", "立山黒部アルペンルート"),
            ("富山県", "五箇山合掌造り集落"),
            ("石川県", "金沢城跡／兼六園"),
            ("石川県", "21世紀美術館"),
            ("石川県", "近江町市場"),
            ("福井県", "東尋坊"),
            ("福井県", "恐竜博物館"),
            ("福井県", "越前海岸"),
            ("山梨県", "富士山（河口湖周辺・五合目エリア）"),
            ("山梨県", "忍野八海"),
            ("山梨県", "甲府城跡"),
            ("長野県", "松本城"),
            ("長野県", "善光寺"),
            ("長野県", "上高地"),
            ("岐阜県", "白川郷合掌造り集落"),
            ("岐阜県", "高山の古い町並み"),
            ("岐阜県", "郡上八幡城"),
            ("静岡県", "富士山（世界遺産・周辺エリア）"),
            ("静岡県", "熱海温泉"),
            ("静岡県", "三保の松原"),
            ("愛知県", "名古屋城"),
            ("愛知県", "熱田神宮"),
            ("愛知県", "犬山城"),
            ("三重県", "伊勢神宮"),
            ("三重県", "熊野古道"),
            ("三重県", "鳥羽水族館"),
            ("滋賀県", "琵琶湖"),
            ("滋賀県", "彦根城"),
            ("滋賀県", "比叡山延暦寺"),
            ("京都府", "清水寺"),
            ("京都府", "金閣寺（鹿苑寺）"),
            ("京都府", "伏見稲荷大社"),
            ("大阪府", "大阪城"),
            ("大阪府", "道頓堀"),
            ("大阪府", "ユニバーサル・スタジオ・ジャパン"),
            ("兵庫県", "姫路城"),
            ("兵庫県", "有馬温泉"),
            ("兵庫県", "神戸・北野異人館街"),
            ("奈良県", "東大寺"),
            ("奈良県", "奈良公園"),
            ("奈良県", "吉野山"),
            ("和歌山県", "熊野古道"),
            ("和歌山県", "那智の滝"),
            ("和歌山県", "高野山"),
            ("鳥取県", "鳥取砂丘"),
            ("鳥取県", "白兎神社"),
            ("鳥取県", "倉吉の白壁土蔵群"),
            ("島根県", "出雲大社"),
            ("島根県", "石見銀山遺跡"),
            ("島根県", "松江城"),
            ("岡山県", "後楽園"),
            ("岡山県", "岡山城"),
            ("岡山県", "倉敷美観地区"),
            ("広島県", "広島平和記念公園・原爆ドーム"),
            ("広島県", "宮島（厳島神社）"),
            ("広島県", "呉の大和ミュージアム"),
            ("山口県", "秋吉台カルスト台地"),
            ("山口県", "瑠璃光寺五重塔"),
            ("山口県", "角島大橋"),
            ("徳島県", "阿波おどり会館"),
            ("徳島県", "渦の道"),
            ("徳島県", "鳴門公園（大鳴門橋架橋記念公園）"),
            ("香川県", "栗林公園"),
            ("香川県", "金刀比羅宮"),
            ("香川県", "小豆島・寒霞渓"),
            ("愛媛県", "道後温泉"),
            ("愛媛県", "松山城"),
            ("愛媛県", "しまなみ海道"),
            ("高知県", "高知城"),
            ("高知県", "桂浜"),
            ("高知県", "四万十川"),
            ("福岡県", "太宰府天満宮"),
            ("福岡県", "福岡タワー"),
            ("福岡県", "大濠公園"),
            ("佐賀県", "佐賀城跡"),
            ("佐賀県", "虹の松原"),
            ("佐賀県", "吉野ヶ里歴史公園"),
            ("長崎県", "グラバー園"),
            ("長崎県", "稲佐山夜景"),
            ("長崎県", "長崎原爆資料館・平和公園"),
            ("熊本県", "熊本城"),
            ("熊本県", "阿蘇山"),
            ("熊本県", "黒川温泉"),
            ("大分県", "別府温泉"),
            ("大分県", "湯布院"),
            ("大分県", "高崎山自然動物園"),
            ("宮崎県", "高千穂峡"),
            ("宮崎県", "日南海岸"),
            ("宮崎県", "青島神社"),
            ("鹿児島県", "屋久島"),
            ("鹿児島県", "桜島"),
            ("鹿児島県", "指宿温泉"),
            ("沖縄県", "美ら海水族館"),
            ("沖縄県", "首里城"),
            ("沖縄県", "今帰仁城跡")
        ]
    }

    private func spotCoordinateKey(prefecture: String, name: String) -> String {
        "\(prefecture)|\(name)"
    }

    private func generatePrefectureSpots() async -> [Spot] {
        let offsets: [(Double, Double)] = [
            (0.05, 0.05),
            (-0.05, 0.04),
            (0.04, -0.05)
        ]
        var spots: [Spot] = []
        var perPrefectureIndex: [String: Int] = [:]

        for (index, definition) in spotDefinitions.enumerated() {
            let prefKey = definition.prefecture
            let count = perPrefectureIndex[prefKey, default: 0]
            perPrefectureIndex[prefKey] = count + 1

            let lat: Double
            let lon: Double
            let coordinateKey = spotCoordinateKey(prefecture: definition.prefecture, name: definition.name)
            if let coordinates = spotCoordinates[coordinateKey] {
                lat = coordinates.0
                lon = coordinates.1
            } else {
                let base = prefectureCenter(prefecture: prefKey)
                let offset = offsets[count % offsets.count]
                lat = base.latitude + offset.0
                lon = base.longitude + offset.1
            }

            let spot = Spot(
                id: spotID(prefecture: definition.prefecture, name: definition.name, index: index + 1),
                name: definition.name,
                latitude: lat,
                longitude: lon,
                radius: 80
            )
            spots.append(spot)
        }

        return spots
    }

    private func prefectureCenter(prefecture: String) -> (latitude: Double, longitude: Double) {
        if let pref = Prefecture.allCases.first(where: { $0.rawValue == prefecture }) {
            return pref.centerCoordinate
        }
        return Prefecture.tokyo.centerCoordinate
    }

    private func spotID(prefecture: String, name: String, index: Int) -> String {
        let base = "\(prefecture)_\(name)"
        let sanitized = base
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "・", with: "")
            .replacingOccurrences(of: "／", with: "")
            .replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")
            .replacingOccurrences(of: "ー", with: "")
            .replacingOccurrences(of: "－", with: "")
            .replacingOccurrences(of: "—", with: "")
            .replacingOccurrences(of: "〜", with: "")
        return "spot_\(sanitized)_\(index)"
    }

    // 初期スポットを登録（バージョン更新時に再登録）
    func seedInitialSpotsIfNeeded() async {
        let storedVersion = UserDefaults.standard.integer(forKey: seededSpotsVersionKey)
        if storedVersion >= currentSpotsVersion {
            return
        }

        do {
            await deleteAllSpots()
            let spots = await generatePrefectureSpots()

            for spot in spots {
                try await createSpot(spot)
            }
            UserDefaults.standard.set(currentSpotsVersion, forKey: seededSpotsVersionKey)
        } catch {
            print("❌ 初期スポット登録に失敗: \(error.localizedDescription)")
        }
    }
    
    // MARK: - コンテンツモデレーション機能
    
    // 投稿を報告
    func reportPost(postID: String, reason: String) async throws {
        let currentUserID = UserService.shared.currentUserID
        let reportData: [String: Any] = [
            "postID": postID,
            "reporterID": currentUserID,
            "reason": reason,
            "createdAt": Timestamp(date: Date()),
            "status": "pending" // pending, reviewed, resolved
        ]
        
        try await db.collection("reports")
            .document("\(postID)_\(currentUserID)")
            .setData(reportData)
        
        print("✅ 投稿を報告しました: \(postID)")
    }
    
    // ユーザーをブロック
    func blockUser(blockedUserID: String) async throws {
        let currentUserID = UserService.shared.currentUserID
        
        // ブロック情報を保存
        try await db.collection("blocks")
            .document("\(currentUserID)_\(blockedUserID)")
            .setData([
                "blockerID": currentUserID,
                "blockedUserID": blockedUserID,
                "createdAt": Timestamp(date: Date())
            ])
        
        // 友達関係を削除（もし存在する場合）
        let friendships1 = try await db.collection("friendships")
            .whereField("userID1", isEqualTo: currentUserID)
            .whereField("userID2", isEqualTo: blockedUserID)
            .getDocuments()
        for doc in friendships1.documents {
            try await doc.reference.delete()
        }
        
        let friendships2 = try await db.collection("friendships")
            .whereField("userID1", isEqualTo: blockedUserID)
            .whereField("userID2", isEqualTo: currentUserID)
            .getDocuments()
        for doc in friendships2.documents {
            try await doc.reference.delete()
        }
        
        // 友達申請を削除
        let requests1 = try await db.collection("friendRequests")
            .whereField("fromUserID", isEqualTo: currentUserID)
            .whereField("toUserID", isEqualTo: blockedUserID)
            .getDocuments()
        for doc in requests1.documents {
            try await doc.reference.delete()
        }
        
        let requests2 = try await db.collection("friendRequests")
            .whereField("fromUserID", isEqualTo: blockedUserID)
            .whereField("toUserID", isEqualTo: currentUserID)
            .getDocuments()
        for doc in requests2.documents {
            try await doc.reference.delete()
        }
        
        print("✅ ユーザーをブロックしました: \(blockedUserID)")
    }
    
    // ユーザーのブロック解除
    func unblockUser(blockedUserID: String) async throws {
        let currentUserID = UserService.shared.currentUserID
        try await db.collection("blocks")
            .document("\(currentUserID)_\(blockedUserID)")
            .delete()
        print("✅ ユーザーのブロックを解除しました: \(blockedUserID)")
    }
    
    // ブロックされているユーザーIDのリストを取得
    func getBlockedUserIDs() async throws -> [String] {
        let currentUserID = UserService.shared.currentUserID
        let snapshot = try await db.collection("blocks")
            .whereField("blockerID", isEqualTo: currentUserID)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            doc.get("blockedUserID") as? String
        }
    }
    
    // 特定のユーザーがブロックされているかチェック
    func isUserBlocked(userID: String) async throws -> Bool {
        let currentUserID = UserService.shared.currentUserID
        let docRef = db.collection("blocks")
            .document("\(currentUserID)_\(userID)")
        let document = try await docRef.getDocument()
        return document.exists
    }
    
    // 報告された投稿を取得（管理者用）
    func getReportedPosts() async throws -> [[String: Any]] {
        // インデックス不要のシンプルなクエリに変更
        let snapshot = try await db.collection("reports")
            .whereField("status", isEqualTo: "pending")
            .limit(to: 100)
            .getDocuments()
        
        // クライアント側でソート
        let sortedDocs = snapshot.documents.sorted { doc1, doc2 in
            let date1 = (doc1.get("createdAt") as? Timestamp)?.dateValue() ?? Date.distantPast
            let date2 = (doc2.get("createdAt") as? Timestamp)?.dateValue() ?? Date.distantPast
            return date1 > date2
        }
        
        return sortedDocs.map { doc in
            var data = doc.data()
            data["reportID"] = doc.documentID
            return data
        }
    }
    
    // 報告を解決（管理者用）
    func resolveReport(reportID: String, action: String) async throws {
        try await db.collection("reports")
            .document(reportID)
            .updateData([
                "status": "resolved",
                "action": action,
                "resolvedAt": Timestamp(date: Date())
            ])
    }
    
    // MARK: - コメント機能
    
    // 投稿にコメントを追加（友達のみ）
    func addComment(postID: UUID, comment: String) async throws {
        let currentUserID = UserService.shared.currentUserID
        let currentUserName = UserService.shared.userName
        let commentID = UUID().uuidString
        
        // IDフィールドでクエリ検索（大文字小文字両方対応）
        let lowercaseID = postID.uuidString.lowercased()
        let normalID = postID.uuidString
        
        var snapshot = try await db.collection(collectionName)
            .whereField("id", isEqualTo: lowercaseID)
            .limit(to: 1)
            .getDocuments()
        
        if snapshot.documents.isEmpty {
            snapshot = try await db.collection(collectionName)
                .whereField("id", isEqualTo: normalID)
                .limit(to: 1)
                .getDocuments()
        }
        
        guard let postDoc = snapshot.documents.first,
              postDoc.exists,
              let authorID = postDoc.get("authorID") as? String else {
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "投稿が見つかりません"])
        }
        
        // 実際に使用されたドキュメントIDを取得
        let actualPostID = postDoc.documentID
        
        // 自分の投稿にはコメントできない
        if authorID == currentUserID {
            throw NSError(domain: "FirestoreService", code: 403, userInfo: [NSLocalizedDescriptionKey: "自分の投稿にはコメントできません"])
        }
        
        // 友達関係をチェック
        let isFriend = try await checkIfFriends(userID: authorID)
        print("📍 addComment友達チェック: authorID=\(authorID), isFriend=\(isFriend)")
        if !isFriend {
            throw NSError(domain: "FirestoreService", code: 403, userInfo: [NSLocalizedDescriptionKey: "友達の投稿にのみコメントできます"])
        }
        
        // コメントを保存（実際に見つかったpostIDを使用）
        let commentData: [String: Any] = [
            "id": commentID,
            "postID": actualPostID,
            "userID": currentUserID,
            "userName": currentUserName,
            "comment": comment,
            "createdAt": Timestamp(date: Date())
        ]
        
        try await db.collection("postComments")
            .document(commentID)
            .setData(commentData)
        
        print("✅ コメントを追加しました: postID=\(actualPostID), commentID=\(commentID)")
        
        // 投稿者に通知を送る
        print("\n📨 コメント通知の作成を開始")
        print("   - 送信先: \(authorID)")
        print("   - 送信元: \(currentUserName)")
        print("   - 投稿ID: \(actualPostID)")
        
        do {
            try await createNotification(
                type: .comment,
                title: "コメントがありました",
                body: "\(currentUserName)さんがあなたの投稿にコメントしました",
                relatedID: actualPostID,
                toUserID: authorID
            )
            print("✅ コメント通知の作成に成功しました")
            print("   → Cloud Functionsがプッシュ通知を送信します\n")
        } catch {
            print("❌ コメント通知の作成に失敗しました!")
            print("   - エラー: \(error.localizedDescription)")
            print("   - 詳細: \(error)\n")
        }
    }
    
    // コメントに返信を追加（投稿者のみ）
    func addReply(postID: UUID, comment: String, replyToCommentID: String, replyToUserName: String) async throws {
        let currentUserID = UserService.shared.currentUserID
        let currentUserName = UserService.shared.userName
        let commentID = UUID().uuidString
        
        // IDフィールドでクエリ検索（大文字小文字両方対応）
        let lowercaseID = postID.uuidString.lowercased()
        let normalID = postID.uuidString
        
        var snapshot = try await db.collection(collectionName)
            .whereField("id", isEqualTo: lowercaseID)
            .limit(to: 1)
            .getDocuments()
        
        if snapshot.documents.isEmpty {
            snapshot = try await db.collection(collectionName)
                .whereField("id", isEqualTo: normalID)
                .limit(to: 1)
                .getDocuments()
        }
        
        guard let postDoc = snapshot.documents.first,
              postDoc.exists,
              let authorID = postDoc.get("authorID") as? String else {
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "投稿が見つかりません"])
        }
        
        let actualPostID = postDoc.documentID
        
        // 返信先のコメントを確認
        let commentRef = db.collection("postComments").document(replyToCommentID)
        let commentDoc = try await commentRef.getDocument()
        
        guard commentDoc.exists,
              let replyToUserID = commentDoc.get("userID") as? String else {
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "返信先のコメントが見つかりません"])
        }
        
        // 返信可能な条件を確認:
        // 1. 投稿者である場合、または
        // 2. 返信先のコメントが投稿者からのもので、かつその返信先が現在のユーザー宛である場合
        let isAuthor = (authorID == currentUserID)
        let isReplyToAuthor = (replyToUserID == authorID)
        let replyToReplyToUserID = commentDoc.get("replyToUserID") as? String
        let canReplyToAuthorReply = isReplyToAuthor && (replyToReplyToUserID == currentUserID)
        
        guard isAuthor || canReplyToAuthorReply else {
            throw NSError(domain: "FirestoreService", code: 403, userInfo: [NSLocalizedDescriptionKey: "この返信には返信できません"])
        }
        
        // 返信を保存
        let replyData: [String: Any] = [
            "id": commentID,
            "postID": actualPostID,
            "userID": currentUserID,
            "userName": currentUserName,
            "comment": comment,
            "createdAt": Timestamp(date: Date()),
            "replyToCommentID": replyToCommentID,
            "replyToUserName": replyToUserName
        ]
        
        try await db.collection("postComments")
            .document(commentID)
            .setData(replyData)
        
        print("✅ 返信を追加しました: postID=\(actualPostID), commentID=\(commentID), replyTo=\(replyToCommentID)")
        
        // 返信先のユーザーに通知を送る
        do {
            try await createNotification(
                type: .comment,
                title: "返信がありました",
                body: "\(currentUserName)さんがあなたのコメントに返信しました",
                relatedID: actualPostID,
                toUserID: replyToUserID
            )
        } catch {
            print("⚠️ 返信通知の送信に失敗: \(error.localizedDescription)")
        }
    }
    
    // 投稿のコメントを取得
    func fetchComments(postID: UUID) async throws -> [PostComment] {
        var allComments: [PostComment] = []
        
        // 小文字のpostIDでコメントを検索（インデックスエラーを無視）
        do {
            let snapshot = try await db.collection("postComments")
                .whereField("postID", isEqualTo: postID.uuidString.lowercased())
                .order(by: "createdAt", descending: false)
                .getDocuments()
            
            let comments = snapshot.documents.compactMap { doc -> PostComment? in
                guard
                    let id = doc.get("id") as? String,
                    let postID = doc.get("postID") as? String,
                    let userID = doc.get("userID") as? String,
                    let userName = doc.get("userName") as? String,
                    let comment = doc.get("comment") as? String,
                    let timestamp = doc.get("createdAt") as? Timestamp
                else {
                    return nil
                }
                
                // 返信情報を取得（オプショナル）
                let replyToCommentID = doc.get("replyToCommentID") as? String
                let replyToUserName = doc.get("replyToUserName") as? String
                
                return PostComment(
                    id: id,
                    postID: postID,
                    userID: userID,
                    userName: userName,
                    comment: comment,
                    createdAt: timestamp.dateValue(),
                    replyToCommentID: replyToCommentID,
                    replyToUserName: replyToUserName
                )
            }
            allComments.append(contentsOf: comments)
        } catch {
            // インデックスエラーの場合はスキップ
            if !error.localizedDescription.contains("index") {
                throw error
            }
        }
        
        // 大文字混在のpostIDでも検索（インデックスエラーを無視）
        if allComments.isEmpty {
            do {
                let snapshot = try await db.collection("postComments")
                    .whereField("postID", isEqualTo: postID.uuidString)
                    .order(by: "createdAt", descending: false)
                    .getDocuments()
                
                let comments = snapshot.documents.compactMap { doc -> PostComment? in
                    guard
                        let id = doc.get("id") as? String,
                        let postID = doc.get("postID") as? String,
                        let userID = doc.get("userID") as? String,
                        let userName = doc.get("userName") as? String,
                        let comment = doc.get("comment") as? String,
                        let timestamp = doc.get("createdAt") as? Timestamp
                    else {
                        return nil
                    }
                    
                    // 返信情報を取得（オプショナル）
                    let replyToCommentID = doc.get("replyToCommentID") as? String
                    let replyToUserName = doc.get("replyToUserName") as? String
                    
                    return PostComment(
                        id: id,
                        postID: postID,
                        userID: userID,
                        userName: userName,
                        comment: comment,
                        createdAt: timestamp.dateValue(),
                        replyToCommentID: replyToCommentID,
                        replyToUserName: replyToUserName
                    )
                }
                allComments.append(contentsOf: comments)
            } catch {
                // インデックスエラーでない場合のみスロー
                if !error.localizedDescription.contains("index") {
                    throw error
                }
            }
        }
        
        return allComments
    }
    
    // コメントを削除（自分のコメントのみ）
    func deleteComment(commentID: String) async throws {
        let currentUserID = UserService.shared.currentUserID
        let commentRef = db.collection("postComments").document(commentID)
        let commentDoc = try await commentRef.getDocument()
        
        guard commentDoc.exists,
              let userID = commentDoc.get("userID") as? String else {
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "コメントが見つかりません"])
        }
        
        // 自分のコメントのみ削除可能
        if userID != currentUserID {
            throw NSError(domain: "FirestoreService", code: 403, userInfo: [NSLocalizedDescriptionKey: "他人のコメントは削除できません"])
        }
        
        try await commentRef.delete()
        print("✅ コメントを削除しました: commentID=\(commentID)")
    }
    
    // 友達かどうかをチェック（新旧両バージョン対応）
    private func checkIfFriends(userID: String) async throws -> Bool {
        let currentUserID = UserService.shared.currentUserID
        
        // 1. 新バージョン: friendshipsコレクションをチェック
        let userIDs = [currentUserID, userID].sorted()
        let friendshipID = "\(userIDs[0])_\(userIDs[1])"
        
        let friendshipDoc = try await db.collection("friendships")
            .document(friendshipID)
            .getDocument()
        
        if friendshipDoc.exists {
            print("📍 checkIfFriends: 新バージョンのfriendshipsで友達を確認")
            return true
        }
        
        // friendshipsコレクションでの従来の検索方法（userID1/userID2フィールド）
        let friendship1 = try await db.collection("friendships")
            .whereField("userID1", isEqualTo: currentUserID)
            .whereField("userID2", isEqualTo: userID)
            .limit(to: 1)
            .getDocuments()
        
        if !friendship1.documents.isEmpty {
            print("📍 checkIfFriends: friendshipsコレクション（userID1/userID2）で友達を確認")
            return true
        }
        
        let friendship2 = try await db.collection("friendships")
            .whereField("userID1", isEqualTo: userID)
            .whereField("userID2", isEqualTo: currentUserID)
            .limit(to: 1)
            .getDocuments()
        
        if !friendship2.documents.isEmpty {
            print("📍 checkIfFriends: friendshipsコレクション（userID1/userID2 逆）で友達を確認")
            return true
        }
        
        // 2. 旧バージョン: friendRequestsコレクションでacceptedをチェック
        let request1 = try await db.collection("friendRequests")
            .whereField("fromUserID", isEqualTo: currentUserID)
            .whereField("toUserID", isEqualTo: userID)
            .whereField("status", isEqualTo: "accepted")
            .limit(to: 1)
            .getDocuments()
        
        if !request1.documents.isEmpty {
            print("📍 checkIfFriends: 旧バージョンのfriendRequests（accepted）で友達を確認")
            return true
        }
        
        let request2 = try await db.collection("friendRequests")
            .whereField("fromUserID", isEqualTo: userID)
            .whereField("toUserID", isEqualTo: currentUserID)
            .whereField("status", isEqualTo: "accepted")
            .limit(to: 1)
            .getDocuments()
        
        if !request2.documents.isEmpty {
            print("📍 checkIfFriends: 旧バージョンのfriendRequests（accepted 逆）で友達を確認")
            return true
        }
        
        print("📍 checkIfFriends: 友達関係が見つかりませんでした")
        return false
    }
    
    // MARK: - 管理者機能
    
    /// 異常なゲージ値を一括リセット
    func resetAbnormalGauges() async throws -> Int {
        let gaugesSnapshot = try await db.collection(prefectureGaugesCollectionName).getDocuments()
        var resetCount = 0
        
        for doc in gaugesSnapshot.documents {
            let currentValue = doc.get("currentValue") as? Int ?? 0
            let maxValue = doc.get("maxValue") as? Int ?? 100
            
            // currentValueがmaxValueの2倍を超えている場合
            if currentValue > maxValue * 2 {
                try await doc.reference.updateData([
                    "currentValue": 0,
                    "completedDate": NSNull(),
                    "lastUpdated": Timestamp(date: Date())
                ])
                resetCount += 1
                print("✅ 異常ゲージをリセット: \(doc.documentID) (\(currentValue)/\(maxValue) → 0/\(maxValue))")
            }
        }
        
        return resetCount
    }
    
    /// 特定ユーザーに経験値を付与
    func addExperienceToUser(userID: String, amount: Int) async throws {
        // 現在の経験値を取得
        let userDoc = try await db.collection(usersCollectionName).document(userID).getDocument()
        let currentExp = userDoc.get("experiencePoints") as? Int ?? 0
        
        // レベル計算（レベルが上がるほど必要経験値が増える）
        let oldLevel = UserService.calculateLevel(fromExp: currentExp)
        let newExp = currentExp + amount
        let newLevel = UserService.calculateLevel(fromExp: newExp)
        
        // 経験値を更新
        try await db.collection(usersCollectionName).document(userID).setData([
            "experiencePoints": FieldValue.increment(Int64(amount)),
            "experienceUpdatedAt": Timestamp(date: Date())
        ], merge: true)
        
        print("✅ ユーザー \(userID) に経験値 \(amount) を付与しました（\(currentExp) → \(newExp)、レベル \(oldLevel) → \(newLevel)）")
        
        // レベルアップした場合、通知を送信してミッション報酬を付与
        if newLevel > oldLevel {
            let levelDiff = newLevel - oldLevel
            print("🎉 レベルアップ検出: レベル \(oldLevel) → \(newLevel) (+\(levelDiff))")
            
            // レベルアップ通知
            try await createNotification(
                type: .levelUp,
                title: "レベルアップ！",
                body: "レベル\(newLevel)に上がりました！おめでとうございます🎉",
                relatedID: nil,
                toUserID: userID
            )
            
            print("✅ レベルアップ通知を送信しました")
            
            // ミッション報酬を付与（称号、アイコンフレーム、ボーナス経験値など）
            do {
                try await awardLevelRewards(from: oldLevel, to: newLevel, userID: userID)
                print("✅ ミッション報酬を付与しました")
            } catch {
                print("⚠️ ミッション報酬の付与に失敗: \(error.localizedDescription)")
            }
        }
    }

    /// 特定ユーザーに「投稿可能回数」ボーナスを付与（次回プロフィール同期時に反映）
    func grantPostLimitBonusToUser(userID: String, amount: Int) async throws {
        guard amount > 0 else {
            throw NSError(
                domain: "FirestoreService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "付与回数は1以上で指定してください"]
            )
        }

        try await db.collection(usersCollectionName).document(userID).setData([
            "adminPostLimitBonusTotal": FieldValue.increment(Int64(amount)),
            "adminPostLimitBonusUpdatedAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ], merge: true)

        try? await createNotification(
            type: .announcement,
            title: "投稿可能回数が付与されました",
            body: "管理者から本日の投稿可能回数 +\(amount) 回が付与されました。",
            relatedID: nil,
            toUserID: userID
        )

        print("✅ ユーザー \(userID) に投稿可能回数ボーナス +\(amount) を付与しました")
    }
    
    /// ユーザーをBANする
    func banUser(userID: String, reason: String) async throws {
        try await db.collection(usersCollectionName).document(userID).setData([
            "isBanned": true,
            "banReason": reason,
            "bannedAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
        try await banKnownDevices(for: userID, reason: reason)
        
        print("✅ ユーザー \(userID) をBANしました: \(reason)")
    }
    
    /// ユーザーのBAN解除
    func unbanUser(userID: String) async throws {
        try await db.collection(usersCollectionName).document(userID).setData([
            "isBanned": false,
            "banReason": NSNull(),
            "bannedAt": NSNull(),
            "unbannedAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
        try await unbanKnownDevices(for: userID)
        
        print("✅ ユーザー \(userID) のBANを解除しました")
    }
    
    /// カスタム通知を全ユーザーに送信
    func sendCustomNotificationToAllUsers(title: String, body: String) async throws -> Int {
        // 全ユーザーのFCMトークンを取得
        let usersSnapshot = try await db.collection(usersCollectionName).getDocuments()
        var sentCount = 0
        
        for userDoc in usersSnapshot.documents {
            let userID = userDoc.documentID
            
            // 各ユーザーに通知を作成
            try await createNotification(
                type: .announcement,
                title: title,
                body: body,
                relatedID: nil,
                toUserID: userID
            )
            
            sentCount += 1
        }
        
        print("✅ カスタム通知を \(sentCount) 人のユーザーに送信しました")
        return sentCount
    }
    
    /// モヤ浄化カウントを設定（ミッション報酬も自動付与）
    func setMistClearCount(userID: String, count: Int) async throws -> String {
        let docRef = db.collection(userRegistrationsCollectionName).document(userID)
        let document = try await docRef.getDocument()
        let currentCount = document.get("mistClearCount") as? Int ?? 0
        let rewarded = document.get("mistClearRewards") as? [Int] ?? []
        
        // カウントを設定
        try await docRef.setData([
            "mistClearCount": count,
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
        
        print("✅ モヤ浄化カウントを設定: \(currentCount) → \(count)")
        
        // ミッション報酬を付与
        let milestones = [10, 20, 30, 40, 50, 100]
        var awarded: [String] = []
        
        for milestone in milestones where count >= milestone && !rewarded.contains(milestone) {
            let title = "モヤ討伐\(milestone)回達成"
            let frameID = "mist_clear_\(milestone)"
            
            // 称号とフレームを付与
            try await addUserTitle(userID: userID, title: title)
            try await addUserIconFrame(userID: userID, frameID: frameID)
            
            // 報酬を計算
            let expReward = milestone * 5
            
            // 経験値を付与
            try await db.collection(usersCollectionName).document(userID).setData([
                "experiencePoints": FieldValue.increment(Int64(expReward)),
                "experienceUpdatedAt": Timestamp(date: Date())
            ], merge: true)
            
            // 通知を送信
            try await createNotification(
                type: .missionCleared,
                title: "ミッション達成",
                body: "モヤ討伐\(milestone)回達成！経験値+\(expReward)を獲得",
                relatedID: "mist_\(milestone)",
                toUserID: userID
            )
            
            awarded.append("モヤ討伐\(milestone)回")
            print("✅ モヤ討伐\(milestone)回の報酬を付与しました")
        }
        
        // 報酬記録を更新
        let allRewarded = Array(Set(rewarded + milestones.filter { count >= $0 }))
        try await docRef.setData([
            "mistClearRewards": allRewarded
        ], merge: true)
        
        if awarded.isEmpty {
            return "モヤ浄化カウントを\(count)に設定しました（新規報酬なし）"
        } else {
            return "モヤ浄化カウントを\(count)に設定し、報酬を付与しました: \(awarded.joined(separator: ", "))"
        }
    }
    
    /// 感情投稿カウントを設定（ミッション報酬も自動付与）
    func setEmotionPostCount(userID: String, count: Int) async throws -> String {
        let docRef = db.collection(userRegistrationsCollectionName).document(userID)
        let document = try await docRef.getDocument()
        let currentCount = document.get("emotionPostCount") as? Int ?? 0
        let rewarded = document.get("emotionPostRewards") as? [Int] ?? []
        
        // カウントを設定
        try await docRef.setData([
            "emotionPostCount": count,
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
        
        print("✅ 感情投稿カウントを設定: \(currentCount) → \(count)")
        
        // ミッション報酬を付与
        let milestones = [10, 20, 40, 50, 100]
        var awarded: [String] = []
        
        for milestone in milestones where count >= milestone && !rewarded.contains(milestone) {
            let title = "感情投稿\(milestone)回達成"
            let frameID = "post_\(milestone)"
            
            // 称号とフレームを付与
            try await addUserTitle(userID: userID, title: title)
            try await addUserIconFrame(userID: userID, frameID: frameID)
            
            // 報酬を計算
            let expReward = milestone * 5
            
            // 経験値を付与
            try await db.collection(usersCollectionName).document(userID).setData([
                "experiencePoints": FieldValue.increment(Int64(expReward)),
                "experienceUpdatedAt": Timestamp(date: Date())
            ], merge: true)
            
            // 通知を送信
            try await createNotification(
                type: .missionCleared,
                title: "ミッション達成",
                body: "感情投稿\(milestone)回達成！経験値+\(expReward)を獲得",
                relatedID: "post_\(milestone)",
                toUserID: userID
            )
            
            awarded.append("感情投稿\(milestone)回")
            print("✅ 感情投稿\(milestone)回の報酬を付与しました")
        }
        
        // 報酬記録を更新
        let allRewarded = Array(Set(rewarded + milestones.filter { count >= $0 }))
        try await docRef.setData([
            "emotionPostRewards": allRewarded
        ], merge: true)
        
        if awarded.isEmpty {
            return "感情投稿カウントを\(count)に設定しました（新規報酬なし）"
        } else {
            return "感情投稿カウントを\(count)に設定し、報酬を付与しました: \(awarded.joined(separator: ", "))"
        }
    }
    
    /// 特定ユーザーのミッション報酬を強制的に再付与
    func forceAwardMissionRewards(userID: String) async throws -> String {
        // ユーザーの現在の経験値を取得
        let userDoc = try await db.collection(usersCollectionName).document(userID).getDocument()
        let currentExp = userDoc.get("experiencePoints") as? Int ?? 0
        let currentLevel = UserService.calculateLevel(fromExp: currentExp)
        
        // レベル報酬の記録を取得
        let regDoc = try await db.collection(userRegistrationsCollectionName).document(userID).getDocument()
        let rewarded = regDoc.get("levelRewards") as? [Int] ?? []
        
        print("📊 ユーザー \(userID) の状態:")
        print("   - 現在のレベル: \(currentLevel)")
        print("   - 既に受け取った報酬: \(rewarded)")
        
        // レベル10, 20, 40, 50, 100のマイルストーン
        let milestones = [10, 20, 40, 50, 100]
        var awarded: [String] = []
        
        for milestone in milestones where currentLevel >= milestone && !rewarded.contains(milestone) {
            let title = "レベル\(milestone)達成"
            let frameID = "level_\(milestone)"
            
            // 称号とフレームを付与
            try await addUserTitle(userID: userID, title: title)
            try await addUserIconFrame(userID: userID, frameID: frameID)
            
            // 報酬を計算
            let expReward = milestone * 10
            let postBonusReward = max(1, milestone / 20)
            
            // 経験値を付与
            try await db.collection(usersCollectionName).document(userID).setData([
                "experiencePoints": FieldValue.increment(Int64(expReward)),
                "experienceUpdatedAt": Timestamp(date: Date())
            ], merge: true)
            
            // 通知を送信
            try await createNotification(
                type: .missionCleared,
                title: "ミッション達成",
                body: "レベル\(milestone)達成！経験値+\(expReward), 投稿回数+\(postBonusReward)回を獲得",
                relatedID: "level_\(milestone)",
                toUserID: userID
            )
            
            awarded.append("レベル\(milestone)")
            print("✅ レベル\(milestone)の報酬を付与しました")
        }
        
        // 報酬記録を更新
        let allRewarded = Array(Set(rewarded + milestones.filter { currentLevel >= $0 }))
        try await db.collection(userRegistrationsCollectionName).document(userID).setData([
            "levelRewards": allRewarded
        ], merge: true)
        
        if awarded.isEmpty {
            return "付与する報酬がありません（既に全て受け取り済みか、レベルが不足しています）"
        } else {
            return "報酬を付与しました: \(awarded.joined(separator: ", "))"
        }
    }
}

// MARK: - PostComment Model

struct PostComment: Identifiable {
    let id: String
    let postID: String
    let userID: String
    let userName: String
    let comment: String
    let createdAt: Date
    let replyToCommentID: String? // 返信先のコメントID
    let replyToUserName: String? // 返信先のユーザー名
    
    init(id: String = UUID().uuidString,
         postID: String,
         userID: String,
         userName: String,
         comment: String,
         createdAt: Date = Date(),
         replyToCommentID: String? = nil,
         replyToUserName: String? = nil) {
        self.id = id
        self.postID = postID
        self.userID = userID
        self.userName = userName
        self.comment = comment
        self.createdAt = createdAt
        self.replyToCommentID = replyToCommentID
        self.replyToUserName = replyToUserName
    }
}

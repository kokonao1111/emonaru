import Foundation

// 都道府県の列挙型
enum Prefecture: String, CaseIterable, Codable, Identifiable {
    case hokkaido = "北海道"
    case aomori = "青森県"
    case iwate = "岩手県"
    case miyagi = "宮城県"
    case akita = "秋田県"
    case yamagata = "山形県"
    case fukushima = "福島県"
    case ibaraki = "茨城県"
    case tochigi = "栃木県"
    case gunma = "群馬県"
    case saitama = "埼玉県"
    case chiba = "千葉県"
    case tokyo = "東京都"
    case kanagawa = "神奈川県"
    case niigata = "新潟県"
    case toyama = "富山県"
    case ishikawa = "石川県"
    case fukui = "福井県"
    case yamanashi = "山梨県"
    case nagano = "長野県"
    case gifu = "岐阜県"
    case shizuoka = "静岡県"
    case aichi = "愛知県"
    case mie = "三重県"
    case shiga = "滋賀県"
    case kyoto = "京都府"
    case osaka = "大阪府"
    case hyogo = "兵庫県"
    case nara = "奈良県"
    case wakayama = "和歌山県"
    case tottori = "鳥取県"
    case shimane = "島根県"
    case okayama = "岡山県"
    case hiroshima = "広島県"
    case yamaguchi = "山口県"
    case tokushima = "徳島県"
    case kagawa = "香川県"
    case ehime = "愛媛県"
    case kochi = "高知県"
    case fukuoka = "福岡県"
    case saga = "佐賀県"
    case nagasaki = "長崎県"
    case kumamoto = "熊本県"
    case oita = "大分県"
    case miyazaki = "宮崎県"
    case kagoshima = "鹿児島県"
    case okinawa = "沖縄県"
    
    var id: String { rawValue }
    
    // 都道府県の中心座標　大体
    var centerCoordinate: (latitude: Double, longitude: Double) {
        switch self {
        case .hokkaido: return (43.0642, 141.3469)
        case .aomori: return (40.8244, 140.7406)
        case .iwate: return (39.7036, 141.1527)
        case .miyagi: return (38.2682, 140.8694)
        case .akita: return (39.7186, 140.1024)
        case .yamagata: return (38.2404, 140.3633)
        case .fukushima: return (37.7500, 140.4678)
        case .ibaraki: return (36.3414, 140.4467)
        case .tochigi: return (36.5658, 139.8836)
        case .gunma: return (36.3911, 139.0608)
        case .saitama: return (35.8617, 139.6455)
        case .chiba: return (35.6074, 140.1065)
        case .tokyo: return (35.6762, 139.6503)
        case .kanagawa: return (35.4475, 139.6425)
        case .niigata: return (37.9161, 139.0364)
        case .toyama: return (36.6953, 137.2113)
        case .ishikawa: return (36.5947, 136.6256)
        case .fukui: return (36.0652, 136.2216)
        case .yamanashi: return (35.6636, 138.5684)
        case .nagano: return (36.6513, 138.1809)
        case .gifu: return (35.3912, 136.7222)
        case .shizuoka: return (34.9769, 138.3830)
        case .aichi: return (35.1802, 136.9066)
        case .mie: return (34.7303, 136.5086)
        case .shiga: return (35.0045, 135.8686)
        case .kyoto: return (35.0214, 135.7554)
        case .osaka: return (34.6937, 135.5023)
        case .hyogo: return (34.6913, 135.1830)
        case .nara: return (34.6851, 135.8048)
        case .wakayama: return (34.2261, 135.1675)
        case .tottori: return (35.5039, 134.2377)
        case .shimane: return (35.4723, 133.0505)
        case .okayama: return (34.6617, 133.9350)
        case .hiroshima: return (34.3960, 132.4596)
        case .yamaguchi: return (34.1858, 131.4705)
        case .tokushima: return (34.0658, 134.5593)
        case .kagawa: return (34.3401, 134.0433)
        case .ehime: return (33.8416, 132.7657)
        case .kochi: return (33.5597, 133.5310)
        case .fukuoka: return (33.5904, 130.4017)
        case .saga: return (33.2494, 130.2988)
        case .nagasaki: return (32.7448, 129.8737)
        case .kumamoto: return (32.7898, 130.7416)
        case .oita: return (33.2381, 131.6126)
        case .miyazaki: return (31.9077, 131.4202)
        case .kagoshima: return (31.5965, 130.5571)
        case .okinawa: return (26.2124, 127.6809)
        }
    }
}

// 都道府県の感情ゲージ
struct PrefectureGauge: Identifiable, Codable {
    let id: String // 都道府県名
    var currentValue: Int // 現在のゲージ値
    let maxValue: Int // 最大ゲージ値（満タンのとこ）
    var lastUpdated: Date // 最終更新日時
    var completedDate: Date? // ゲージ満タン達成日
    var completedCount: Int // ゲージ満タン達成回数
    
    init(
        prefecture: Prefecture,
        currentValue: Int = 0,
        maxValue: Int = 100,
        lastUpdated: Date = Date(),
        completedDate: Date? = nil,
        completedCount: Int = 0
    ) {
        self.id = prefecture.rawValue
        self.currentValue = currentValue
        self.maxValue = maxValue
        self.lastUpdated = lastUpdated
        self.completedDate = completedDate
        self.completedCount = completedCount
    }
    
    var progress: Double {
        min(Double(currentValue) / Double(maxValue), 1.0)
    }
    
    var isCompleted: Bool {
        currentValue >= maxValue
    }
}

// ユーザーの都道府県登録情報
struct UserPrefectureRegistration: Codable {
    let prefecture: String
    let registeredAt: Date
    var stars: Int // 獲得した星の数
    var titles: [String] // 獲得した称号のリスト
    var baseGaugeValue: Int // 登録時点の共有ゲージ値（基準値）
    var maxGaugeValue: Int // 最大ゲージ値
    var completedCount: Int // 完了回数
    var lastCompletedAt: Date? // 最後に完了した日時
}

// 報酬タイプ
enum RewardType: String, Codable {
    case star = "星"
    case title = "称号"
}

// 報酬情報
struct Reward: Codable {
    let type: RewardType
    let value: String // 星の数または称号名
    let prefecture: String
    let earnedAt: Date
}

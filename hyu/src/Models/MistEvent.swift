import Foundation
import CoreLocation

// モヤイベント
struct MistEvent: Identifiable, Codable, Equatable {
    let id: String
    let centerLatitude: Double
    let centerLongitude: Double
    let prefectureName: String
    let radius: Double // モヤの半径（km）
    var currentHP: Int // 現在のHP（正の感情で減る）
    let maxHP: Int // 最大HP
    var happyPostCount: Int // 嬉しい投稿の回数（5回で消える）
    let createdAt: Date
    var lastUpdated: Date
    var isActive: Bool // イベントがアクティブかどうか
    var contributorIDs: [String] // モヤに投稿したユーザー
    
    init(id: String = UUID().uuidString,
         centerLatitude: Double,
         centerLongitude: Double,
         prefectureName: String = "不明",
         radius: Double = 3.0, // デフォルト3km
         currentHP: Int = 100,
         maxHP: Int = 100,
         happyPostCount: Int = 0,
         createdAt: Date = Date(),
         lastUpdated: Date = Date(),
         isActive: Bool = true,
         contributorIDs: [String] = []) {
        self.id = id
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.prefectureName = prefectureName
        self.radius = radius
        self.currentHP = currentHP
        self.maxHP = maxHP
        self.happyPostCount = happyPostCount
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
        self.isActive = isActive
        self.contributorIDs = contributorIDs
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
    }
    
    var progress: Double {
        Double(maxHP - currentHP) / Double(maxHP)
    }
    
    var isCleared: Bool {
        currentHP <= 0 || happyPostCount >= 5
    }

    /// 時間経過で拡大した現在のモヤ半径（km）
    func expandedRadius(at date: Date = Date(), growthPerMinuteKm: Double = 0.1) -> Double {
        let elapsed = max(0, date.timeIntervalSince(createdAt))
        let growth = (elapsed / 60.0) * growthPerMinuteKm
        return max(radius, radius + growth)
    }

    /// HPを反映した現在のモヤ半径（km）
    /// - 時間経過での拡大は維持
    /// - HPが減るほど小さくなる
    func activeRadius(
        at date: Date = Date(),
        growthPerMinuteKm: Double = 0.1
    ) -> Double {
        let grown = expandedRadius(at: date, growthPerMinuteKm: growthPerMinuteKm)
        let hpRatio: Double
        if maxHP > 0 {
            hpRatio = max(0.0, min(1.0, Double(currentHP) / Double(maxHP)))
        } else {
            hpRatio = 0.0
        }
        // 低HPでも極端に小さくなりすぎないよう最小値を確保
        return max(radius * 0.25, grown * hpRatio)
    }

    /// 現在の拡大後モヤ範囲内かどうか
    func containsInExpandedArea(
        latitude: Double,
        longitude: Double,
        at date: Date = Date(),
        growthPerMinuteKm: Double = 0.1
    ) -> Bool {
        let distance = calculateDistance(
            lat1: centerLatitude, lon1: centerLongitude,
            lat2: latitude, lon2: longitude
        )
        return distance <= activeRadius(at: date, growthPerMinuteKm: growthPerMinuteKm)
    }
    
    // 指定された座標がモヤの範囲内かどうか
    func contains(latitude: Double, longitude: Double) -> Bool {
        let distance = calculateDistance(
            lat1: centerLatitude, lon1: centerLongitude,
            lat2: latitude, lon2: longitude
        )
        return distance <= radius
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
}

// スポット（特定の位置で投稿するとボーナスがもらえる）
struct Spot: Identifiable, Codable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let radius: Double // スポットの有効範囲（メートル）
    let isActive: Bool // アクティブかどうか
    
    init(id: String = UUID().uuidString,
         name: String,
         latitude: Double,
         longitude: Double,
         radius: Double = 50.0, // デフォルト50メートル
         isActive: Bool = true) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.isActive = isActive
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    // 指定された座標がスポットの範囲内かどうか
    func contains(latitude: Double, longitude: Double) -> Bool {
        let distance = calculateDistance(
            lat1: self.latitude, lon1: self.longitude,
            lat2: latitude, lon2: longitude
        )
        return distance <= (radius / 1000.0) // メートルをキロメートルに変換
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
}

import Foundation
import FirebaseFirestore
import Darwin

final class FirestoreService {
    private let db = Firestore.firestore()
    private let collectionName = "emotions"

    func postEmotion(level: EmotionLevel, visualType: EmotionVisualType, latitude: Double? = nil, longitude: Double? = nil) async throws {
        let id = UUID()
        var data: [String: Any] = [
            "id": id.uuidString,
            "level": level.rawValue,
            "visualType": visualType.rawValue,
            "createdAt": Timestamp(date: Date())
        ]
        
        if let latitude = latitude, let longitude = longitude {
            data["latitude"] = latitude
            data["longitude"] = longitude
        }

        try await db.collection(collectionName)
            .document(id.uuidString)
            .setData(data)
    }

    func fetchRecentEmotions(lastHours: Int = 6) async throws -> [EmotionPost] {
        let since = Date().addingTimeInterval(-Double(lastHours) * 60 * 60)
        let snapshot = try await db.collection(collectionName)
            .whereField("createdAt", isGreaterThanOrEqualTo: Timestamp(date: since))
            .order(by: "createdAt", descending: true)
            .getDocuments()

        let visibilityCutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return snapshot.documents.compactMap { doc in
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

            let level = EmotionLevel.clamped(levelValue)
            guard let visualType = EmotionVisualType(rawValue: visualRaw) else { return nil }
            
            let latitude = doc.get("latitude") as? Double
            let longitude = doc.get("longitude") as? Double

            return EmotionPost(id: id, level: level, visualType: visualType, createdAt: createdAt, latitude: latitude, longitude: longitude)
        }
    }
    
    func fetchEmotionsInRegion(centerLatitude: Double, centerLongitude: Double, radiusKm: Double = 10.0) async throws -> [EmotionPost] {
        // 簡易的な範囲検索（実際の実装ではGeoFirestoreなどを使うとより正確）
        // ここでは全件取得してフィルタリング（小規模なデータ向け）
        let allPosts = try await fetchRecentEmotions(lastHours: 24)
        
        return allPosts.filter { post in
            guard let lat = post.latitude, let lon = post.longitude else { return false }
            
            let distance = calculateDistance(
                lat1: centerLatitude, lon1: centerLongitude,
                lat2: lat, lon2: lon
            )
            
            return distance <= radiusKm
        }
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

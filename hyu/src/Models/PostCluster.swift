import Foundation
import CoreLocation
import MapKit

// 投稿のクラスター（複数の投稿をまとめたもの）
struct PostCluster: Identifiable {
    let id = UUID()
    let posts: [EmotionPost]
    let centerCoordinate: CLLocationCoordinate2D
    
    var postCount: Int {
        posts.count
    }
    
    // クラスターの平均感情レベル
    var averageLevel: Double {
        let sum = posts.reduce(0) { $0 + Double($1.level.rawValue) }
        return sum / Double(posts.count)
    }
    
    // クラスターの色（平均感情レベルに基づく）
    var clusterColor: String {
        if averageLevel > 2 {
            return "green"
        } else if averageLevel > 0 {
            return "yellow"
        } else if averageLevel > -2 {
            return "orange"
        } else {
            return "red"
        }
    }
}

// クラスタリングアルゴリズム
class PostClusterManager {
    // 投稿をクラスタリング（距離ベース）
    // minClusterSize: クラスター化する最小投稿数（これ未満は個別表示）
    static func clusterPosts(_ posts: [EmotionPost], currentSpan: Double, minClusterSize: Int = 10) -> [PostCluster] {
        // ビル1軒分くらいの距離（約30m = 0.03km）
        // ズームレベルに応じて調整：ズームアウト時はもっと広い範囲でクラスター化
        let baseDistance = 0.03 // km（30m）
        let maxDistance = 0.3 // km（300m）
        let clusteringDistance = min(maxDistance, max(baseDistance, currentSpan * 5))
        
        var clusters: [PostCluster] = []
        var processedPosts: Set<UUID> = []
        
        for post in posts {
            guard let lat = post.latitude, let lon = post.longitude else { continue }
            guard !processedPosts.contains(post.id) else { continue }
            
            let postCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            
            // この投稿の近くにある他の投稿を探す
            var nearbyPosts: [EmotionPost] = [post]
            processedPosts.insert(post.id)
            
            for otherPost in posts {
                guard let otherLat = otherPost.latitude, let otherLon = otherPost.longitude else { continue }
                guard !processedPosts.contains(otherPost.id) else { continue }
                
                let otherCoord = CLLocationCoordinate2D(latitude: otherLat, longitude: otherLon)
                let distance = calculateDistance(from: postCoord, to: otherCoord)
                
                // クラスタリング距離以内なら同じクラスターに追加
                if distance <= clusteringDistance {
                    nearbyPosts.append(otherPost)
                    processedPosts.insert(otherPost.id)
                }
            }
            
            // minClusterSize個以上の投稿がある場合のみクラスター化
            // それ未満は後で個別表示される
            if nearbyPosts.count >= minClusterSize {
                // 中心座標を計算（平均位置）
                let avgLat = nearbyPosts.compactMap { $0.latitude }.reduce(0, +) / Double(nearbyPosts.count)
                let avgLon = nearbyPosts.compactMap { $0.longitude }.reduce(0, +) / Double(nearbyPosts.count)
                let centerCoord = CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
                
                let cluster = PostCluster(posts: nearbyPosts, centerCoordinate: centerCoord)
                clusters.append(cluster)
            } else {
                // minClusterSize未満なので、処理済みフラグを戻して個別表示させる
                for post in nearbyPosts {
                    processedPosts.remove(post.id)
                }
            }
        }
        
        return clusters
    }
    
    // 2点間の距離を計算（km）
    private static func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation) / 1000.0 // メートルをkmに変換
    }
}

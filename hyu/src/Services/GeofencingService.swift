import Foundation
import CoreLocation
import UserNotifications
import FirebaseFirestore

final class GeofencingService: NSObject, CLLocationManagerDelegate {
    static let shared = GeofencingService()
    
    private let locationManager = CLLocationManager()
    private let firestoreService = FirestoreService()
    
    // Firestoreから取得した全スポットのキャッシュ
    private var allSpots: [Spot] = []
    
    // 現在監視中のスポット（最大20個）
    private var monitoredSpotIDs: Set<String> = []
    
    // 最後に位置情報を更新した場所（距離が一定以上変わったら再計算）
    private var lastUpdateLocation: CLLocation?
    private let updateThresholdKm: Double = 10.0 // 10km移動したら再計算
    
    override private init() {
        super.init()
        setupLocationManager()
        
        // Firestoreからスポット情報を取得
        Task {
            await loadSpotsFromFirestore()
        }
    }
    
    // 位置情報マネージャーのセットアップ
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer // バッテリー節約のため精度を下げる
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.distanceFilter = 1000 // 1km移動するごとに更新
    }
    
    // Firestoreからスポット情報を読み込み
    private func loadSpotsFromFirestore() async {
        do {
            allSpots = try await firestoreService.fetchAllSpots()
            print("✅ スポット情報を読み込みました: \(allSpots.count)件")
        } catch {
            print("❌ スポット情報の読み込みに失敗: \(error.localizedDescription)")
        }
    }
    
    // 位置情報の許可をリクエスト
    func requestAuthorization() {
        locationManager.requestAlwaysAuthorization()
        print("📍 位置情報の許可をリクエストしました（Always）")
    }
    
    // ジオフェンスを開始
    func startMonitoring() {
        // 位置情報の更新を開始
        locationManager.startUpdatingLocation()
        print("📍 位置情報の更新を開始しました")
    }
    
    // 現在地に近いスポットを監視
    private func updateMonitoringForCurrentLocation(_ location: CLLocation) {
        // スポットが読み込まれていない場合は何もしない
        guard !allSpots.isEmpty else {
            print("⚠️ スポット情報がまだ読み込まれていません")
            return
        }
        
        // 最後の更新から距離が閾値未満なら何もしない
        if let lastLocation = lastUpdateLocation {
            let distance = location.distance(from: lastLocation) / 1000.0 // km
            if distance < updateThresholdKm {
                return
            }
        }
        
        print("📍 現在地: 緯度\(location.coordinate.latitude), 経度\(location.coordinate.longitude)")
        
        // 現在地からの距離でスポットをソート
        let sortedSpots = allSpots.map { spot -> (spot: Spot, distance: Double) in
            let spotLocation = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
            let distance = location.distance(from: spotLocation)
            return (spot, distance)
        }.sorted { $0.distance < $1.distance }
        
        // 近い順に最大20個を選択
        let maxMonitoredRegions = 20
        let nearbySpots = Array(sortedSpots.prefix(maxMonitoredRegions))
        
        // 新しい監視対象のIDセット
        let newMonitoredIDs = Set(nearbySpots.map { $0.spot.id })
        
        // 変更がない場合は何もしない
        if newMonitoredIDs == monitoredSpotIDs {
            return
        }
        
        print("🔄 監視スポットを更新します...")
        
        // 既存の監視を全て停止
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        
        // 新しいスポットを監視
        for (spot, distance) in nearbySpots {
            let center = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
            let region = CLCircularRegion(
                center: center,
                radius: max(spot.radius, 100), // 最小100m
                identifier: spot.id
            )
            
            region.notifyOnEntry = true  // 入った時に通知
            region.notifyOnExit = false  // 出た時は通知しない
            
            locationManager.startMonitoring(for: region)
            
            let distanceKm = distance / 1000.0
            print("📍 監視中: \(spot.name)（距離: \(String(format: "%.1f", distanceKm))km, 半径: \(Int(spot.radius))m）")
        }
        
        // 監視対象を更新
        monitoredSpotIDs = newMonitoredIDs
        lastUpdateLocation = location
        
        print("✅ \(nearbySpots.count)個の近隣スポットを監視中")
    }
    
    // ジオフェンスを停止
    func stopMonitoring() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        print("🛑 ジオフェンス監視を停止しました")
    }
    
    // MARK: - CLLocationManagerDelegate
    
    // 位置情報の許可状態が変更された
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            print("✅ 位置情報の許可: Always（バックグラウンドでも取得可能）")
            startMonitoring()
        case .authorizedWhenInUse:
            print("⚠️ 位置情報の許可: WhenInUse（アプリ使用中のみ）")
            print("💡 ヒント: 設定でAlwaysに変更すると、バックグラウンドでも動作します")
        case .denied:
            print("❌ 位置情報の許可が拒否されました")
        case .notDetermined:
            print("⚠️ 位置情報の許可がまだ決定されていません")
        case .restricted:
            print("❌ 位置情報の使用が制限されています")
        @unknown default:
            print("⚠️ 不明な許可状態")
        }
    }
    
    // 位置情報が更新された
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // 近隣スポットの監視を更新
        updateMonitoringForCurrentLocation(location)
    }
    
    // ジオフェンスに入った
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        
        let spotID = region.identifier
        
        // スポット情報を取得
        guard let spot = allSpots.first(where: { $0.id == spotID }) else {
            print("⚠️ スポット情報が見つかりません: \(spotID)")
            return
        }
        
        print("📍 観光スポットに到着: \(spot.name)")
        
        // 通知を送信
        Task { @MainActor in
            await sendSpotNotification(spot: spot)
        }
        
        // 経験値と投稿回数ボーナスを付与
        Task {
            await grantSpotBonus(spot: spot, coordinate: circularRegion.center)
        }
    }
    
    // ジオフェンスから出た
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("📍 観光スポットから離れました: \(region.identifier)")
    }
    
    // 監視エラー
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        if let region = region {
            print("❌ ジオフェンス監視エラー（\(region.identifier)）: \(error.localizedDescription)")
        } else {
            print("❌ ジオフェンス監視エラー: \(error.localizedDescription)")
        }
    }
    
    // 観光スポット到着通知を送信
    @MainActor
    private func sendSpotNotification(spot: Spot) async {
        let content = UNMutableNotificationContent()
        content.title = "🎉 観光スポットに到着！"
        content.body = "\(spot.name)に到着しました！\n経験値+20、投稿回数+3をゲット！"
        content.sound = .default
        content.badge = 1
        content.userInfo = [
            "type": "spot_arrival",
            "spotID": spot.id,
            "spotName": spot.name
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "spot_arrival_\(spot.id)",
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("✅ 観光スポット到着通知を送信: \(spot.name)")
        } catch {
            print("❌ 観光スポット通知の送信に失敗: \(error.localizedDescription)")
        }
    }
    
    // スポット到着ボーナスを付与
    private func grantSpotBonus(spot: Spot, coordinate: CLLocationCoordinate2D) async {
        let visitKey = "lastVisit_\(spot.id)"
        let now = Date()
        
        // 最後に訪問した時刻を確認（1日1回のみボーナス）
        if let lastVisit = UserDefaults.standard.object(forKey: visitKey) as? Date {
            let hoursSinceLastVisit = now.timeIntervalSince(lastVisit) / 3600
            if hoursSinceLastVisit < 24 {
                print("⏰ \(spot.name)のボーナスは24時間に1回のみです（残り\(Int(24 - hoursSinceLastVisit))時間）")
                return
            }
        }
        
        // ボーナスを付与
        await MainActor.run {
            // 経験値 +20
            UserService.shared.addExperience(points: 20)
            
            // 投稿回数 +3
            UserService.shared.addPostCountBonus(count: 3)
        }
        
        // 訪問時刻を記録
        UserDefaults.standard.set(now, forKey: visitKey)
        
        print("✅ スポットボーナスを付与: \(spot.name)（経験値+20、投稿回数+3）")
    }
}

import Foundation
import CoreLocation
import Combine

// ============================================
// LocationService: 位置情報管理
// ============================================
// このファイルの役割：
// - スマホのGPS位置情報を取得
// - 位置情報の権限をリクエスト
// - 座標から都道府県名を取得（逆ジオコーディング）
// - 位置が変わったら自動で画面を更新
// ============================================

@MainActor  // UI更新用のメインスレッドで動作
final class LocationService: NSObject, ObservableObject {
    // iOSの位置情報管理システム
    private let locationManager = CLLocationManager()
    
    // 画面に自動反映される変数（@Publishedは値が変わると画面が更新される）
    @Published var currentLocation: CLLocation?  // 現在位置
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined  // 権限状態
    @Published var errorMessage: String?  // エラーメッセージ
    
    override init() {
        super.init()
        locationManager.delegate = self  // 位置情報の変更を受け取る
        locationManager.desiredAccuracy = kCLLocationAccuracyBest  // 最高精度で取得
    }
    
    // ============================================
    // 位置情報の権限をリクエスト
    // ============================================
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()  // 「アプリ使用中のみ」の権限
    }
    
    // ============================================
    // 位置情報の更新を開始（継続的に位置を取得）
    // ============================================
    func startUpdatingLocation() {
        // 権限がなければ先にリクエスト
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }
        locationManager.startUpdatingLocation()
    }
    
    // ============================================
    // 位置情報の更新を停止（バッテリー節約）
    // ============================================
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
    
    // ============================================
    // 現在位置を取得（1回だけ）
    // ============================================
    func getCurrentLocation() async -> CLLocation? {
        // 権限がなければリクエスト
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            return nil
        }
        
        // 既に取得済みならそれを返す
        if let location = currentLocation {
            return location
        }
        
        // 位置情報の取得を開始
        locationManager.startUpdatingLocation()
        
        // 位置情報が取得できるまで最大5秒待つ
        for _ in 0..<50 {
            if let location = currentLocation {
                locationManager.stopUpdatingLocation()
                return location
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒待つ
        }
        
        // 5秒経っても取得できなかったら諦める
        locationManager.stopUpdatingLocation()
        return currentLocation
    }
    
    // ============================================
    // 座標から都道府県を取得（逆ジオコーディング）
    // ============================================
    // 例：(35.6812, 139.7671) → 「東京都」
    func getPrefectureFromCoordinate(latitude: Double, longitude: Double) async -> String? {
        let geocoder = CLGeocoder()  // 座標↔住所の変換ツール
        let location = CLLocation(latitude: latitude, longitude: longitude)
        
        do {
            // Appleのサーバーに問い合わせ（待つ処理）
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else {
                print("❌ 逆ジオコーディング: プレースマークが見つかりませんでした")
                return nil
            }
            
            // administrativeAreaが都道府県名
            if let prefecture = placemark.administrativeArea {
                print("✅ 逆ジオコーディング成功: \(prefecture)")
                return prefecture
            } else {
                print("❌ 逆ジオコーディング: administrativeAreaが取得できませんでした")
                return nil
            }
        } catch {
            print("❌ 逆ジオコーディングエラー: \(error.localizedDescription)")
            return nil
        }
    }
}

// ============================================
// CLLocationManagerDelegateの実装
// ============================================
// iOSから位置情報の変更を受け取るための処理
extension LocationService: CLLocationManagerDelegate {
    // 位置情報が更新された時に自動で呼ばれる
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let location = locations.last {
                self.currentLocation = location  // 最新の位置を保存
            }
        }
    }
    
    // 位置情報の取得に失敗した時に自動で呼ばれる
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = "位置情報の取得に失敗しました: \(error.localizedDescription)"
        }
    }
    
    // 位置情報の権限が変更された時に自動で呼ばれる
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus  // 権限状態を更新
        }
    }
}

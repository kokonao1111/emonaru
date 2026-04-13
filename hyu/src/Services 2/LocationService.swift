import Foundation
import CoreLocation

@MainActor
final class LocationService: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startUpdatingLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }
        locationManager.startUpdatingLocation()
    }
    
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
    
    func getCurrentLocation() async -> CLLocation? {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            return nil
        }
        
        if let location = currentLocation {
            return location
        }
        
        locationManager.startUpdatingLocation()
        
        // 位置情報が取得できるまで待つ（最大5秒）
        for _ in 0..<50 {
            if let location = currentLocation {
                locationManager.stopUpdatingLocation()
                return location
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒待つ
        }
        
        locationManager.stopUpdatingLocation()
        return currentLocation
    }
    
    // 座標から都道府県を正確に取得（逆ジオコーディングを使用）
    func getPrefectureFromCoordinate(latitude: Double, longitude: Double) async -> String? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: latitude, longitude: longitude)
        
        do {
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

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let location = locations.last {
                self.currentLocation = location
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = "位置情報の取得に失敗しました: \(error.localizedDescription)"
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
        }
    }
}

# Skip Migration Inventory

## Scope
- Project: `hyu`
- Goal: isolate iOS-only APIs from business logic before Skip migration

## iOS-only entrypoints
- `hyu/hyu/hyuApp.swift`
  - `@UIApplicationDelegateAdaptor`
  - `UIApplication.shared.registerForRemoteNotifications()`
  - `UNUserNotificationCenter.current()`
  - `FirebaseMessaging` delegate hooks

## Platform-coupled views
- `src/Views/EmotionMapView.swift`
  - `MapKit`, `MKCoordinateRegion`, camera callbacks
- `src/Views/PrefectureGameMapView.swift`
  - `MapKit`
- `src/Views/MainTabView.swift`
  - `UIApplication.didBecomeActiveNotification`
- `src/Views/NotificationsView.swift`
  - `UNUserNotificationCenter`, `UIApplication` badge handling
- `src/Views/SettingsView.swift`
  - `UNUserNotificationCenter`, app settings deep-link (`UIApplication.openSettingsURLString`)

## Platform-coupled services
- `src/Services/LocationService.swift`
  - `CLLocationManager` delegate lifecycle
- `src/Services/NotificationService.swift`
  - `UNUserNotificationCenter` request/schedule/remove
- `src/Services/NotificationDelegate.swift`
  - `UNUserNotificationCenterDelegate`
- `src/Services/BackgroundTaskService.swift`
  - iOS background tasks + local notifications
- `src/Services/GeofencingService.swift`
  - `CLLocationManagerDelegate` + notification delivery
- `src/Services/FirestoreService.swift`
  - `UIKit` import only (image conversion/upload logic)

## Utility/model files coupled to UIKit/MapKit
- `src/Models/PostCluster.swift` (`MapKit`)
- `src/Services/QRCodeService.swift` (`UIKit`)
- `src/Models/QRCodeService.swift` (`UIKit`)
- `src/Views/ProfileShareView.swift` (`UIKit`)
- `src/Models/ProfileShareView.swift` (`UIKit`)

## Migration boundaries to introduce
1. `CoreDomain`: entities/value-objects/pure logic only
2. `CoreUseCases`: auth/post/mist/profile/timeline orchestration
3. `CorePorts`: repository + platform ports
4. `IOSAdapters`: wraps current services/UI APIs
5. `AndroidAdapters`: Skip/Android implementations

## First extraction candidates (pure logic)
- `EmotionLevel` helpers and level labels from `src/Models/EmotionPost.swift`
- `UserService` level math (`totalExpForLevel`, `calculateLevel`, `expForNextLevel`)
- `PostClusterManager` distance clustering algorithm (move MapKit out)
- Mist HP progression arithmetic from `src/Services/FirestoreService.swift`

//
//  hyuApp.swift
//  hyu
//
//  Created by 小林直寛 on 2026/01/25.
//

import SwiftUI
import FirebaseCore
import UserNotifications
import UIKit
import FirebaseMessaging
import BackgroundTasks

// ============================================
// hyuApp: アプリのスタート地点
// ============================================
// このファイルの役割：
// - アプリが起動した時に最初に実行される
// - Firebaseの初期化
// - 通知の設定
// - QRコードのディープリンク処理
// - ログイン画面とメイン画面の切り替え
// ============================================

@main  // アプリのエントリーポイント（ここから全てが始まる）
struct hyuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate  // iOS標準の機能を使う
    @StateObject private var authService = LocalAuthService.shared  // ログイン管理
    @State private var scannedUserID: String?  // QRコードでスキャンしたユーザーID
    @State private var showScannedUserProfile = false  // スキャンしたユーザーのプロフィールを表示するか

    // ============================================
    // アプリ起動時の初期設定（1回だけ実行される）
    // ============================================
    init() {
        // Firebaseを起動（これがないとデータベースが使えない）
        FirebaseApp.configure()
        
        // 通知の設定（アプリが開いている時も通知を表示）
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        
        // バックグラウンドタスクの登録（アプリが閉じている時の処理）
        BackgroundTaskService.shared.registerBackgroundTasks()
        
        // 通知の許可をリクエスト（バックグラウンドで実行）
        Task {
            // ステップ1: ユーザーに通知の許可を求める
            await NotificationService.shared.requestAuthorization()
            
            // ステップ2: 許可が得られたらリモート通知を登録
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .authorized {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                print("✅ リモート通知の登録を開始しました")
            } else {
                print("⚠️ 通知が許可されていないため、リモート通知を登録できません")
            }
            
            // ステップ3: 毎日の感情リマインダーをスケジュール（午前・午後にランダム）
            NotificationService.shared.scheduleDailyEmotionReminder()
        }

        // Firebaseから経験値を同期（サーバーとスマホの値を合わせる）
        Task {
            await UserService.shared.syncExperienceFromFirestore()
        }

        // 初期観光スポットをFirebaseに登録（初回のみ）
        Task {
            // スポットバージョンをリセット（新しいスポット追加のため）
            UserDefaults.standard.removeObject(forKey: "com.nao.hyu.seededSpotsVersion.v6")
            print("🔄 スポットバージョンをリセットしました")
            
            await FirestoreService().seedInitialSpotsIfNeeded()
        }
        
        // 友達申請の監視を開始（新しい申請が来たら通知）
        FriendRequestNotificationService.shared.startMonitoring()
        
        // ジオフェンシング（観光スポットに近づいたら通知）を開始
        GeofencingService.shared.requestAuthorization()
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if authService.isLoggedIn {
                        MainTabView()
                    } else {
                        UserAuthView(authService: authService, allowDismiss: false)
                    }
                }
                .environment(\.dynamicTypeSize, UIDevice.current.userInterfaceIdiom == .pad ? .xxxLarge : .large)
            }
            .onOpenURL { url in
                handleURL(url)
            }
            .onChange(of: showScannedUserProfile) { oldValue, newValue in
                print("🟡 showScannedUserProfile変更: \(oldValue) → \(newValue)")
            }
            .onChange(of: scannedUserID) { oldValue, newValue in
                print("🟡 scannedUserID変更: \(oldValue ?? "nil") → \(newValue ?? "nil")")
            }
            .sheet(isPresented: $showScannedUserProfile) {
                if let userID = scannedUserID {
                    NavigationView {
                        UserProfileView(userID: userID)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button("閉じる") {
                                        print("🔴 閉じるボタンがタップされました")
                                        showScannedUserProfile = false
                                    }
                                }
                            }
                    }
                    .onAppear {
                        print("🟢 Sheet表示開始: userID = \(userID)")
                    }
                } else {
                    Text("エラー: ユーザーIDが見つかりません")
                        .onAppear {
                            print("⚠️ Sheet表示されたがuserIDがnil")
                        }
                }
            }
        }
    }
    
    private func handleURL(_ url: URL) {
        print("📱 URLを受信: \(url.absoluteString)")
        print("   - scheme: \(url.scheme ?? "nil")")
        print("   - host: \(url.host ?? "nil")")
        print("   - path: \(url.path)")
        print("   - pathComponents: \(url.pathComponents)")
        
        // QRコードのURL形式: emotionapp://user/{userID}
        guard url.scheme == "emotionapp" else {
            print("❌ 無効なスキーム: \(url.scheme ?? "nil")")
            return
        }
        
        guard url.host == "user" else {
            print("❌ 無効なホスト: \(url.host ?? "nil")")
            return
        }
        
        // pathComponents から userID を取得（"/" を除く）
        let components = url.pathComponents.filter { $0 != "/" }
        guard let userID = components.first, !userID.isEmpty else {
            print("❌ ユーザーIDが見つかりません: pathComponents = \(url.pathComponents)")
            return
        }
        
        print("✅ ユーザーIDを抽出: \(userID)")
        
        // ログイン済みの場合のみプロフィールを表示
        if authService.isLoggedIn {
            print("✅ ログイン済み - プロフィールを表示します")
            // UIの準備を待ってから表示
            Task { @MainActor in
                // 少し遅延を入れる
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                print("🔵 userIDを設定: \(userID)")
                self.scannedUserID = userID
                print("🔵 showScannedUserProfileをtrueに設定")
                self.showScannedUserProfile = true
                print("🔵 showScannedUserProfile = \(self.showScannedUserProfile)")
            }
        } else {
            print("⚠️ ログインが必要です")
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Messaging.messaging().delegate = self
        
        // バックグラウンド更新を最小化間隔で許可
        application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
        
        // iPadの場合、UIを大きく表示
        if UIDevice.current.userInterfaceIdiom == .pad {
            // iPadでのフォントサイズを大きく設定
            UIApplication.shared.windows.first?.overrideUserInterfaceStyle = .unspecified
        }
        
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        print("✅ APNsデバイストークンを登録しました")
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ リモート通知の登録に失敗しました: \(error.localizedDescription)")
        // リトライを試みる
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            application.registerForRemoteNotifications()
            print("🔄 リモート通知の登録を再試行しています...")
        }
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { 
            print("⚠️ FCMトークンが取得できませんでした")
            return 
        }
        
        // 以前のトークンと比較
        let previousToken = UserDefaults.standard.string(forKey: "previousFCMToken")
        if previousToken == token {
            print("ℹ️ FCMトークンは変更されていません")
            print("🔄 念のため、Firestoreへの保存を確認します...")
            // トークンが変更されていなくても、Firestoreに保存されているか確認
        } else {
            print("🔔 新しいFCMトークンを取得: \(token)")
        }
        
        // トークンを保存（変更されていなくても保存を試みる）
        UserDefaults.standard.set(token, forKey: "previousFCMToken")
        
        Task {
            do {
                await FirestoreService().updateUserFCMToken(token: token)
                print("✅ FCMトークンをFirestoreに保存しました")
            } catch {
                print("❌ FCMトークンの保存に失敗: \(error.localizedDescription)")
                // 失敗した場合は再試行
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3秒待機
                await FirestoreService().updateUserFCMToken(token: token)
            }
        }
    }
    
    // サイレントプッシュ通知を受信
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("📨 リモート通知を受信（バックグラウンド）")
        
        // サイレントプッシュの場合、バックグラウンドでデータを更新
        Task {
            do {
                // Firestoreから最新データを取得
                await UserService.shared.syncExperienceFromFirestore()
                
                print("✅ バックグラウンドでデータを更新しました")
                completionHandler(.newData)
            } catch {
                print("❌ バックグラウンド更新に失敗: \(error.localizedDescription)")
                completionHandler(.failed)
            }
        }
    }
    
    // アプリがバックグラウンドに移行
    func applicationDidEnterBackground(_ application: UIApplication) {
        // バックグラウンド更新をスケジュール
        BackgroundTaskService.shared.scheduleAppRefresh()
        print("🔄 バックグラウンド更新をスケジュールしました")
    }
    
    // アプリがフォアグラウンドに復帰
    func applicationWillEnterForeground(_ application: UIApplication) {
        // BeReal風通知を再スケジュール（通知が少なくなっている場合に補充）
        NotificationService.shared.rescheduleBeRealNotificationsIfNeeded()
        
        // フォアグラウンドに戻った際にトークンを再確認
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .authorized {
                await MainActor.run {
                    application.registerForRemoteNotifications()
                }
            }
        }
    }
}

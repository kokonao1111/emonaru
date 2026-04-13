import SwiftUI
import CoreLocation
import UIKit

// ============================================
// MainTabView: アプリのメイン画面（タブ管理）
// ============================================
// このファイルの役割：
// - 画面下部のタブバーを管理
// - 4つのタブ（ミニゲーム、投稿、地図、プロフィール）
// - 通知からの画面遷移を処理
// - チュートリアル（初回のみ）を表示
// ============================================

struct MainTabView: View {
    // どのタブが選択されているか（1=投稿タブがデフォルト）
    @State private var selectedTab = 1
    
    // 画面遷移用の変数
    @State private var targetLocation: CLLocationCoordinate2D?  // 地図の移動先
    @State private var targetPostID: UUID?  // 表示する投稿のID
    @State private var allowNextMapJump = false  // 地図移動の許可フラグ
    
    // チュートリアル表示フラグ（初回のみtrue）
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    
    // ミニゲームを読み込むかどうか（起動時のちらつき防止）
    @State private var shouldLoadMiniGame = false
    
    // ダークモード/ライトモードの状態
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                // ミニゲームタブ（条件付き読み込み）
                Group {
                    if shouldLoadMiniGame {
                        MiniGameView()
                    } else {
                        // 完全に空のビュー（何も表示しない）
                        Rectangle()
                            .fill(Color.clear)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .tabItem {
                    Label("ミニゲーム", systemImage: "gamecontroller.fill")
                }
                .tag(0)
                
                EmotionPostView(
                    selectedTab: $selectedTab,
                    targetLocation: $targetLocation,
                    targetPostID: $targetPostID,
                    allowNextMapJump: $allowNextMapJump
                )
                .tabItem {
                    Label("投稿", systemImage: "heart.fill")
                }
                .tag(1)
                
                EmotionMapView(
                    targetLocation: $targetLocation,
                    targetPostID: $targetPostID,
                    allowNextMapJump: $allowNextMapJump
                )
                .tabItem {
                    Label("地図", systemImage: "map.fill")
                }
                .tag(2)
                
                ProfileView()
                    .tabItem {
                        Label("プロフィール", systemImage: "person.fill")
                    }
                .tag(3)
            }
            .onChange(of: selectedTab) { newValue in
                // ミニゲームタブが選択されたら読み込む
                if newValue == 0 {
                    shouldLoadMiniGame = true
                }
            }
            .onAppear {
                // 起動時は必ず投稿タブを表示
                selectedTab = 1
                
                // 0.5秒後にミニゲームの読み込みを許可（起動時のちらつき完全防止）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    shouldLoadMiniGame = true
                }
                
                configureTabBarAppearance(for: colorScheme)
                
                // 友達申請の監視を開始（念のため）
                FriendRequestNotificationService.shared.startMonitoring()
                handleDailyReminderIfNeeded()
            }
            .onChange(of: colorScheme) { newColorScheme in
                configureTabBarAppearance(for: newColorScheme)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                handleDailyReminderIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenPostTab"))) { _ in
                // 通知がタップされたときに投稿タブに遷移
                selectedTab = 1
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenMapAtLocation"))) { notification in
                if let coordinate = notification.object as? CLLocationCoordinate2D {
                    allowNextMapJump = true
                    targetLocation = coordinate
                    targetPostID = nil
                    selectedTab = 2
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenFriendRequests"))) { _ in
                // 友達申請通知がタップされたらプロフィールタブに遷移
                selectedTab = 3
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenProfile"))) { _ in
                // 応援通知がタップされたらプロフィールタブに遷移
                selectedTab = 3
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenMapTab"))) { _ in
                // 観光スポット到着通知がタップされたら地図タブに遷移
                selectedTab = 2
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenMapAtPost"))) { notification in
                // 投稿関連の通知がタップされたら地図タブに遷移して投稿を表示
                if let userInfo = notification.object as? [String: Any],
                   let coordinate = userInfo["coordinate"] as? CLLocationCoordinate2D,
                   let postID = userInfo["postID"] as? UUID {
                    allowNextMapJump = true
                    targetLocation = coordinate
                    targetPostID = postID
                    selectedTab = 2
                    print("✅ 地図タブに遷移: postID=\(postID.uuidString)")
                }
            }
            
            // オンボーディングを上に重ねる（ZStackで）
            if showOnboarding {
                OnboardingView(isPresented: $showOnboarding, selectedTab: $selectedTab)
            }
        }
    }

    private func handleDailyReminderIfNeeded() {
        NotificationService.shared.handleRecentDailyReminder {}
    }
    
    private func configureTabBarAppearance(for colorScheme: ColorScheme) {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        
        // カラースキームに応じて背景色とシャドウを設定
        if colorScheme == .dark {
            // ダークモード: 暗い背景でしっかり見える
            appearance.backgroundColor = UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0)
            appearance.shadowColor = UIColor(white: 0.3, alpha: 0.3)
        } else {
            // ライトモード: 白い背景
            appearance.backgroundColor = UIColor.white
            appearance.shadowColor = UIColor(white: 0.0, alpha: 0.1)
        }
        
        // 選択されていないアイテムの色
        let normalIconColor = colorScheme == .dark ? UIColor.lightGray : UIColor.gray
        appearance.stackedLayoutAppearance.normal.iconColor = normalIconColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalIconColor]
        
        // 選択されたアイテムの色
        let selectedIconColor = UIColor.systemBlue
        appearance.stackedLayoutAppearance.selected.iconColor = selectedIconColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedIconColor]
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

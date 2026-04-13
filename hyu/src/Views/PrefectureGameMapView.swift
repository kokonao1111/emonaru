import SwiftUI
import MapKit
import CoreLocation

struct PrefectureGameMapView: View {
    let prefecture: Prefecture
    @StateObject private var locationService = LocationService()
    private let firestoreService = FirestoreService()
    
    @State private var gauge: PrefectureGauge?
    @State private var previousGaugeValue: Int = 0
    @State private var posts: [EmotionPost] = []
    @State private var isLoading = false
    @State private var showPostView = false
    @State private var selectedPost: EmotionPost?
    @State private var showRanking = false
    @State private var rankingGauges: [PrefectureGauge] = []
    @State private var showGaugeComplete = false
    @State private var gaugeCompleteInfo: (level: Int, experiencePoints: Int, postBonus: Int, nextMax: Int)?
    @State private var gaugeGlowing = false
    @State private var registration: UserPrefectureRegistration?
    
    // 地図のカメラ位置（都道府県の中心に設定）
    @State private var cameraPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    )
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let isSmallScreen = screenWidth <= 375 // iPhone SE (375px) 以下
            
            ZStack {
                // 地図
                Map(position: $cameraPosition) {
                // 投稿のピン
                ForEach(postsWithLocation) { post in
                    Annotation(post.level.rawValue.description, coordinate: post.coordinate) {
                        EmotionPin(post: post)
                            .onTapGesture {
                                selectedPost = post
                            }
                    }
                }
                
                // 現在地の表示
                if let coordinate = locationService.currentLocation?.coordinate {
                    Annotation("", coordinate: coordinate) {
                        userLocationAnnotationView()
                    }
                }
            }
            .ignoresSafeArea()
            .onAppear {
                locationService.requestPermission()
                locationService.startUpdatingLocation()
                setupMap()
                Task {
                    await loadGauge()
                    // 初回読み込み時はpreviousGaugeValueを現在の値に設定（リザルト画面を表示しないため）
                    if let gauge = gauge {
                        previousGaugeValue = gauge.currentValue
                    }
                    await loadPosts()
                    await loadRanking()
                }
            }
            .onDisappear {
                locationService.stopUpdatingLocation()
            }
            .onChange(of: posts) { _, _ in
                Task {
                    await loadGauge()
                    await loadRanking()
                }
            }
            
            VStack {
                // 上部：ゲージ表示
                VStack(spacing: isSmallScreen ? 8 : 12) {
                    HStack {
                        Text(prefecture.rawValue)
                            .font(isSmallScreen ? .headline : .title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Spacer()
                        Button("全国ランキング") {
                            showRanking = true
                        }
                        .font(isSmallScreen ? .caption2 : .caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, isSmallScreen ? 8 : 10)
                        .padding(.vertical, isSmallScreen ? 4 : 6)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(8)
                    }
                    
                    // ミニゲーム説明
                    HStack(spacing: isSmallScreen ? 4 : 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: isSmallScreen ? 12 : 14))
                            .foregroundColor(.orange)
                        Text("感情を投稿してゲージを貯めよう！")
                            .font(isSmallScreen ? .caption : .subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, isSmallScreen ? 6 : 8)
                    .padding(.horizontal, isSmallScreen ? 8 : 12)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.orange.opacity(0.7), Color.red.opacity(0.7)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(isSmallScreen ? 8 : 10)
                    
                    if let gauge = gauge {
                        VStack(spacing: isSmallScreen ? 4 : 8) {
                            HStack {
                                Text("感情ゲージ")
                                    .font(isSmallScreen ? .subheadline : .headline)
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(gauge.currentValue)/\(gauge.maxValue)")
                                    .font(isSmallScreen ? .caption : .subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            
                            GeometryReader { gaugeGeometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: isSmallScreen ? 6 : 8)
                                        .fill(Color.white.opacity(0.3))
                                        .frame(height: isSmallScreen ? 20 : 24)
                                    
                                    RoundedRectangle(cornerRadius: isSmallScreen ? 6 : 8)
                                        .fill(gaugeColor(for: gauge.progress))
                                        .frame(width: gaugeGeometry.size.width * gauge.progress, height: isSmallScreen ? 20 : 24)
                                        .shadow(color: gaugeGlowing ? .yellow : .clear, radius: gaugeGlowing ? 15 : 0)
                                        .animation(.spring(), value: gauge.progress)
                                    
                                    // 満タン時の光るエフェクト
                                    if gauge.isCompleted {
                                        RoundedRectangle(cornerRadius: isSmallScreen ? 6 : 8)
                                            .fill(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [.white.opacity(0.8), .yellow.opacity(0.8)]),
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: gaugeGeometry.size.width, height: isSmallScreen ? 20 : 24)
                                            .opacity(gaugeGlowing ? 0.6 : 0.2)
                                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: gaugeGlowing)
                                    }
                                }
                            }
                            .frame(height: isSmallScreen ? 20 : 24)
                            
                            // 報酬情報（常に表示）
                            VStack(spacing: isSmallScreen ? 2 : 4) {
                                let nextLevel = (registration?.completedCount ?? 0) + 1
                                let nextRewards = calculateRewards(completedCount: nextLevel)
                                
                                if gauge.isCompleted {
                                    Text("🎉 報酬獲得済み！")
                                        .font(isSmallScreen ? .caption2 : .caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.yellow)
                                } else {
                                    Text("満タン時の報酬 (Lv.\(nextLevel))")
                                        .font(isSmallScreen ? .system(size: 9) : .caption2)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                
                                HStack(spacing: isSmallScreen ? 8 : 12) {
                                    HStack(spacing: isSmallScreen ? 2 : 4) {
                                        Image(systemName: "bolt.fill")
                                            .font(.system(size: isSmallScreen ? 8 : 10))
                                            .foregroundColor(.yellow)
                                        Text("\(nextRewards.experience)")
                                            .font(isSmallScreen ? .caption2 : .caption)
                                            .foregroundColor(.yellow)
                                            .fontWeight(.semibold)
                                    }
                                    
                                    HStack(spacing: isSmallScreen ? 2 : 4) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: isSmallScreen ? 8 : 10))
                                            .foregroundColor(.green)
                                        Text("+\(nextRewards.postBonus)回")
                                            .font(isSmallScreen ? .caption2 : .caption)
                                            .foregroundColor(.green)
                                            .fontWeight(.semibold)
                                    }
                                }
                            }
                            .padding(.top, isSmallScreen ? 2 : 4)
                        }
                        .padding(isSmallScreen ? 12 : 16)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(isSmallScreen ? 10 : 12)
                    }
                }
                .padding(isSmallScreen ? 12 : 16)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.7), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                Spacer()
                
                // 下部：投稿ボタン
                VStack(spacing: isSmallScreen ? 12 : 16) {
                    Button(action: {
                        showPostView = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("感情を投稿する")
                                .fontWeight(.semibold)
                        }
                        .font(isSmallScreen ? .subheadline : .headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(isSmallScreen ? 12 : 16)
                        .background(Color.blue)
                        .cornerRadius(isSmallScreen ? 10 : 12)
                        .shadow(radius: 4)
                    }
                    .padding(.horizontal, isSmallScreen ? 12 : 16)
                }
                .padding(.bottom, isSmallScreen ? 20 : 40)
                .background(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .sheet(isPresented: $showPostView) {
            PrefecturePostView(
                prefecture: prefecture,
                onPostComplete: {
                    showPostView = false
                    Task {
                        await loadPosts()
                        await loadGauge()
                        await loadRanking()
                    }
                }
            )
        }
        .sheet(item: $selectedPost) { post in
            NavigationView {
                EmotionDetailSheet(
                    post: post,
                    onSupport: { updatedPost, emoji in
                        await addSupport(postID: updatedPost.id, emoji: emoji)
                    },
                    onRemoveSupport: { updatedPost in
                        await removeSupport(postID: updatedPost.id)
                    }
                )
                .id("\(post.id.uuidString)_\(post.supportCount)_\(post.supports.count)")
            }
        }
        .sheet(isPresented: $showRanking) {
            RankingSheet(gauges: rankingGauges)
        }
        .fullScreenCover(isPresented: $showGaugeComplete, onDismiss: {
            // リザルト画面を閉じた後、ゲージをリセット表示
            Task {
                // 光るアニメーションを停止
                await MainActor.run {
                    gaugeGlowing = false
                }
                
                // ゲージを強制的にリセット表示（次の目標値で0からスタート）
                if let info = gaugeCompleteInfo {
                    let newGauge = PrefectureGauge(
                        prefecture: prefecture,
                        currentValue: 0,
                        maxValue: info.nextMax,
                        lastUpdated: Date(),
                        completedDate: nil, // リセット時は completedDate をクリア
                        completedCount: info.level
                    )
                    
                    await MainActor.run {
                        self.gauge = newGauge
                        print("🔄 ゲージをリセット表示: 0/\(info.nextMax)")
                    }
                    
                    // 🆕 重要：Firestoreにリセット後の値を保存
                    do {
                        try await firestoreService.resetPrefectureGauge(
                            prefecture: prefecture,
                            currentValue: 0,
                            maxValue: info.nextMax,
                            completedDate: nil
                        )
                        print("✅ Firestoreにゲージリセットを保存: 0/\(info.nextMax)")
                    } catch {
                        print("❌ ゲージリセットの保存に失敗: \(error.localizedDescription)")
                    }
                }
                
                // 1秒後にFirestoreから最新データを取得（キャッシュをバイパスして強制的にサーバーから取得）
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
                await loadGauge(forceServerFetch: true)
                await loadPosts()
                
                print("✅ Firestoreから強制的にゲージを再読み込みしました（サーバーから直接取得）")
            }
        }) {
            if let info = gaugeCompleteInfo {
                GaugeCompleteView(
                    prefecture: prefecture.rawValue,
                    level: info.level,
                    experiencePoints: info.experiencePoints,
                    postBonus: info.postBonus,
                    nextMaxValue: info.nextMax,
                    isPresented: $showGaugeComplete
                )
            }
        }
        }
    }
    
    private func setupMap() {
        let center = prefecture.centerCoordinate
        cameraPosition = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
            )
        )
    }

    @ViewBuilder
    private func userLocationAnnotationView() -> some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.25))
                .frame(width: 28, height: 28)
            Circle()
                .fill(Color.blue)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
        }
        .shadow(color: .blue.opacity(0.4), radius: 4, x: 0, y: 2)
    }
    
    private func loadGauge(forceServerFetch: Bool = false) async {
        do {
            let gauges = try await firestoreService.fetchPrefectureGauges(forceServerFetch: forceServerFetch)
            let registrations = try await firestoreService.fetchUserPrefectureRegistrations(forceServerFetch: forceServerFetch)
            
            await MainActor.run {
                if let existingGauge = gauges.first(where: { $0.id == prefecture.rawValue }) {
                    let previousValue = self.gauge?.currentValue ?? 0
                    
                    // 🆕 異常値チェック：currentValueがmaxValueを大幅に超えている場合
                    if existingGauge.currentValue > existingGauge.maxValue * 2 {
                        print("⚠️ 異常値検出: \(existingGauge.currentValue)/\(existingGauge.maxValue) → 自動修正します")
                        
                        // 異常値を修正してFirestoreに保存
                        Task {
                            do {
                                try await firestoreService.resetPrefectureGauge(
                                    prefecture: prefecture,
                                    currentValue: 0,
                                    maxValue: existingGauge.maxValue,
                                    completedDate: nil
                                )
                                print("✅ 異常値を修正しました: 0/\(existingGauge.maxValue)")
                                
                                // 1秒後に再読み込み
                                try? await Task.sleep(nanoseconds: 1_000_000_000)
                                await loadGauge(forceServerFetch: true)
                            } catch {
                                print("❌ 異常値の修正に失敗: \(error.localizedDescription)")
                            }
                        }
                        return
                    }
                    
                    self.gauge = existingGauge
                    self.registration = registrations.first(where: { $0.prefecture == prefecture.rawValue })
                    
                    print("✅ ゲージ読み込み成功: \(prefecture.rawValue) - \(existingGauge.currentValue)/\(existingGauge.maxValue)")
                    
                    // まだ見ていない完了をチェック
                    if let reg = self.registration {
                        let currentCompletedCount = reg.completedCount
                        let lastViewedCount = getLastViewedCompletionCount()
                        
                        // ゲージが満タンで、まだ見ていない完了がある場合
                        if existingGauge.isCompleted && currentCompletedCount > lastViewedCount {
                            // 光るアニメーション開始
                            gaugeGlowing = true
                            
                            // 0.5秒後にリザルト画面を表示
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                let level = currentCompletedCount
                                let nextMax = max(existingGauge.maxValue + 20, Int(ceil(Double(existingGauge.maxValue) * 1.2)))
                                
                                // 完了回数に応じた報酬を計算
                                let rewards = calculateRewards(completedCount: level)
                                
                                gaugeCompleteInfo = (
                                    level: level,
                                    experiencePoints: rewards.experience,
                                    postBonus: rewards.postBonus,
                                    nextMax: nextMax
                                )
                                showGaugeComplete = true
                                
                                // リザルト画面を見たことを記録
                                saveLastViewedCompletionCount(currentCompletedCount)
                                
                                // 光るアニメーションを停止
                                gaugeGlowing = false
                            }
                        } else {
                            // リザルト画面を見た後は光らない
                            gaugeGlowing = false
                        }
                    }
                    
                    previousGaugeValue = existingGauge.currentValue
                } else {
                    // 登録されていない場合は、デフォルトのゲージを作成
                    self.gauge = PrefectureGauge(prefecture: prefecture, currentValue: 0, maxValue: 100)
                    print("⚠️ ゲージが見つからないため、デフォルトのゲージを作成: \(prefecture.rawValue)")
                }
            }
        } catch {
            print("❌ ゲージの読み込みに失敗: \(error.localizedDescription)")
            await MainActor.run {
                // エラー時もデフォルトのゲージを表示
                self.gauge = PrefectureGauge(prefecture: prefecture, currentValue: 0, maxValue: 100)
            }
        }
    }
    
    // 最後に見た完了回数を取得
    private func getLastViewedCompletionCount() -> Int {
        let key = "lastViewedCompletion_\(prefecture.rawValue)"
        return UserDefaults.standard.integer(forKey: key)
    }
    
    // 最後に見た完了回数を保存
    private func saveLastViewedCompletionCount(_ count: Int) {
        let key = "lastViewedCompletion_\(prefecture.rawValue)"
        UserDefaults.standard.set(count, forKey: key)
        print("✅ リザルト画面を見たことを記録: \(prefecture.rawValue) - レベル\(count)")
    }
    
    // 完了回数に応じた報酬を計算
    private func calculateRewards(completedCount: Int) -> (experience: Int, postBonus: Int) {
        // 10回ごとに報酬が増える
        let tier = completedCount / 10
        
        // 経験値: 基本100 + (tier * 50)
        let experience = 100 + (tier * 50)
        
        // 投稿回数ボーナス: 基本1 + (tier / 2)
        let postBonus = 1 + (tier / 2)
        
        return (experience, postBonus)
    }

    private func loadRanking() async {
        do {
            // 全都道府県の共有ゲージを取得
            let allGauges = try await firestoreService.fetchAllSharedGauges()
            
            // 現在の値でソート（活発な都道府県が上位）
            let sorted = allGauges.sorted { $0.currentValue > $1.currentValue }
            
            await MainActor.run {
                rankingGauges = Array(sorted.prefix(10))
                print("✅ ランキング読み込み成功: トップ10都道府県")
            }
        } catch {
            print("❌ ランキングの読み込みに失敗: \(error.localizedDescription)")
        }
    }
    
    private func loadPosts() async {
        isLoading = true
        do {
            let center = prefecture.centerCoordinate
            // 都道府県内の投稿を取得（中心から半径50km以内）
            let allPosts = try await firestoreService.fetchRecentEmotions(lastHours: 24, includeOnlyFriends: false)
            let filteredPosts = allPosts.filter { post in
                guard let lat = post.latitude, let lon = post.longitude else { return false }
                let distance = calculateDistance(
                    lat1: center.latitude, lon1: center.longitude,
                    lat2: lat, lon2: lon
                )
                return distance <= 50.0 // 50km以内
            }
            
            await MainActor.run {
                self.posts = filteredPosts
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
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
    
    private var postsWithLocation: [EmotionPost] {
        posts.filter { $0.latitude != nil && $0.longitude != nil }
    }
    
    private func gaugeColor(for progress: Double) -> Color {
        if progress >= 1.0 {
            return .green
        } else if progress >= 0.7 {
            return .blue
        } else if progress >= 0.4 {
            return .yellow
        } else {
            return .orange
        }
    }
    //
    private func addSupport(postID: UUID, emoji: SupportEmoji) async {
        do {
            // 投稿情報を取得
            let postBeforeUpdate = posts.first(where: { $0.id == postID })
            
            print("📍 [Prefecture] 共感追加を開始: postID=\(postID.uuidString)")
            let newSupportCount = try await firestoreService.addSupport(postID: postID, emoji: emoji, post: postBeforeUpdate)
            print("📍 [Prefecture] 共感追加が完了: 新しい応援数=\(newSupportCount)")
            
            // 投稿一覧を再読み込み
            await loadPosts()
            print("📍 [Prefecture] 投稿一覧の再読み込み完了: 全投稿数=\(posts.count)")
            
            // 選択中の投稿も更新
            if let index = posts.firstIndex(where: { $0.id == postID }) {
                let updatedPost = posts[index]
                print("📍 [Prefecture] selectedPostを更新: 応援数=\(updatedPost.supportCount), supports数=\(updatedPost.supports.count)")
                print("📍 [Prefecture] 更新後のsupports配列: \(updatedPost.supports.map { "\($0.userID): \($0.emoji.rawValue)" })")
                await MainActor.run {
                    // 確実に更新するため、一度nilにしてから再設定
                    let temp = updatedPost
                    selectedPost = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        selectedPost = temp
                    }
                }
            } else {
                print("⚠️ [Prefecture] 選択中の投稿が投稿一覧に見つかりません")
            }
        } catch {
            print("❌ [Prefecture] 応援の追加に失敗しました: \(error.localizedDescription)")
        }
    }
    
    private func removeSupport(postID: UUID) async {
        // EmotionDetailSheetから呼ばれた時は、既にFirestoreから削除済み
        // ここでは投稿一覧の再読み込みのみを行う
        print("📍 [Prefecture] 親のremoveSupport呼び出し: postID=\(postID.uuidString)")
        
        // 投稿一覧を再読み込み
        await loadPosts()
        print("📍 [Prefecture] 投稿一覧の再読み込み完了: 全投稿数=\(posts.count)")
        
        // 選択中の投稿も更新
        if let index = posts.firstIndex(where: { $0.id == postID }) {
            let updatedPost = posts[index]
            print("📍 [Prefecture] selectedPostを更新: 応援数=\(updatedPost.supportCount), supports数=\(updatedPost.supports.count)")
            print("📍 [Prefecture] 更新後のsupports配列: \(updatedPost.supports.map { "\($0.userID): \($0.emoji.rawValue)" })")
            await MainActor.run {
                // 確実に更新するため、一度nilにしてから再設定
                let temp = updatedPost
                selectedPost = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    selectedPost = temp
                }
            }
        } else {
            print("⚠️ [Prefecture] 選択中の投稿が投稿一覧に見つかりません")
        }
    }
}

// 都道府県専用の投稿ビュー
struct PrefecturePostView: View {
    let prefecture: Prefecture
    let onPostComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var locationService = LocationService()
    private let firestoreService = FirestoreService()
    
    @State private var emotionLevel: EmotionLevel = .zero
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var dragStartLevel: Int? = nil
    
    var body: some View {
        NavigationView {
            GeometryReader { proxy in
                ZStack {
                    // 背景グラデーション
                    LinearGradient(
                        colors: [emotionColor.opacity(0.3), emotionColor],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    
                    VStack(spacing: 24) {
                        Text(prefecture.rawValue)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.top, 48)
                        
                        // 感情レベル選択スライダー
                        VStack(spacing: 16) {
                            Text(emotionEmoji)
                                .font(.system(size: 80))
                                .shadow(color: .black.opacity(0.3), radius: 8)
                            
                            Text(emotionLevelText)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 4)
                            
                            // 横スライダー（画面サイズに合わせて拡大）
                            let sliderWidth = min(proxy.size.width * 0.85, 600)
                            let sliderHeight: CGFloat = proxy.size.width >= 768 ? 80 : 60
                            
                            ZStack(alignment: .center) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 50)
                                
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.4))
                                    .frame(height: 8)
                                
                                let markerCenterX = 18.0 + (CGFloat(emotionLevel.rawValue + 5) / 10.0) * (sliderWidth - 36.0)
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 36, height: 36)
                                    .shadow(color: .black.opacity(0.3), radius: 4)
                                    .offset(x: markerCenterX - sliderWidth / 2.0)
                            }
                            .frame(width: sliderWidth, height: sliderHeight)
                            .contentShape(Rectangle())
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 3)
                                    .onChanged { dragValue in
                                        if dragStartLevel == nil {
                                            dragStartLevel = emotionLevel.rawValue
                                        }
                                        
                                        guard let startLevel = dragStartLevel else { return }
                                        
                                        let translationX = dragValue.translation.width
                                        let effectiveWidth = sliderWidth - 36.0
                                        let levelChange = translationX / effectiveWidth * 10.0
                                        let newValue = Int(round(Double(startLevel) + levelChange))
                                        let clampedValue = max(-5, min(5, newValue))
                                        
                                        if emotionLevel.rawValue != clampedValue {
                                            emotionLevel = EmotionLevel.clamped(clampedValue)
                                        }
                                    }
                                    .onEnded { _ in
                                        dragStartLevel = nil
                                    }
                            )
                        }
                        .padding(.horizontal)
                        .padding(.top, proxy.size.width >= 768 ? 24 : 0)
                        
                        Spacer(minLength: 0)
                        
                        Button(action: {
                        Task {
                            await submitPost()
                        }
                        }) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "paperplane.fill")
                                }
                                Text(isLoading ? "投稿中..." : "投稿する")
                                    .fontWeight(.semibold)
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                            .shadow(radius: 4)
                        }
                        .disabled(isLoading)
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                        
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.black)
                                .padding()
                        }
                    }
                    .padding(.top, proxy.size.width >= 768 ? 80 : 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .navigationTitle("感情を投稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var emotionColor: Color {
        let t = Double(emotionLevel.rawValue + 5) / 10
        let hue = 0.62 - 0.62 * t
        return Color(hue: hue, saturation: 0.55, brightness: 0.95)
    }
    
    private var emotionLevelText: String {
        switch emotionLevel {
        case .minusFive: return "とても悲しい"
        case .minusFour: return "悲しい"
        case .minusThree: return "少し悲しい"
        case .minusTwo: return "やや悲しい"
        case .minusOne: return "少し低い"
        case .zero: return "普通"
        case .plusOne: return "少し高い"
        case .plusTwo: return "やや嬉しい"
        case .plusThree: return "少し嬉しい"
        case .plusFour: return "嬉しい"
        case .plusFive: return "とても嬉しい"
        }
    }
    
    private var emotionEmoji: String {
        switch emotionLevel {
        case .minusFive, .minusFour: return "😢"
        case .minusThree, .minusTwo: return "😔"
        case .minusOne: return "😐"
        case .zero: return "😊"
        case .plusOne: return "😄"
        case .plusTwo, .plusThree: return "😃"
        case .plusFour, .plusFive: return "🤩"
        }
    }
    
    private func submitPost() async {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // 実際の位置情報を取得（高精度で取得するまで待つ）
            locationService.startUpdatingLocation()
            
            var actualLocation: CLLocation?
            let requiredAccuracy: CLLocationAccuracy = 50.0 // 50m以内の精度を要求
            
            // 最大5秒間、精度が十分になるまで待つ
            for _ in 0..<50 {
                if let tempLocation = await locationService.getCurrentLocation() {
                    // 精度が十分な場合は採用
                    if tempLocation.horizontalAccuracy > 0 && tempLocation.horizontalAccuracy <= requiredAccuracy {
                        actualLocation = tempLocation
                        print("✅ 高精度な位置情報を取得: 精度 \(tempLocation.horizontalAccuracy)m")
                        break
                    }
                    // 精度が不十分でも、一旦保存しておく（タイムアウト時に使用）
                    actualLocation = tempLocation
                }
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒待つ
            }
            
            locationService.stopUpdatingLocation()
            
            guard let location = actualLocation else {
                await MainActor.run {
                    errorMessage = "位置情報を取得できませんでした。設定で位置情報の許可を確認してください。"
                    isLoading = false
                }
                return
            }
            
            // 精度の警告
            if location.horizontalAccuracy > requiredAccuracy {
                print("⚠️ 位置情報の精度が低い可能性があります: \(location.horizontalAccuracy)m")
            }
            
            let latitude = location.coordinate.latitude
            let longitude = location.coordinate.longitude
            
            // 実際の位置が登録した都道府県内にあるか確認（逆ジオコーディングを使用）
            guard let prefectureName = await locationService.getPrefectureFromCoordinate(latitude: latitude, longitude: longitude) else {
                await MainActor.run {
                    errorMessage = "現在地の都道府県を特定できませんでした。もう一度お試しください。"
                    isLoading = false
                }
                return
            }
            
            let detectedPrefecture = Prefecture(rawValue: prefectureName)
            
            guard detectedPrefecture == prefecture else {
                await MainActor.run {
                    errorMessage = "\(prefecture.rawValue)にいないとゲージを貯めることができません。現在地: \(prefectureName)"
                    isLoading = false
                }
                return
            }
            
            // 都道府県内にいる場合のみ投稿
            try await firestoreService.postMiniGame(
                level: emotionLevel,
                latitude: latitude,
                longitude: longitude
            )
            
            await MainActor.run {
                isLoading = false
                onPostComplete()
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = "エラー: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}

// EmotionPinとEmotionDetailSheetをPrefectureGameMapViewでも使用できるように追加
private struct EmotionPin: View {
    let post: EmotionPost
    @State private var animationScale: CGFloat = 1.0
    @State private var rippleScale: CGFloat = 1.0
    @State private var rippleOpacity: Double = 0.0
    
    var body: some View {
        ZStack {
            // 応援数に応じた滲み効果（複数の輪）
            if post.supportCount > 0 {
                ForEach(0..<min(post.supportCount, 5), id: \.self) { index in
                    Circle()
                        .fill(pinColor.opacity(0.3))
                        .frame(width: baseSize + CGFloat(index * 10), height: baseSize + CGFloat(index * 10))
                        .scaleEffect(rippleScale + CGFloat(index) * 0.2)
                        .opacity(rippleOpacity * (1.0 - Double(index) * 0.15))
                }
            }
            
            // メインのピン
            Circle()
                .fill(pinColor)
                .frame(width: baseSize, height: baseSize)
                .shadow(radius: 3)
                .scaleEffect(animationScale)
            
            Text(emoji)
                .font(.system(size: 16))
        }
        .onAppear {
            startAnimation()
        }
        .onChange(of: post.supportCount) { oldValue, newValue in
            startAnimation()
        }
    }
    
    private var baseSize: CGFloat {
        let supportMultiplier = min(CGFloat(post.supportCount) * 2.0, 20.0)
        return 30 + supportMultiplier
    }
    
    private var pinColor: Color {
        let t = Double(post.level.rawValue + 5) / 10
        let hue = 0.62 - 0.62 * t
        return Color(hue: hue, saturation: 0.7, brightness: 0.9)
    }
    
    private var emoji: String {
        switch post.level {
        case .minusFive, .minusFour: return "😢"
        case .minusThree, .minusTwo: return "😔"
        case .minusOne: return "😐"
        case .zero: return "😊"
        case .plusOne: return "😄"
        case .plusTwo, .plusThree: return "😃"
        case .plusFour, .plusFive: return "🤩"
        }
    }
    
    private func startAnimation() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            animationScale = post.supportCount > 0 ? 1.1 : 1.0
        }
        
        if post.supportCount > 0 {
            rippleScale = 1.0
            rippleOpacity = 0.6
            
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                rippleScale = 2.0 + CGFloat(min(post.supportCount, 5)) * 0.3
                rippleOpacity = 0.0
            }
        }
    }
}

private struct RankingSheet: View {
    let gauges: [PrefectureGauge]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if gauges.isEmpty {
                    Text("ランキングがまだありません")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("全国の都道府県で投稿された感情の合計ゲージ量")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: "gift.fill")
                                        .foregroundColor(.orange)
                                    Text("満タン報酬（レベルで変動）:")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                HStack(spacing: 8) {
                                    HStack(spacing: 2) {
                                        Image(systemName: "bolt.fill")
                                            .font(.system(size: 8))
                                            .foregroundColor(.yellow)
                                        Text("100~")
                                            .font(.caption2)
                                            .foregroundColor(.yellow)
                                    }
                                    HStack(spacing: 2) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 8))
                                            .foregroundColor(.green)
                                        Text("+1~")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    ForEach(Array(gauges.enumerated()), id: \.offset) { index, gauge in
                        HStack(spacing: 12) {
                            // 順位
                            ZStack {
                                if let crown = crownSymbol(for: index) {
                                    Image(systemName: crown)
                                        .foregroundColor(crownColor(for: index))
                                        .font(.title3)
                                } else {
                                    Text("\(index + 1)")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(width: 32)
                            
                            // 都道府県名
                            Text(gauge.id)
                                .font(.body)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            // ゲージ値
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(gauge.currentValue)")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                                
                                if gauge.completedCount > 0 {
                                    Text("レベル\(gauge.completedCount)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("全国ランキング")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func crownSymbol(for index: Int) -> String? {
        switch index {
        case 0, 1, 2:
            return "crown.fill"
        default:
            return nil
        }
    }

    private func crownColor(for index: Int) -> Color {
        switch index {
        case 0:
            return Color.yellow
        case 1:
            return Color.gray
        case 2:
            return Color.orange
        default:
            return Color.secondary
        }
    }
}

private struct EmotionDetailSheet: View {
    let post: EmotionPost
    let onSupport: (EmotionPost, SupportEmoji) async -> Void
    let onRemoveSupport: (EmotionPost) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var currentPost: EmotionPost
    
    init(post: EmotionPost, 
         onSupport: @escaping (EmotionPost, SupportEmoji) async -> Void,
         onRemoveSupport: @escaping (EmotionPost) async -> Void) {
        self.post = post
        self.onSupport = onSupport
        self.onRemoveSupport = onRemoveSupport
        _currentPost = State(initialValue: post)
    }
    
    var body: some View {
        VStack(spacing: 24) {
                Text(emoji)
                    .font(.system(size: 80))
                
                Text(levelText)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("\(currentPost.level.rawValue)")
                    .font(.title)
                    .foregroundColor(.secondary)
                
                if let createdAt = formatDate(currentPost.createdAt) {
                    Text(createdAt)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let comment = currentPost.comment, !comment.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("コメント")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(comment)
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                
                Spacer()
                
            }
            .padding()
            .navigationTitle("感情の詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        .onAppear {
            currentPost = post
        }
        .onChange(of: post.id) { oldValue, newValue in
            currentPost = post
        }
    }
    
    private var emoji: String {
        switch currentPost.level {
        case .minusFive, .minusFour: return "😢"
        case .minusThree, .minusTwo: return "😔"
        case .minusOne: return "😐"
        case .zero: return "😊"
        case .plusOne: return "😄"
        case .plusTwo, .plusThree: return "😃"
        case .plusFour, .plusFive: return "🤩"
        }
    }
    
    private var levelText: String {
        switch currentPost.level {
        case .minusFive: return "とても悲しい"
        case .minusFour: return "悲しい"
        case .minusThree: return "少し悲しい"
        case .minusTwo: return "やや悲しい"
        case .minusOne: return "少し低い"
        case .zero: return "普通"
        case .plusOne: return "少し高い"
        case .plusTwo: return "やや嬉しい"
        case .plusThree: return "少し嬉しい"
        case .plusFour: return "嬉しい"
        case .plusFive: return "とても嬉しい"
        }
    }
    
    private func formatDate(_ date: Date) -> String? {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
}


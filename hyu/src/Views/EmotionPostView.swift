import SwiftUI
import CoreLocation

// ============================================
// EmotionPostView: 感情投稿画面
// ============================================
// このファイルの役割：
// - ユーザーが感情を選んで投稿する画面
// - スライダーで感情レベル（-5〜+5）を選択
// - 現在位置を取得して投稿に付与
// - 観光スポットの近くだとボーナス
// - 投稿回数の制限管理（1日5回〜10回）
// ============================================

struct EmotionPostView: View {
    // データベース操作用（投稿を保存するため）
    private let firestoreService = FirestoreService()
    private let postUseCase = PostUseCase(
        postRepository: IOSPostRepository()
    )
    // 位置情報取得用（現在地を取得するため）
    @StateObject private var locationService = LocationService()
    
    // 画面遷移用の変数（他の画面から渡される）
    @Binding var selectedTab: Int  // 現在選択されているタブ番号
    @Binding var targetLocation: CLLocationCoordinate2D?  // 地図の移動先
    @Binding var targetPostID: UUID?  // 表示する投稿のID
    @Binding var allowNextMapJump: Bool  // 地図移動の許可フラグ
    
    // 画面内で使う変数（@Stateは値が変わると画面が自動更新される）
    @State private var emotionLevel: EmotionLevel = .zero  // 選択中の感情レベル
    @State private var myPosts: [EmotionPost] = []  // 自分の投稿履歴
    @State private var isLoading = false  // 投稿中かどうか（ボタンを無効化）
    @State private var errorMessage: String?  // エラーメッセージ（表示用）
    @State private var nearbySpot: Spot?  // 近くの観光スポット
    @State private var showSpotBonus = false  // スポットボーナス表示フラグ
    @State private var showMyPostsHistory = false  // 投稿履歴表示フラグ
    @State private var dragStartLevel: Int? = nil  // スライダードラッグ開始位置
    @State private var isPublicPost: Bool = true  // 公開設定（true=みんな、false=友達のみ）
    @State private var comment: String = ""  // コメント（任意）
    @State private var showCommentModal = false  // コメント入力画面の表示フラグ
    @State private var notificationBonusTimeRemaining: Int = 0  // 通知ボーナスの残り時間（秒）
    @State private var bonusTimer: Timer?  // 残り時間をカウントダウンするタイマー

    init(
        selectedTab: Binding<Int> = .constant(0),
        targetLocation: Binding<CLLocationCoordinate2D?> = .constant(nil),
        targetPostID: Binding<UUID?> = .constant(nil),
        allowNextMapJump: Binding<Bool> = .constant(false)
    ) {
        _selectedTab = selectedTab
        _targetLocation = targetLocation
        _targetPostID = targetPostID
        _allowNextMapJump = allowNextMapJump
    }

    var body: some View {
        GeometryReader { geometry in
            // 画面サイズに応じたスケール係数を計算（基準: iPhone 14 Pro = 393pt）
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let scale = min(screenWidth / 393.0, screenHeight / 852.0)
            let isSmallScreen = screenWidth <= 375 // iPhone SE (375pt) 以下
            let isLargeScreen = screenWidth > 430 // iPhone Pro Max, iPad (16eは393ptなので通常サイズ扱い)
            
            ZStack {
                VStack(spacing: 0) {
                    // エラーメッセージ表示（改善版）
                    if let errorMessage = errorMessage {
                        VStack(spacing: isSmallScreen ? 6 : 8) {
                            HStack {
                                Text(errorMessage)
                                    .font(.system(size: isSmallScreen ? 12 : 14))
                                    .foregroundColor(.red)
                                    .lineLimit(3)
                                Button(action: {
                                    self.errorMessage = nil
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: isSmallScreen ? 16 : 18))
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(isSmallScreen ? 12 : 14)
                            .background(Color.white.opacity(0.95))
                            .cornerRadius(isSmallScreen ? 10 : 12)
                            .shadow(radius: isSmallScreen ? 4 : 6)
                        }
                        .padding(.horizontal, isSmallScreen ? 16 : 20)
                        .padding(.top, isSmallScreen ? 60 : 70)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // 残りの投稿回数表示
                    VStack(spacing: isSmallScreen ? 4 : 8) {
                        HStack(spacing: isSmallScreen ? 8 : 12) {
                            Image(systemName: "calendar.badge.clock")
                                .font(isSmallScreen ? .body : .title3)
                                .foregroundColor(.white)
                            
                            VStack(alignment: .leading, spacing: isSmallScreen ? 1 : 3) {
                                HStack(spacing: isSmallScreen ? 3 : 6) {
                                    Text("今日の残り投稿回数:")
                                        .font(.system(size: isSmallScreen ? 11 : 15))
                                        .foregroundColor(.white.opacity(0.9))
                                    
                                    Text("\(UserService.shared.remainingPosts)/\(UserService.shared.dailyPostLimit) 回")
                                        .font(.system(size: isSmallScreen ? 14 : 18, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                
                                // 通知ボーナスが有効な場合
                                if notificationBonusTimeRemaining > 0 {
                                    HStack(spacing: isSmallScreen ? 2 : 4) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.system(size: isSmallScreen ? 9 : 11))
                                            .foregroundColor(.orange)
                                        Text("ボーナス有効！残り \(notificationBonusTimeRemaining)秒")
                                            .font(.system(size: isSmallScreen ? 9 : 12, weight: .bold))
                                            .foregroundColor(.orange)
                                    }
                                    Text("上限に達していても追加で1回投稿可能")
                                        .font(.system(size: isSmallScreen ? 8 : 11))
                                        .foregroundColor(.orange.opacity(0.8))
                                }
                                // 1分以内に投稿した場合のメッセージ
                                else if UserService.shared.dailyPostLimit == 10 {
                                    HStack(spacing: isSmallScreen ? 2 : 4) {
                                        Image(systemName: "bolt.fill")
                                            .font(.system(size: isSmallScreen ? 9 : 11))
                                            .foregroundColor(.yellow)
                                        Text("1分以内に投稿成功！")
                                            .font(.system(size: isSmallScreen ? 9 : 12))
                                            .foregroundColor(.yellow)
                                    }
                                } else {
                                    Text("次回は通知から1分以内に投稿しよう")
                                        .font(.system(size: isSmallScreen ? 9 : 12))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, isSmallScreen ? 12 : 20)
                        .padding(.vertical, isSmallScreen ? 8 : 14)
                        .background(
                            RoundedRectangle(cornerRadius: isSmallScreen ? 12 : 16)
                                .fill(Color.black.opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: isSmallScreen ? 12 : 16)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                                )
                        )
                        .padding(.horizontal, isSmallScreen ? 16 : 20)
                        .padding(.top, isSmallScreen ? 50 : 70)
                    }
                    
                    // 感情レベルの縦表示UI（見やすいデザイン）
                    VStack(spacing: isSmallScreen ? 16 : 40) {
                        // 現在の感情レベル表示（大きく強調）
                        VStack(spacing: isSmallScreen ? 8 : 16) {
                            // 大きな絵文字表示
                            Text(emotionEmoji)
                                .font(.system(size: isSmallScreen ? 50 : 80))
                                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                                .frame(width: isSmallScreen ? 80 : 120, height: isSmallScreen ? 80 : 120)
                                .background(
                                    Circle()
                                        .fill(emotionColor.opacity(0.3))
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.5), lineWidth: isSmallScreen ? 2 : 3)
                                        )
                                )
                            
                            // 感情レベルテキスト（固定幅でレイアウトを安定化）
                            Text(emotionLevelText)
                                .font(.system(size: isSmallScreen ? 18 : 28, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 3)
                                .frame(width: isSmallScreen ? 140 : 200)
                                .padding(.horizontal, isSmallScreen ? 12 : 24)
                                .padding(.vertical, isSmallScreen ? 8 : 12)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.4))
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.white.opacity(0.3), lineWidth: isSmallScreen ? 1.5 : 2)
                                        )
                                )
                        }
                        
                        // 横スライダー（感情選択バー）
                        VStack(spacing: isSmallScreen ? 6 : 12) {
                            HStack(spacing: isSmallScreen ? 8 : 20) {
                                // 横スライダー
                                let sliderWidth: CGFloat = isSmallScreen ? min(260, geometry.size.width - 60) : 280
                                let sliderHeight: CGFloat = isSmallScreen ? 45.0 : 60.0
                                let markerSize: CGFloat = isSmallScreen ? 28.0 : 36.0
                                
                                ZStack(alignment: .center) {
                                    // 操作領域の背景（視覚的なガイド）
                                    RoundedRectangle(cornerRadius: isSmallScreen ? 10 : 12)
                                        .fill(Color.white.opacity(0.1))
                                        .frame(height: isSmallScreen ? 45 : 50)
                                    
                                    // 背景バー
                                    RoundedRectangle(cornerRadius: isSmallScreen ? 6 : 8)
                                        .fill(Color.white.opacity(0.3))
                                        .frame(height: isSmallScreen ? 6 : 8)
                                    
                                    // 現在位置のマーカー
                                    // UI表示: 左端が-5（とても悲しい）、右端が+5（とても嬉しい）
                                    // emotionLevel = -5の時、マーカーは左端に
                                    // emotionLevel = +5の時、マーカーは右端に
                                    // マーカーの中心位置を計算
                                    let markerHalf = markerSize / 2.0
                                    let markerCenterX = markerHalf + (CGFloat(emotionLevel.rawValue + 5) / 10.0) * (sliderWidth - markerSize)
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: markerSize, height: markerSize)
                                        .shadow(color: .black.opacity(0.3), radius: isSmallScreen ? 3 : 4)
                                        .offset(x: markerCenterX - sliderWidth / 2.0)
                                }
                                .frame(width: sliderWidth, height: sliderHeight)
                                .contentShape(Rectangle())
                                .highPriorityGesture(
                                    DragGesture(minimumDistance: 3)
                                        .onChanged { dragValue in
                                            // ドラッグ開始時の感情レベルを保存（初回のみ）
                                            if dragStartLevel == nil {
                                                dragStartLevel = emotionLevel.rawValue
                                            }
                                            
                                            guard let startLevel = dragStartLevel else { return }
                                            
                                            // ドラッグの移動量を取得（右方向が正、左方向が負）
                                            // translation.widthは右方向にドラッグすると正の値、左方向にドラッグすると負の値
                                            let translationX = dragValue.translation.width
                                            
                                            // スライダーの有効な幅（マーカーのサイズを考慮）
                                            let effectiveWidth = sliderWidth - markerSize
                                            
                                            // 移動量を感情レベルの変化量に変換
                                            // スライダーの全範囲（effectiveWidth）が感情レベルの全範囲（-5から+5、つまり10段階）に対応
                                            // 右方向にドラッグ（translationX > 0）→ 感情レベルが上がる（+方向）
                                            // 左方向にドラッグ（translationX < 0）→ 感情レベルが下がる（-方向）
                                            let levelChange = translationX / effectiveWidth * 10.0
                                            
                                            // 開始時の感情レベルに移動量を加算
                                            let newValue = Int(round(Double(startLevel) + levelChange))
                                            
                                            // 値を-5から+5の範囲に制限
                                            let clampedValue = max(-5, min(5, newValue))
                                            
                                            // 値が変わった時だけ更新
                                            if emotionLevel.rawValue != clampedValue {
                                                emotionLevel = EmotionLevel.clamped(clampedValue)
                                            }
                                        }
                                        .onEnded { _ in
                                            // ドラッグ終了時に開始位置をリセット
                                            dragStartLevel = nil
                                        }
                                )
                                .layoutPriority(1) // レイアウトの優先度を上げる
                                .clipped() // はみ出しを防ぐ
                            }
                                .padding(.horizontal, isSmallScreen ? 10 : 14)
                        }
                    }
                    .padding(.top, isSmallScreen ? 8 : 30)
                    
                    // 公開設定の選択
                    VStack(spacing: isSmallScreen ? 4 : 8) {
                        Picker("公開設定", selection: $isPublicPost) {
                            Text("誰でも見れる").tag(true)
                            Text("友達のみ").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, isSmallScreen ? 20 : 35)
                        
                        Text(isPublicPost ? "誰でもこの投稿を見ることができます" : "友達のみがこの投稿を見ることができます")
                            .font(.system(size: isSmallScreen ? 10 : 14))
                            .foregroundColor(.black.opacity(0.7))
                            .shadow(color: .white.opacity(0.3), radius: 1, x: 0, y: 0)
                            .padding(.horizontal, isSmallScreen ? 20 : 35)
                            .padding(.top, isSmallScreen ? 4 : 12)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.top, isSmallScreen ? 6 : 20)
                    .padding(.bottom, isSmallScreen ? 6 : 20)
                    
                    Spacer()
                }
                .padding(.bottom, 20)
                
                // 下部のボタンエリアをZStackの最下層に固定配置
                VStack {
                    Spacer()
                    
                    VStack(spacing: 0) {
                        // 固定のボタンエリア（常に表示）
                        VStack(spacing: isSmallScreen ? 8 : 16) {
                            // 投稿ボタン
                            Button(action: {
                                // コメント入力モーダルを表示（誰でも見れる・友達のみ両方に対応）
                                showCommentModal = true
                            }) {
                                HStack(spacing: isSmallScreen ? 6 : 10) {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(isSmallScreen ? 0.7 : 0.9)
                                    } else {
                                        Image(systemName: "paperplane.fill")
                                            .font(.system(size: isSmallScreen ? 14 : 18))
                                    }
                                    Text(isLoading ? "投稿中..." : "投稿する")
                                        .font(.system(size: isSmallScreen ? 14 : 18, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, isSmallScreen ? 12 : 16)
                                .background(
                                    Capsule()
                                        .fill(Color.blue.opacity(0.8))
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.white.opacity(0.3), lineWidth: isSmallScreen ? 1.5 : 2)
                                        )
                                )
                                .shadow(color: .black.opacity(0.3), radius: isSmallScreen ? 6 : 8, x: 0, y: isSmallScreen ? 3 : 4)
                            }
                            .disabled(isLoading)
                            .padding(.horizontal, isSmallScreen ? 16 : 24)
                            
                            // 自分の投稿履歴ボタン
                            Button(action: {
                                showMyPostsHistory = true
                            }) {
                                HStack(spacing: isSmallScreen ? 5 : 8) {
                                    Image(systemName: "clock.fill")
                                        .font(.system(size: isSmallScreen ? 12 : 16))
                                    Text("履歴")
                                        .font(.system(size: isSmallScreen ? 12 : 16, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, isSmallScreen ? 16 : 24)
                                .padding(.vertical, isSmallScreen ? 8 : 12)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(25)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 25)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                                )
                            }
                        }
                        .padding(.horizontal, isSmallScreen ? 16 : 24)
                        .padding(.top, isSmallScreen ? 8 : 16)
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, isSmallScreen ? 4 : 8) + (isSmallScreen ? 20 : 40))
                    }
                    .background(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                emotionColor.opacity(0.3)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .background(background)
            .ignoresSafeArea()
        }
        .scrollDisabled(true) // GeometryReader全体のスクロールを無効化
        .sheet(isPresented: $showMyPostsHistory) {
            MyPostsHistoryView(posts: myPosts)
        }
        .sheet(isPresented: $showCommentModal) {
            CommentInputModal(
                comment: $comment,
                onPost: {
                    showCommentModal = false
                    submit()
                },
                onCancel: {
                    showCommentModal = false
                    comment = ""
                }
            )
        }
        .onChange(of: showMyPostsHistory) { oldValue, newValue in
            if newValue {
                Task {
                    await loadMyPosts()
                }
            }
        }
        .task {
            locationService.requestPermission()
            // 管理者が付与した投稿可能回数ボーナスを同期
            try? await firestoreService.loadCurrentUserProfile()
            await loadMyPosts()
        }
        .alert("スポットボーナス獲得！", isPresented: $showSpotBonus) {
            Button("OK") {
                showSpotBonus = false
            }
        } message: {
            Text("経験値+20と投稿回数3回分のボーナスを獲得しました！")
        }
        .onAppear {
            // 位置情報を取得してスポット判定
            Task {
                await checkNearbySpot()
            }
            
            // 通知ボーナスの残り時間を更新
            updateNotificationBonusTime()
            
            // タイマーを開始（1秒ごとに残り時間を更新）
            bonusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                updateNotificationBonusTime()
            }
        }
        .onDisappear {
            // タイマーを停止
            bonusTimer?.invalidate()
            bonusTimer = nil
        }
    }

    private var background: some View {
        let base = emotionColor
        let darker = base.opacity(0.85)
        return LinearGradient(
            colors: [darker, base],
            startPoint: .top,
            endPoint: .bottom
        )
        .animation(.easeInOut(duration: 0.2), value: emotionLevel.rawValue)
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

    private func submit() {
        guard !isLoading else { return }
        
        // 投稿回数制限をチェック
        guard UserService.shared.canPost() else {
            let limit = UserService.shared.dailyPostLimit
            let count = UserService.shared.todayPostCount
            errorMessage = "今日の投稿回数制限に達しました（\(count)/\(limit)回）。\n通知が来てから1分以内に投稿すると、上限に達していても追加で1回投稿できます。"
            return
        }
        
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                // 位置情報を取得（確実に取得するため、更新を開始してから待機）
                locationService.startUpdatingLocation()
                
                // 位置情報が取得できるまで待つ（最大3秒）
                var location: CLLocation?
                for _ in 0..<30 {
                    location = await locationService.getCurrentLocation()
                    if location != nil {
                        break
                    }
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒待つ
                }
                
                locationService.stopUpdatingLocation()
                
                guard let location = location else {
                    await MainActor.run {
                        errorMessage = "位置情報を取得できませんでした。設定で位置情報の許可を確認してください。"
                        isLoading = false
                    }
                    return
                }
                
                let latitude = location.coordinate.latitude
                let longitude = location.coordinate.longitude
                
                // デバッグ用：位置情報をログに出力
                print("投稿位置: 緯度 \(latitude), 経度 \(longitude)")
                
                // スポット判定（投稿前にチェック）
                let spot = try? await firestoreService.findNearestSpot(latitude: latitude, longitude: longitude)
                await MainActor.run {
                    nearbySpot = spot
                }
                
                // 投稿を保存
                let gotSpotBonus = try await postUseCase.createPost(
                    level: emotionLevel.rawValue,
                    coordinate: CoreCoordinate(latitude: latitude, longitude: longitude),
                    comment: !comment.isEmpty ? comment : nil,
                    isPublicPost: isPublicPost,
                    isMistCleanup: false
                )
                
                // 投稿回数を記録
                UserService.shared.recordPost()
                
                // スポットボーナスがもらえた場合、通知を表示
                if gotSpotBonus {
                    await MainActor.run {
                        showSpotBonus = true
                    }
                }
                
                // 投稿作成を通知（プロフィール画面で連続投稿日数を更新するため）
                NotificationCenter.default.post(name: NSNotification.Name("PostCreated"), object: nil)
                
                // Firestoreから最新データを再取得
                await loadMyPosts()
                
                // 最新の投稿を取得してIDを取得
                let latestPosts = try await firestoreService.fetchMyPosts()
                let latestPost = latestPosts.first
                
                await MainActor.run {
                    isLoading = false
                    
                    // 投稿が成功したら地図タブに移動して投稿位置を表示
                    if let latestPost = latestPost,
                       let postLatitude = latestPost.latitude,
                       let postLongitude = latestPost.longitude {
                        allowNextMapJump = true
                        targetLocation = CLLocationCoordinate2D(latitude: postLatitude, longitude: postLongitude)
                        targetPostID = latestPost.id
                        selectedTab = 2 // 地図タブに切り替え
                        
                        // コメントをリセット
                        comment = ""
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "エラー: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func loadMyPosts() async {
        do {
            let fetchedPosts = try await firestoreService.fetchMyPosts()
            await MainActor.run {
                myPosts = fetchedPosts
            }
        } catch {
            await MainActor.run {
                errorMessage = "履歴の取得に失敗しました: \(error.localizedDescription)"
            }
        }
    }

    // 通知ボーナスの残り時間を更新
    private func updateNotificationBonusTime() {
        notificationBonusTimeRemaining = UserService.shared.notificationBonusTimeRemaining()
    }
    
    // 近くのスポットをチェック
    private func checkNearbySpot() async {
        locationService.startUpdatingLocation()

        // 位置情報が取得できるまで待つ（最大3秒）
        var location: CLLocation?
        for _ in 0..<30 {
            location = await locationService.getCurrentLocation()
            if location != nil {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒待つ
        }

        locationService.stopUpdatingLocation()

        if let location = location {
            let spot = try? await firestoreService.findNearestSpot(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            await MainActor.run {
                nearbySpot = spot
            }
        }
    }
}

// MARK: - CommentInputModal
struct CommentInputModal: View {
    @Binding var comment: String
    let onPost: () -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    @State private var errorMessage: String?
    
    private let maxLength = 20 // 最大文字数
    
    // 不適切な言葉のリスト（誤魔化し入力も考慮して広めに検知）
    private let inappropriateWords = [
        "死ね", "しね", "氏ね", "殺す", "ころす", "殺害", "自殺",
        "消えろ", "消え失せろ", "ぶっころ", "ぶっ殺",
        "バカ", "ばか", "馬鹿", "アホ", "あほ", "間抜け", "クズ", "くず", "ゴミ",
        "うざい", "キモ", "きも", "気持ち悪",
        "クソ", "くそ", "糞", "ちんかす", "まんこ", "ちんこ",
        "fuck", "fxxk", "shit", "bitch", "die", "kill"
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("コメントを入力してください")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.top, 20)
                
                VStack(alignment: .trailing, spacing: 8) {
                    TextField("一言コメントを入力...", text: $comment, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(16)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .lineLimit(3...6)
                    .focused($isTextFieldFocused)
                    .onChange(of: comment) { oldValue, newValue in
                        // 20文字を超える場合は自動的に20文字に戻す
                        if newValue.count > maxLength {
                            comment = String(newValue.prefix(maxLength))
                        }
                        // 入力中はエラーメッセージをクリア
                        errorMessage = nil
                    }
                    .onAppear {
                        // モーダルが表示されたら自動的にキーボードを表示
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isTextFieldFocused = true
                        }
                    }
                    
                    // 文字数カウンター
                    Text("\(comment.count)/\(maxLength)")
                        .font(.caption)
                        .foregroundColor(comment.count >= maxLength ? .red : .secondary)
                        .padding(.trailing, 4)
                }
                
                // エラーメッセージ
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button(action: {
                        onCancel()
                        dismiss()
                    }) {
                        Text("キャンセル")
                            .font(.headline)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                    }
                    
                    Button(action: {
                        if validateComment() {
                            onPost()
                            dismiss()
                        }
                    }) {
                        Text("投稿する")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func validateComment() -> Bool {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 空白のみの場合はOK（コメントなしで投稿できる）
        if trimmed.isEmpty {
            return true
        }
        
        // 不適切な言葉をチェック（記号/空白混ぜも検知）
        let normalized = normalizeForModeration(comment)
        for word in inappropriateWords {
            let normalizedWord = normalizeForModeration(word)
            if normalized.contains(normalizedWord) {
                errorMessage = "不適切な言葉が含まれています"
                return false
            }
        }
        
        return true
    }

    private func normalizeForModeration(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        let katakanaUnified = folded.applyingTransform(.hiraganaToKatakana, reverse: false) ?? folded
        let noSeparators = katakanaUnified.replacingOccurrences(
            of: "[\\s\\p{P}\\p{S}ーｰ＿_]+",
            with: "",
            options: .regularExpression
        )
        return noSeparators.lowercased()
    }
}

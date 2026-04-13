import SwiftUI
import MapKit
import CoreLocation
import UIKit
import Combine
import FirebaseFirestore

// ============================================
// EmotionMapView: 地図表示画面
// ============================================
// このファイルの役割：
// - 地図上に投稿をピンで表示
// - 30個以上の投稿が密集している場所をクラスター化（まとめて表示）
// - モヤイベント（黒い雲）を表示
// - 観光スポットを表示
// - 表示モード切り替え（みんな/友達のみ）
// ============================================

// 地図ピン用：観光スポットの画像をインターネットから読み込んで保存
private final class SpotImageCache: ObservableObject {
    @Published private(set) var loadedImages: [String: UIImage] = [:]
    
    func image(for spotName: String) -> UIImage? {
        loadedImages[spotName]
    }
    
    func preload(spotNames: [String], urlForName: (String) -> String?) {
        for name in spotNames {
            guard loadedImages[name] == nil,
                  let urlString = urlForName(name),
                  let url = URL(string: urlString) else { continue }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let self = self, let data = data, let img = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    var next = self.loadedImages
                    next[name] = img
                    self.loadedImages = next
                }
            }.resume()
        }
    }
}

// 地図の表示モード
enum MapMode: String, CaseIterable {
    case everyone = "みんな+友達"  // 全員の投稿を表示
    case friendsOnly = "友達のみ"  // 友達の投稿だけ表示
}

struct EmotionMapView: View {
    // サービス系（データ取得・位置情報）
    @StateObject private var locationService = LocationService()  // 位置情報取得
    private let firestoreService = FirestoreService()  // データベース操作
    private let timelineUseCase = TimelineUseCase(
        timelineRepository: IOSTimelineRepository()
    )
    private let mistUseCase = MistUseCase(
        mistRepository: IOSMistEventRepository()
    )
    
    // 他の画面から渡される変数（通知からの遷移など）
    @Binding var targetLocation: CLLocationCoordinate2D?  // 移動先の座標
    @Binding var targetPostID: UUID?  // 表示する投稿のID
    @Binding var allowNextMapJump: Bool  // 地図移動の許可フラグ
    
    // 地図上に表示するデータ
    @State private var posts: [EmotionPost] = []  // 投稿リスト
    @State private var postClusters: [PostCluster] = []  // 投稿クラスター（30個以上の集まり）
    @State private var selectedCluster: PostCluster?  // 選択中のクラスター
    @State private var mapMode: MapMode = .everyone  // 表示モード
    
    // ズームレベルの制限値
    private let minSpan: Double = 0.0001  // 最小ズーム（これ以上近づけない）
    private let hidePostsSpanThreshold: Double = 0.02  // 投稿を非表示にする閾値
    private let clusteringThreshold: Double = 0.003  // クラスター表示の閾値（これ以上ズームアウトでクラスター化）
    
    @State private var cameraPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503), // 東京
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    )
    @State private var selectedPost: EmotionPost?
    @State private var isLoading = false
    @State private var userLocation: CLLocationCoordinate2D?
    @State private var mistEvents: [MistEvent] = []
    @State private var spots: [Spot] = []
    @StateObject private var spotImageCache = SpotImageCache()
    @State private var selectedSpot: Spot?
    @State private var selectedMistEvent: MistEvent?
    @State private var currentSpan: Double = 0.1
    @State private var didSetInitialCamera = false
    @State private var lastMapCenter: CLLocationCoordinate2D?
    @State private var now = Date()
    @State private var showMistEventTutorial = false
    @State private var hasCheckedMistEventTutorial = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var targetLocationKey: String {
        if let location = targetLocation {
            return "\(location.latitude),\(location.longitude)"
        }
        return "nil"
    }

    init(
        targetLocation: Binding<CLLocationCoordinate2D?> = .constant(nil),
        targetPostID: Binding<UUID?> = .constant(nil),
        allowNextMapJump: Binding<Bool> = .constant(false)
    ) {
        _targetLocation = targetLocation
        _targetPostID = targetPostID
        _allowNextMapJump = allowNextMapJump
    }
    
    @ViewBuilder
    private var mapContent: some View {
        Map(position: $cameraPosition) {
            ForEach(spots) { spot in
                Annotation(spot.name, coordinate: spot.coordinate) {
                    spotAnnotationView(for: spot)
                }
            }
            
            // ズームレベルに応じて表示を切り替え
            if currentSpan >= clusteringThreshold {
                // ズームアウト時：クラスターと個別投稿を両方表示
                ForEach(postClusters) { cluster in
                    Annotation("", coordinate: cluster.centerCoordinate) {
                        clusterAnnotationView(for: cluster)
                    }
                }
                
                ForEach(postsNotInClusters) { post in
                    Annotation(post.level.rawValue.description, coordinate: post.coordinate) {
                        postAnnotationView(for: post)
                    }
                }
            } else {
                // ズームイン時：すべての投稿を個別表示（クラスター化しない）
                ForEach(visiblePostsForMap) { post in
                    Annotation(post.level.rawValue.description, coordinate: post.coordinate) {
                        postAnnotationView(for: post)
                    }
                }
            }

            ForEach(mistEvents) { event in
                MapCircle(center: event.coordinate, radius: mistRadius(for: event) * 1000)
                    .foregroundStyle(.black.opacity(0.4))
                    .stroke(.black.opacity(0.6), lineWidth: 2)
                Annotation("", coordinate: event.coordinate) {
                    mistEventAnnotationView(for: event)
                }
            }
            
            if let coordinate = locationService.currentLocation?.coordinate {
                Annotation("", coordinate: coordinate) {
                    userLocationAnnotationView()
                }
            }
        }
    }
    
    @ViewBuilder
    private var configuredMapContent: some View {
        mapContent
            .ignoresSafeArea()
            .onReceive(timer) { value in
                now = value
            }
            .onAppear {
                handleMapAppear()
            }
            .onDisappear {
                locationService.stopUpdatingLocation()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                handleMapCameraChange(context)
            }
            .onChange(of: targetLocationKey) { _, _ in
                handleTargetLocationChange()
            }
    }
    
    private var overlayControls: some View {
        VStack {
            topControls
            locationButton
            Spacer()
        }
    }
    
    private var topControls: some View {
        VStack(spacing: 8) {
            modePicker
            mistEventBanner
            mistEventsList
            Spacer()
        }
    }
    
    private var modePicker: some View {
        Picker("表示モード", selection: $mapMode) {
            ForEach(MapMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 8)
        .onChange(of: mapMode) { oldValue, newValue in
            Task {
                await loadPosts()
                await loadMistEvents()
            }
        }
    }
    
    @ViewBuilder
    private var mistEventBanner: some View {
        if let mistEvent = mistEvents.first {
            Button(action: {
                jumpToMistEvent(mistEvent)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "cloud.fill")
                        .foregroundColor(.black)
                    Text("イベント発生中")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("タップで移動")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(mistEvent.prefectureName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.top, 6)
        }
    }
    
    @ViewBuilder
    private var mistEventsList: some View {
        if !mistEvents.isEmpty {
            VStack(spacing: 8) {
                ForEach(mistEvents) { event in
                    VStack(spacing: 4) {
                        HStack {
                            Image(systemName: "cloud.fill")
                                .foregroundColor(.black)
                            Text("\(event.prefectureName)でモヤ発生中")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("HP: \(event.currentHP)/\(event.maxHP)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Spacer()
                            Text("😊 \(event.happyPostCount)/5")
                                .font(.caption2)
                                .foregroundColor(event.happyPostCount >= 5 ? .green : .secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
        }
    }
    
    private var locationButton: some View {
        HStack {
            Spacer()
            VStack(spacing: 12) {
                Button(action: {
                    Task {
                        await updateToCurrentLocation()
                    }
                }) {
                    Image(systemName: "location.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
            }
            .padding()
        }
    }
    
    var body: some View {
        ZStack {
            configuredMapContent
            overlayControls
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
        .sheet(item: $selectedSpot) { spot in
            SpotDetailSheet(spot: spot, spotImageCache: spotImageCache)
        }
        .sheet(item: $selectedMistEvent) { event in
            MistEventPostSheet(
                event: event,
                onPosted: {
                    await loadMistEvents()
                }
            )
        }
        .sheet(isPresented: $showMistEventTutorial) {
            MistEventTutorialView(isPresented: $showMistEventTutorial)
        }
        .sheet(item: $selectedCluster) { cluster in
            ClusterPostListSheet(cluster: cluster, onSelectPost: { post in
                selectedCluster = nil
                selectedPost = post
            })
        }
        .onChange(of: mistEvents) { _, newEvents in
            checkAndShowMistEventTutorial(newEvents)
        }
        .onChange(of: posts) { _, newPosts in
            updateClusters()
        }
        .onChange(of: currentSpan) { _, _ in
            updateClusters()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PostCreated"))) { _ in
            // 投稿が作成されたときにモヤイベントとスポットを更新
            Task {
                await loadMistEvents()
                await loadSpots()
            }
        }
        .onChange(of: targetPostID) { _, newPostID in
            // 通知から投稿を開く場合、自動的に投稿詳細を表示
            if let postID = newPostID {
                print("📍 targetPostIDが設定されました: \(postID.uuidString)")
                Task {
                    // 少し遅延してマップが表示されるのを待つ
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                    
                    // 投稿を検索して開く
                    if let post = posts.first(where: { $0.id == postID }) {
                        print("✅ 投稿を見つけました - 詳細を開きます")
                        await MainActor.run {
                            selectedPost = post
                        }
                        // targetPostIDをリセット
                        targetPostID = nil
                    } else {
                        print("⚠️ 投稿が見つかりませんでした - 再読み込みします")
                        // 投稿が見つからない場合は再読み込み
                        await loadPosts()
                        
                        // 再度検索
                        if let post = posts.first(where: { $0.id == postID }) {
                            print("✅ 再読み込み後に投稿を見つけました")
                            await MainActor.run {
                                selectedPost = post
                            }
                        } else {
                            print("❌ 再読み込み後も投稿が見つかりませんでした")
                        }
                        targetPostID = nil
                    }
                }
            }
        }
    }
    
    private var postsWithLocation: [EmotionPost] {
        posts.filter { post in
            post.latitude != nil && post.longitude != nil && !post.isMistCleanup
        }
    }

    // モヤ範囲内にいる間は、地図上で他ユーザーの投稿を非表示にする
    private var visiblePostsForMap: [EmotionPost] {
        guard let userCoordinate = locationService.currentLocation?.coordinate else {
            return postsWithLocation
        }

        let isInsideMist = mistEvents.contains { event in
            isInsideVisibleMistArea(
                userCoordinate: userCoordinate,
                event: event
            )
        }

        guard isInsideMist else {
            return postsWithLocation
        }

        let currentUserID = UserService.shared.currentUserID
        return postsWithLocation.filter { $0.authorID == currentUserID }
    }

    // 地図上で見えている黒いモヤ範囲（可視半径）に入っているか判定
    private func isInsideVisibleMistArea(userCoordinate: CLLocationCoordinate2D, event: MistEvent) -> Bool {
        let userLocation = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        let eventLocation = CLLocation(latitude: event.centerLatitude, longitude: event.centerLongitude)
        let distanceKm = userLocation.distance(from: eventLocation) / 1000.0
        return distanceKm <= mistRadius(for: event)
    }
    
    // クラスターに含まれていない投稿（個別表示用）
    private var postsNotInClusters: [EmotionPost] {
        // クラスター内の全投稿IDを収集
        let clusteredPostIDs = Set(postClusters.flatMap { $0.posts.map { $0.id } })
        
        // クラスターに含まれていない投稿のみを返す
        return visiblePostsForMap.filter { !clusteredPostIDs.contains($0.id) }
    }

    @ViewBuilder
    private func spotAnnotationView(for spot: Spot) -> some View {
        ZStack {
            if let image = spotImage(for: spot) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.2), radius: 4)
            } else {
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 42, height: 42)
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title)
            }
        }
        .onTapGesture {
            selectedSpot = spot
        }
    }

    @ViewBuilder
    private func postAnnotationView(for post: EmotionPost) -> some View {
        VStack(spacing: 4) {
            if let comment = post.comment, !comment.isEmpty {
                Text(formatCommentForMap(comment))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    .lineLimit(20)
                    .frame(maxWidth: 200)
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            }

            EmotionPin(post: post)

            if post.needsSupport && post.supportCount > 0 {
                HStack(spacing: 4) {
                    Text(post.isSadEmotion ? "💪" : "🤗")
                        .font(.system(size: 12))
                    Text("\(post.supportCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(post.isSadEmotion ? Color.orange.opacity(0.8) : Color.yellow.opacity(0.8))
                .cornerRadius(8)
            }
        }
        .scaleEffect(postScale)
        .onTapGesture {
            selectedPost = post
        }
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
    
    private func mistEventAnnotationView(for event: MistEvent) -> some View {
        Circle()
            .fill(Color.clear)
            .frame(width: mistTapSize(for: event), height: mistTapSize(for: event))
            .contentShape(Circle())
            .onTapGesture {
                selectedMistEvent = event
            }
    }
    
    @ViewBuilder
    private func clusterAnnotationView(for cluster: PostCluster) -> some View {
        ZStack {
            // 背景円
            Circle()
                .fill(clusterBackgroundColor(for: cluster))
                .frame(width: clusterSize(for: cluster), height: clusterSize(for: cluster))
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            
            // 投稿数
            VStack(spacing: 2) {
                Text("\(cluster.postCount)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Text("件")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .onTapGesture {
            selectedCluster = cluster
        }
    }
    
    private func clusterBackgroundColor(for cluster: PostCluster) -> Color {
        let avgLevel = cluster.averageLevel
        if avgLevel > 2 {
            return Color.green.opacity(0.8)
        } else if avgLevel > 0 {
            return Color.yellow.opacity(0.8)
        } else if avgLevel > -2 {
            return Color.orange.opacity(0.8)
        } else {
            return Color.red.opacity(0.8)
        }
    }
    
    private func clusterSize(for cluster: PostCluster) -> CGFloat {
        // 投稿数に応じてサイズを調整（最小50、最大100）
        let baseSize: CGFloat = 50
        let additionalSize = min(CGFloat(cluster.postCount) * 3, 50)
        return baseSize + additionalSize
    }

    // MapCircle には直接ジェスチャーを付けられないため、タップ判定は Annotation で行う
    
    // コメントを10行ごとに改行して、最大20行まで表示するようにフォーマット
    private func formatCommentForMap(_ comment: String) -> String {
        let charactersPerLine = 10 // 1行あたりの文字数
        let maxLines = 20 // 最大行数
        
        var formattedComment = ""
        var currentLine = ""
        var lineCount = 0
        
        // 文字列を1文字ずつ処理
        for char in comment {
            currentLine.append(char)
            
            // 10文字に達したら改行
            if currentLine.count >= charactersPerLine {
                formattedComment += currentLine + "\n"
                currentLine = ""
                lineCount += 1
                
                // 20行に達したら終了
                if lineCount >= maxLines {
                    break
                }
            }
        }
        
        // 残りの文字を追加
        if !currentLine.isEmpty && lineCount < maxLines {
            formattedComment += currentLine
        }
        
        // 20行を超えた場合は省略記号を追加
        if lineCount >= maxLines && comment.count > charactersPerLine * maxLines {
            formattedComment += "..."
        }
        
        return formattedComment
    }

    private func spotImage(for spot: Spot) -> UIImage? {
        // 地図で写真表示を許可していないスポットは画像を出さない
        guard isSpotPhotoEnabled(spot.name) else {
            return nil
        }
        
        // キャッシュから画像を取得（URL画像）
        if let cachedImage = spotImageCache.image(for: spot.name) {
            return cachedImage
        }
        
        // URLがある場合はキャッシュ待ち（まだプリロード中）
        if spotImageURL(for: spot.name) != nil {
            return nil
        }
        
        // URLがない場合、ローカルアセットを試す
        return UIImage(named: spotImageName(for: spot.name))
    }
    
    private func loadPosts() async {
        isLoading = true
        do {
            let includeOnlyFriends = mapMode == .friendsOnly
            let fetchedPosts = try await timelineUseCase.loadRecentPosts(lastHours: 24, friendsOnly: includeOnlyFriends)
            print("📍 投稿を取得しました: \(fetchedPosts.count)件")
            if let firstPost = fetchedPosts.first {
                print("📍 最初の投稿: ID=\(firstPost.id.uuidString), 応援数=\(firstPost.supportCount)")
            }
            await MainActor.run {
                // 位置情報がある投稿のみをフィルタリング
                posts = fetchedPosts.filter { post in
                    post.latitude != nil && post.longitude != nil && !post.isMistCleanup
                }
                print("📍 位置情報付き投稿: \(posts.count)件")
                
                // 初回のみ、許可がある場合は投稿位置へ移動
                if let firstPost = posts.first, userLocation == nil, !didSetInitialCamera, allowNextMapJump {
                    cameraPosition = .region(
                        MKCoordinateRegion(
                            center: firstPost.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                        )
                    )
                    didSetInitialCamera = true
                    allowNextMapJump = false
                }
            }
        } catch {
            print("❌ エラー: \(error.localizedDescription)")
        }
        isLoading = false
    }

    private func focusHomePrefectureIfNoPosts() async {
        guard posts.isEmpty else { return }
        guard let homePrefecture = UserService.shared.homePrefecture else { return }

        let center = homePrefecture.centerCoordinate
        await MainActor.run {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
                )
            )
            didSetInitialCamera = true
        }
    }
    
    private func loadPostsForRegion(centerLatitude: Double, centerLongitude: Double, span: MKCoordinateSpan? = nil) async {
        do {
            let includeOnlyFriends = mapMode == .friendsOnly
            
            // 地図のズームレベルに応じて読み込み範囲を動的に調整
            // spanが大きい（ズームアウト）ほど広い範囲を読み込む
            let radiusKm: Double
            if let span = span {
                // spanから半径を計算（より広範囲に表示）
                // latitudeDeltaとlongitudeDeltaの平均から半径を推定
                let avgSpan = (span.latitudeDelta + span.longitudeDelta) / 2.0
                // 1度 ≈ 111km として計算し、さらに余裕を持たせる（1.5倍）
                radiusKm = max(50.0, avgSpan * 111.0 * 1.5) // 最小50km、最大はspanに応じて拡大
            } else {
                // デフォルト値（ズームイン時）
                radiusKm = 10.0
            }
            
            // まずUseCase経由で読み込み、リージョンで絞り込む
            let recentPosts = try await timelineUseCase.loadRecentPosts(lastHours: 24, friendsOnly: includeOnlyFriends)
            let fetchedPosts = recentPosts.filter { post in
                guard let lat = post.latitude, let lon = post.longitude else { return false }
                let distance = calculateDistance(
                    lat1: centerLatitude, lon1: centerLongitude,
                    lat2: lat, lon2: lon
                )
                return distance <= radiusKm
            }
            await MainActor.run {
                // 位置情報がある投稿のみをフィルタリング
                posts = fetchedPosts.filter { post in
                    post.latitude != nil && post.longitude != nil && !post.isMistCleanup
                }
            }
        } catch {
            print("エラー: \(error.localizedDescription)")
        }
    }

    private func calculateDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let from = CLLocation(latitude: lat1, longitude: lon1)
        let to = CLLocation(latitude: lat2, longitude: lon2)
        return from.distance(from: to) / 1000.0
    }
    
    private func updateToCurrentLocation() async {
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
            await MainActor.run {
                userLocation = location.coordinate
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                    )
                )
                didSetInitialCamera = true
            }
            await loadPostsForRegion(centerLatitude: location.coordinate.latitude, centerLongitude: location.coordinate.longitude, span: nil)
        }
    }

    private func addTestMistEvent() {
        let center = lastMapCenter
            ?? userLocation
            ?? CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        Task {
            do {
                let event = MistEvent(
                    centerLatitude: center.latitude,
                    centerLongitude: center.longitude,
                    prefectureName: "テストイベント",
                    radius: 5.0,
                    currentHP: 150,
                    maxHP: 150
                )
                try await firestoreService.createTestMistEvent(event)
                await loadMistEvents()
            } catch {
                print("❌ テストモヤの作成に失敗: \(error.localizedDescription)")
            }
        }
    }

    private func mistRadius(for event: MistEvent) -> Double {
        // 判定側と同じ計算を使って、見た目と当たり判定の不一致を防ぐ
        event.activeRadius(at: now, growthPerMinuteKm: 0.1)
    }

    private func mistTapSize(for event: MistEvent) -> CGFloat {
        // モヤ表示半径に合わせて、ズームに応じたタップ領域を計算
        let radiusKm = mistRadius(for: event)
        let visibleKm = max(0.0001, currentSpan * 111.0) // 緯度差(度)→km 換算
        let screenWidth = UIScreen.main.bounds.width
        let diameterOnScreen = (radiusKm * 2.0 / visibleKm) * screenWidth
        return max(120, CGFloat(diameterOnScreen))
    }
    
    
    private func addSupport(postID: UUID, emoji: SupportEmoji) async {
        // EmotionDetailSheetから呼ばれた時は、既にFirestoreに保存済み
        // ここでは投稿一覧の再読み込みのみを行う
        print("📍 親のaddSupport呼び出し: postID=\(postID.uuidString)")
        
        // 通知を送信する前に投稿情報を取得
        let postBeforeUpdate = posts.first(where: { $0.id == postID })
        let isHappy = postBeforeUpdate?.isHappyEmotion ?? false
        
        // 即座に通知を送信（自分の投稿でない場合）
        // 注意: FirestoreService.addSupport内で既にcreateNotificationが呼ばれているため、
        // shouldSaveToFirestoreはfalseにして重複を避ける
        // ただし、アプリが開いている時にも通知を表示するために呼び出す
        if let post = postBeforeUpdate, post.authorID != UserService.shared.currentUserID {
            NotificationService.shared.sendImmediateSupportNotification(
                isHappy: isHappy,
                postID: post.id.uuidString,
                toUserID: post.authorID,
                shouldSaveToFirestore: false // FirestoreService.addSupportで既に保存済み
            )
        }
        
        // 投稿一覧を再読み込み
        print("📍 投稿一覧を再読み込み中...")
        await loadPosts()
        print("📍 投稿一覧の再読み込み完了: 全投稿数=\(posts.count)")
        
        // 選択中の投稿も更新（重要！）
        if let index = posts.firstIndex(where: { $0.id == postID }) {
            let updatedPost = posts[index]
            print("📍 selectedPostを更新: 応援数=\(updatedPost.supportCount), supports数=\(updatedPost.supports.count)")
            print("📍 更新後のsupports配列: \(updatedPost.supports.map { "\($0.userID): \($0.emoji.rawValue)" })")
            await MainActor.run {
                // 確実に更新するため、一度nilにしてから再設定
                let temp = updatedPost
                selectedPost = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    selectedPost = temp
                }
            }
        } else {
            print("⚠️ 選択中の投稿が投稿一覧に見つかりません")
            // 投稿が見つからない場合は、シートを閉じる
            await MainActor.run {
                selectedPost = nil
            }
        }
    }
    
    private func removeSupport(postID: UUID) async {
        // EmotionDetailSheetから呼ばれた時は、既にFirestoreから削除済み
        // ここでは投稿一覧の再読み込みのみを行う
        print("📍 親のremoveSupport呼び出し: postID=\(postID.uuidString)")
        
        // 投稿一覧を再読み込み
        await loadPosts()
        print("📍 投稿一覧の再読み込み完了: 全投稿数=\(posts.count)")
        
        // 選択中の投稿も更新
        if let index = posts.firstIndex(where: { $0.id == postID }) {
            let updatedPost = posts[index]
            print("📍 selectedPostを更新: 応援数=\(updatedPost.supportCount), supports数=\(updatedPost.supports.count)")
            await MainActor.run {
                // 確実に更新するため、一度nilにしてから再設定
                let temp = updatedPost
                selectedPost = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    selectedPost = temp
                }
            }
        } else {
            print("⚠️ 選択中の投稿が投稿一覧に見つかりません")
        }
    }

    private func jumpToMistEvent(_ event: MistEvent) {
        let location = event.coordinate
        let span = max(0.01, minSpan)
        cameraPosition = .region(
            MKCoordinateRegion(
                center: location,
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            )
        )
    }

    private var postScale: CGFloat {
        1.0
    }
    
    // モヤイベントを読み込む
    private func loadMistEvents() async {
        do {
            let events = try await mistUseCase.loadActiveEvents()
            await MainActor.run {
                self.mistEvents = events
            }
        } catch {
            print("モヤイベントの読み込みに失敗しました: \(error.localizedDescription)")
        }
    }
    
    // モヤイベントのチュートリアルを表示するかチェック
    private func checkAndShowMistEventTutorial(_ events: [MistEvent]) {
        guard !hasCheckedMistEventTutorial, !events.isEmpty else { return }
        hasCheckedMistEventTutorial = true
        let hasSeenTutorial = UserDefaults.standard.bool(forKey: "hasSeenMistEventTutorial")
        guard !hasSeenTutorial else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.showMistEventTutorial = true
        }
    }
    
    private func updateClusters() {
        // ズームアウト時のみクラスタリングを実行
        if currentSpan >= clusteringThreshold {
            // 20個以上の投稿が約30-300m以内に集まっている場合のみクラスター化される
            postClusters = PostClusterManager.clusterPosts(visiblePostsForMap, currentSpan: currentSpan, minClusterSize: 20)
        } else {
            // かなりズームインした時はクラスター化しない（すべて個別表示）
            postClusters = []
        }
    }
    
    private func handleMapAppear() {
        locationService.requestPermission()
        Task {
            await updateToCurrentLocation()
            locationService.startUpdatingLocation()
            await loadPosts()
            await focusHomePrefectureIfNoPosts()
            await loadMistEvents()
            await loadSpots()
        }
    }
    
    private func handleMapCameraChange(_ context: MapCameraUpdateContext) {
        let currentSpan = min(context.region.span.latitudeDelta, context.region.span.longitudeDelta)
        self.currentSpan = currentSpan
        lastMapCenter = context.region.center
        
        if currentSpan < minSpan {
            let clampedSpan = MKCoordinateSpan(latitudeDelta: minSpan, longitudeDelta: minSpan)
            let clampedRegion = MKCoordinateRegion(center: context.region.center, span: clampedSpan)
            DispatchQueue.main.async {
                cameraPosition = .region(clampedRegion)
            }
        } else {
            Task {
                if mapMode == .everyone {
                    await loadPosts()
                } else {
                    await loadPostsForRegion(
                        centerLatitude: context.region.center.latitude,
                        centerLongitude: context.region.center.longitude,
                        span: context.region.span
                    )
                }
                await loadMistEvents()
                await loadSpots()
            }
        }
    }
    
    private func handleTargetLocationChange() {
        guard let location = targetLocation else { return }
        guard allowNextMapJump else {
            DispatchQueue.main.async {
                targetLocation = nil
                targetPostID = nil
            }
            return
        }
        allowNextMapJump = false
        let span = max(0.01, minSpan)
        cameraPosition = .region(
            MKCoordinateRegion(
                center: location,
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            )
        )
        
        Task {
            await loadPostsForRegion(centerLatitude: location.latitude, centerLongitude: location.longitude, span: nil)
            
            if let postID = targetPostID,
               let post = posts.first(where: { $0.id == postID }) {
                await MainActor.run {
                    selectedPost = post
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            targetLocation = nil
            targetPostID = nil
        }
    }
    
    // スポットを読み込む
    private func loadSpots() async {
        do {
            let fetchedSpots = try await firestoreService.fetchActiveSpots()
            await MainActor.run {
                self.spots = fetchedSpots
                spotImageCache.preload(spotNames: fetchedSpots.map(\.name), urlForName: spotImageURL)
            }
        } catch {
            print("スポットの読み込みに失敗しました: \(error.localizedDescription)")
        }
    }
}

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
                .font(.system(size: 18))
        }
        .onAppear {
            startAnimation()
        }
        .onChange(of: post.supportCount) { oldValue, newValue in
            startAnimation()
        }
    }
    
    var baseSize: CGFloat {
        // 応援数に応じてピンのサイズを調整
        let supportMultiplier = min(CGFloat(post.supportCount) * 2.0, 20.0)
        return 36 + supportMultiplier
    }
    
    var pinColor: Color {
        let t = Double(post.level.rawValue + 5) / 10
        let hue = 0.62 - 0.62 * t
        return Color(hue: hue, saturation: 0.7, brightness: 0.9)
    }
    
    var emoji: String {
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
    
    func startAnimation() {
        // パルスアニメーション
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            animationScale = post.supportCount > 0 ? 1.1 : 1.0
        }
        
        // 滲みアニメーション（応援数がある場合のみ）
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

private struct EmotionDetailSheet: View {
    let post: EmotionPost
    let onSupport: (EmotionPost, SupportEmoji) async -> Void
    let onRemoveSupport: (EmotionPost) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var currentPost: EmotionPost
    @State private var isSupporting = false
    @State private var showSupportPicker = false
    @State private var showUserProfile = false
    @State private var showReportPost = false
    @State private var comments: [PostComment] = []
    @State private var newCommentText = ""
    @State private var isLoadingComments = false
    @State private var isPostingComment = false
    @State private var isFriend = false
    @State private var commentError: String?
    @State private var supportError: String?
    @State private var replyToComment: PostComment? // 返信先のコメント
    @State private var isReplyMode = false // 返信モードかどうか
    
    let firestoreService = FirestoreService()
    
    init(post: EmotionPost, 
         onSupport: @escaping (EmotionPost, SupportEmoji) async -> Void,
         onRemoveSupport: @escaping (EmotionPost) async -> Void) {
        self.post = post
        self.onSupport = onSupport
        self.onRemoveSupport = onRemoveSupport
        _currentPost = State(initialValue: post)
    }
    
    var body: some View {
        ScrollView {
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
                    
                    // 投稿者のコメント表示（友達のみの投稿でコメントがある場合）
                    if let comment = currentPost.comment, !comment.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("投稿者のコメント")
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
                
                // 応援/共感セクション（自分の投稿でない場合のみ表示）
                if !currentPost.isMyPost {
                    VStack(spacing: 16) {
                        Text(currentPost.isSadEmotion ? "応援メッセージ" : "共感メッセージ")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        // エラーメッセージ
                        if let error = supportError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal)
                        }
                        
                        // 応援絵文字の表示
                        if currentPost.supportCount > 0 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(Array(currentPost.supportEmojiCounts.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { emoji in
                                        let count = currentPost.supportEmojiCounts[emoji] ?? 0
                                        HStack(spacing: 4) {
                                            Text(emoji.rawValue)
                                                .font(.title2)
                                            Text("\(count)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.orange.opacity(0.1))
                                        .cornerRadius(20)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // 応援/共感ボタン
                        if currentPost.hasSupportFromCurrentUser {
                            Button(action: {
                                Task {
                                    await handleRemoveSupport()
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Text(currentPost.isSadEmotion ? "応援を取り消す" : "共感を取り消す")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(25)
                            }
                            .disabled(isSupporting)
                        } else {
                            Button(action: {
                                showSupportPicker = true
                            }) {
                                HStack(spacing: 8) {
                                    Text(currentPost.isSadEmotion ? "💪" : "🤗")
                                        .font(.title2)
                                    Text(currentPost.isSadEmotion ? "応援する" : "共感する")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(currentPost.isSadEmotion ? Color.orange.opacity(0.2) : Color.yellow.opacity(0.2))
                                .cornerRadius(25)
                            }
                            .disabled(isSupporting)
                        }
                        
                        if currentPost.supportCount > 0 {
                            Text(currentPost.isSadEmotion ? "\(currentPost.supportCount)人が応援しています" : "\(currentPost.supportCount)人が共感しています")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.bottom, 12)
                }
                
                // 投稿者のプロフィールを開くボタン（自分の投稿でない場合）
                if currentPost.authorID != nil,
                   !currentPost.isMyPost {
                    VStack(spacing: 12) {
                        Button(action: {
                            showUserProfile = true
                        }) {
                            HStack {
                                Image(systemName: "person.circle")
                                Text("プロフィールを見る")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(20)
                        }
                        
                        Button(action: {
                            showReportPost = true
                        }) {
                            HStack {
                                Image(systemName: "flag")
                                Text("投稿を報告")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(20)
                        }
                    }
                    .padding(.bottom, 12)
                }
                
                // コメントセクション（すべての投稿で表示）
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                        .padding(.vertical, 8)
                
                    HStack {
                        Text("コメント")
                            .font(.headline)
                        Spacer()
                        Text("\(comments.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    
                    // コメント一覧（誰でも見れる）
                    if isLoadingComments {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding()
                    } else if comments.isEmpty {
                        Text("まだコメントがありません")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(comments.filter { $0.replyToCommentID == nil }) { comment in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(comment.userName)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(formatCommentDate(comment.createdAt))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    
                                    // 投稿者は返信可能
                                    if currentPost.isMyPost {
                                        Button(action: {
                                            replyToComment = comment
                                            isReplyMode = true
                                        }) {
                                            Image(systemName: "arrowshape.turn.up.left.fill")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    
                                    // 自分のコメントは削除可能
                                    if comment.userID == UserService.shared.currentUserID {
                                        Button(action: {
                                            Task {
                                                await deleteComment(commentID: comment.id)
                                            }
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.caption)
                                                .foregroundColor(.red)
                                        }
                                    }
                                }
                                
                                Text(comment.comment)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                // このコメントへの返信を表示
                                let replies = comments.filter { $0.replyToCommentID == comment.id }
                                if !replies.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(replies) { reply in
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack {
                                                    Image(systemName: "arrowshape.turn.up.left.fill")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                    Text(reply.userName)
                                                        .font(.caption)
                                                        .fontWeight(.semibold)
                                                    
                                                    // 投稿者マーク
                                                    if reply.userID == currentPost.authorID {
                                                        Image(systemName: "crown.fill")
                                                            .font(.system(size: 10))
                                                            .foregroundColor(.orange)
                                                    }
                                                    
                                                    Text("→ \(reply.replyToUserName ?? "")")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                    Spacer()
                                                    Text(formatCommentDate(reply.createdAt))
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                    
                                                    // 元のコメントが自分で、返信が投稿者からの場合は返信可能
                                                    if comment.userID == UserService.shared.currentUserID && 
                                                       reply.userID == currentPost.authorID &&
                                                       reply.userID != UserService.shared.currentUserID {
                                                        Button(action: {
                                                            replyToComment = reply
                                                            isReplyMode = true
                                                        }) {
                                                            Image(systemName: "arrowshape.turn.up.left.fill")
                                                                .font(.caption2)
                                                                .foregroundColor(.blue)
                                                        }
                                                    }
                                                    
                                                    // 自分の返信は削除可能
                                                    if reply.userID == UserService.shared.currentUserID {
                                                        Button(action: {
                                                            Task {
                                                                await deleteComment(commentID: reply.id)
                                                            }
                                                        }) {
                                                            Image(systemName: "trash")
                                                                .font(.caption2)
                                                                .foregroundColor(.red)
                                                        }
                                                    }
                                                }
                                                
                                                Text(reply.comment)
                                                    .font(.caption)
                                                    .foregroundColor(.primary)
                                            }
                                            .padding(8)
                                            .background(Color.orange.opacity(0.05))
                                            .cornerRadius(8)
                                        }
                                    }
                                    .padding(.leading, 16)
                                    .padding(.top, 4)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(12)
                        }
                    }
                    
                    // コメント入力欄（自分の投稿または友達の投稿のみ）
                    if currentPost.isMyPost || isFriend {
                        VStack(spacing: 8) {
                            // 返信モード表示
                            if isReplyMode, let replyTo = replyToComment {
                                HStack {
                                    Image(systemName: "arrowshape.turn.up.left.fill")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    Text("\(replyTo.userName)さんに返信")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    Spacer()
                                    Button(action: {
                                        isReplyMode = false
                                        replyToComment = nil
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            }
                            
                            if let error = commentError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            
                            HStack(spacing: 12) {
                                TextField(isReplyMode ? "返信を入力..." : "コメントを入力...", text: $newCommentText, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(1...4)
                                
                                Button(action: {
                                    Task {
                                        if isReplyMode {
                                            await postReply()
                                        } else {
                                            await postComment()
                                        }
                                    }
                                }) {
                                    if isPostingComment {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "paperplane.fill")
                                            .foregroundColor(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                                    }
                                }
                                .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPostingComment)
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        // 友達でない場合は、コメント投稿できないことを表示
                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("友達のみコメントを投稿できます")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.top, 8)
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
            }
        .sheet(isPresented: $showSupportPicker) {
            SupportEmojiPickerView(post: currentPost) { emoji in
                showSupportPicker = false
                Task {
                    await handleSupport(emoji: emoji)
                }
            }
        }
        .sheet(isPresented: $showUserProfile) {
            if let authorID = currentPost.authorID {
                NavigationView {
                    UserProfileView(userID: authorID)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("閉じる") {
                                    showUserProfile = false
                                }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showReportPost) {
            ReportPostView(postID: currentPost.id.uuidString)
        }
        .onAppear {
            currentPost = post
            print("📍 EmotionDetailSheet表示: postID=\(post.id.uuidString), 応援数=\(post.supportCount)")
            print("📍 投稿の詳細: authorID=\(post.authorID ?? "nil"), createdAt=\(post.createdAt)")
            
            // 友達チェックとコメント読み込み
            Task {
                await checkFriendship()
                // すべての投稿でコメントを読み込む（閲覧は誰でもOK）
                await loadComments()
            }
        }
        .onChange(of: post.id) { oldValue, newValue in
            currentPost = post
            print("📍 EmotionDetailSheet投稿ID変更: 応援数=\(post.supportCount)")
            
            // 投稿が変わったらコメントを再読み込み
            Task {
                await checkFriendship()
                // すべての投稿でコメントを読み込む（閲覧は誰でもOK）
                await loadComments()
            }
        }
        .onChange(of: post.supportCount) { oldValue, newValue in
            currentPost = post
            print("📍 EmotionDetailSheet応援数変更: \(oldValue) → \(newValue)")
        }
        .onChange(of: post.supports) { oldValue, newValue in
            print("📍 EmotionDetailSheet supports配列変更: \(oldValue.count) → \(newValue.count)")
            print("📍 変更前のcurrentPost.id: \(currentPost.id.uuidString)")
            print("📍 変更後のpost.id: \(post.id.uuidString)")
            currentPost = post
            print("📍 currentPostを更新しました: currentPost.id=\(currentPost.id.uuidString)")
        }
    }
    
    // 友達かどうかをチェック（新旧両バージョン対応）
    func checkFriendship() async {
        guard let authorID = currentPost.authorID,
              authorID != UserService.shared.currentUserID else {
            await MainActor.run {
                isFriend = false
            }
            print("📍 友達チェック: 自分の投稿 or 投稿者IDなし")
            return
        }
        
        do {
            let currentUserID = UserService.shared.currentUserID
            let db = Firestore.firestore()
            
            // 1. 新バージョン: friendshipsコレクションをチェック
            let userIDs = [currentUserID, authorID].sorted()
            let friendshipID = "\(userIDs[0])_\(userIDs[1])"
            
            let friendshipDoc = try await db.collection("friendships")
                .document(friendshipID)
                .getDocument()
            
            if friendshipDoc.exists {
                await MainActor.run {
                    isFriend = true
                }
                print("📍 友達チェック結果: 新バージョンのfriendshipsで友達を確認")
                return
            }
            
            // friendshipsコレクションでの従来の検索方法（userID1/userID2フィールド）
            let friendship1 = try await db.collection("friendships")
                .whereField("userID1", isEqualTo: currentUserID)
                .whereField("userID2", isEqualTo: authorID)
                .limit(to: 1)
                .getDocuments()
            
            if !friendship1.documents.isEmpty {
                await MainActor.run {
                    isFriend = true
                }
                print("📍 友達チェック結果: friendshipsコレクション（userID1/userID2）で友達を確認")
                return
            }
            
            let friendship2 = try await db.collection("friendships")
                .whereField("userID1", isEqualTo: authorID)
                .whereField("userID2", isEqualTo: currentUserID)
                .limit(to: 1)
                .getDocuments()
            
            if !friendship2.documents.isEmpty {
                await MainActor.run {
                    isFriend = true
                }
                print("📍 友達チェック結果: friendshipsコレクション（userID1/userID2 逆）で友達を確認")
                return
            }
            
            // 2. 旧バージョン: friendRequestsコレクションでacceptedをチェック
            let request1 = try await db.collection("friendRequests")
                .whereField("fromUserID", isEqualTo: currentUserID)
                .whereField("toUserID", isEqualTo: authorID)
                .whereField("status", isEqualTo: "accepted")
                .limit(to: 1)
                .getDocuments()
            
            if !request1.documents.isEmpty {
                await MainActor.run {
                    isFriend = true
                }
                print("📍 友達チェック結果: 旧バージョンのfriendRequests（accepted）で友達を確認")
                return
            }
            
            let request2 = try await db.collection("friendRequests")
                .whereField("fromUserID", isEqualTo: authorID)
                .whereField("toUserID", isEqualTo: currentUserID)
                .whereField("status", isEqualTo: "accepted")
                .limit(to: 1)
                .getDocuments()
            
            if !request2.documents.isEmpty {
                await MainActor.run {
                    isFriend = true
                }
                print("📍 友達チェック結果: 旧バージョンのfriendRequests（accepted 逆）で友達を確認")
                return
            }
            
            // どこにも見つからなかった
            await MainActor.run {
                isFriend = false
            }
            print("📍 友達チェック結果: 友達関係が見つかりませんでした")
            
        } catch {
            print("❌ 友達関係のチェックに失敗: \(error.localizedDescription)")
            await MainActor.run {
                isFriend = false
            }
        }
    }
    
    // コメントを読み込み
    func loadComments() async {
        isLoadingComments = true
        
        do {
            let fetchedComments = try await firestoreService.fetchComments(postID: currentPost.id)
            await MainActor.run {
                comments = fetchedComments
                isLoadingComments = false
                commentError = nil
            }
        } catch {
            print("❌ コメントの読み込みに失敗: \(error.localizedDescription)")
            await MainActor.run {
                isLoadingComments = false
                // インデックスエラーの場合はユーザーフレンドリーなメッセージを表示
                if error.localizedDescription.contains("index") || error.localizedDescription.contains("インデックス") {
                    commentError = "コメント機能を使用するにはFirebaseの設定が必要です"
                } else {
                    commentError = nil
                }
            }
        }
    }
    
    // コメントを投稿
    func postComment() async {
        let trimmedComment = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedComment.isEmpty else { return }
        
        print("📍 コメント投稿開始: isFriend=\(isFriend), postID=\(currentPost.id.uuidString)")
        
        isPostingComment = true
        commentError = nil
        
        do {
            try await firestoreService.addComment(postID: currentPost.id, comment: trimmedComment)
            
            print("✅ コメント投稿成功")
            
            // コメント入力欄をクリア
            await MainActor.run {
                newCommentText = ""
                isPostingComment = false
            }
            
            // コメントを再読み込み
            await loadComments()
        } catch {
            print("❌ コメントの投稿に失敗: \(error.localizedDescription)")
            await MainActor.run {
                commentError = error.localizedDescription
                isPostingComment = false
            }
        }
    }
    
    // 返信を投稿
    func postReply() async {
        let trimmedComment = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedComment.isEmpty, let replyTo = replyToComment else { return }
        
        print("📍 返信投稿開始: replyToCommentID=\(replyTo.id), postID=\(currentPost.id.uuidString)")
        
        isPostingComment = true
        commentError = nil
        
        do {
            try await firestoreService.addReply(
                postID: currentPost.id,
                comment: trimmedComment,
                replyToCommentID: replyTo.id,
                replyToUserName: replyTo.userName
            )
            
            print("✅ 返信投稿成功")
            
            // コメント入力欄をクリアし、返信モードを解除
            await MainActor.run {
                newCommentText = ""
                isPostingComment = false
                isReplyMode = false
                replyToComment = nil
            }
            
            // コメントを再読み込み
            await loadComments()
        } catch {
            print("❌ 返信の投稿に失敗: \(error.localizedDescription)")
            await MainActor.run {
                commentError = error.localizedDescription
                isPostingComment = false
            }
        }
    }
    
    // コメントを削除
    func deleteComment(commentID: String) async {
        do {
            try await firestoreService.deleteComment(commentID: commentID)
            await loadComments()
        } catch {
            print("❌ コメントの削除に失敗: \(error.localizedDescription)")
        }
    }
    
    // コメント日時をフォーマット
    func formatCommentDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    func handleSupport(emoji: SupportEmoji) async {
        guard !isSupporting else { return }
        
        print("📍 handleSupport開始: currentPost.id=\(currentPost.id.uuidString), post.id=\(post.id.uuidString)")
        print("📍 現在の応援数: currentPost=\(currentPost.supportCount), post=\(post.supportCount)")
        print("📍 現在のsupports配列: \(currentPost.supports.map { "\($0.userID): \($0.emoji.rawValue)" })")
        
        // 既に共感済みかチェック
        let currentUserID = UserService.shared.currentUserID
        if currentPost.supports.contains(where: { $0.userID == currentUserID }) {
            print("⚠️ 既にこの投稿に共感済みです")
            await MainActor.run {
                supportError = "既にこの投稿に応援済みです"
            }
            return
        }
        
        isSupporting = true
        supportError = nil
        
        // 楽観的更新
        var newSupports = currentPost.supports
        newSupports.append(SupportInfo(emoji: emoji, userID: currentUserID, timestamp: Date()))
        
        let updatedPost = EmotionPost(
            id: currentPost.id,
            level: currentPost.level,
            visualType: currentPost.visualType,
            createdAt: currentPost.createdAt,
            latitude: currentPost.latitude,
            longitude: currentPost.longitude,
            likeCount: currentPost.likeCount,
            likedBy: currentPost.likedBy,
            supports: newSupports,
            authorID: currentPost.authorID,
            isPublicPost: currentPost.isPublicPost,
            comment: currentPost.comment
        )
        
        await MainActor.run {
            currentPost = updatedPost
            print("📍 楽観的更新完了: 新しい応援数=\(currentPost.supportCount)")
            print("📍 楽観的更新後のcurrentPost.id: \(currentPost.id.uuidString)")
        }
        
        print("📍 Firestoreに直接保存開始: currentPost.id=\(currentPost.id.uuidString)")
        
        // 親のコールバックを経由せず、直接Firestoreに保存
        do {
            let newSupportCount = try await firestoreService.addSupport(postID: currentPost.id, emoji: emoji, post: currentPost)
            print("✅ Firestore保存成功: 新しい応援数=\(newSupportCount)")
            
            // 親に通知
            await onSupport(currentPost, emoji)
        } catch {
            print("❌ Firestore保存失敗: \(error.localizedDescription)")
            await MainActor.run {
                supportError = error.localizedDescription
            }
        }
        
        // 親からの更新を待つ
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒待機
        
        await MainActor.run {
            isSupporting = false
        }
    }
    
    func handleRemoveSupport() async {
        guard !isSupporting else { return }
        
        isSupporting = true
        
        print("📍 Firestoreから共感削除開始: currentPost.id=\(currentPost.id.uuidString)")
        
        // 親のコールバックを経由せず、直接Firestoreから削除
        do {
            let newSupportCount = try await firestoreService.removeSupport(postID: currentPost.id, post: currentPost)
            print("✅ Firestore削除成功: 新しい応援数=\(newSupportCount)")
            
            // 楽観的更新
            let currentUserID = UserService.shared.currentUserID
            var newSupports = currentPost.supports
            newSupports.removeAll { $0.userID == currentUserID }
            
            currentPost = EmotionPost(
                id: currentPost.id,
                level: currentPost.level,
                visualType: currentPost.visualType,
                createdAt: currentPost.createdAt,
                latitude: currentPost.latitude,
                longitude: currentPost.longitude,
                likeCount: currentPost.likeCount,
                likedBy: currentPost.likedBy,
                supports: newSupports,
                authorID: currentPost.authorID,
                isPublicPost: currentPost.isPublicPost,
                comment: currentPost.comment
            )
            
            // 親に通知
            await onRemoveSupport(currentPost)
        } catch {
            print("❌ Firestore削除失敗: \(error.localizedDescription)")
            await MainActor.run {
                supportError = error.localizedDescription
            }
        }
        
        isSupporting = false
    }
    
    var emoji: String {
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
    
    var levelText: String {
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
    
    func formatDate(_ date: Date) -> String? {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
}

// 商用利用可能な観光写真（Unsplash: 商用OK・クレジット任意）
// https://unsplash.com/license
// ★「その場所」の写真に差し替え済み：東京スカイツリー／東京タワー／浅草寺／明治神宮／鎌倉大仏／清水寺／金閣寺／伏見稲荷／富士山／姫路城／大阪城／宮島／札幌／彦根城／東大寺・奈良公園 など。
// 未対応スポットは unsplash.com で「スポット名」を検索→お気に入りの写真を選ぶ→Download→表示される画像URLをコピーしてこの辞書の値に貼り付けてください。
private let spotImageURLOverrides: [String: String] = [
    // 北海道
    "札幌時計台": "https://images.unsplash.com/photo-1758316649536-7a07e008a48e?w=800", // その場所（札幌時計台・夜景）
    "小樽運河": "https://images.unsplash.com/photo-1756460886124-fca30da074c4?w=800", // その場所（小樽運河・北海道）
    "富良野・美瑛のラベンダー畑": "https://images.unsplash.com/photo-1590559899731-a382839e5549?w=800", // その場所（ラベンダー畑）
    // 東北
    "弘前城": "https://images.unsplash.com/photo-1714999667643-d811c009309e?w=800",
    "十和田湖・奥入瀬渓流": "https://images.unsplash.com/photo-1637230922121-8eb94eff2dd6?w=800", // その場所（十和田湖・奥入瀬渓流・青森・紅葉）
    "三内丸山遺跡": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "中尊寺": "https://images.unsplash.com/photo-1669002231631-aee9a55f8ef0?w=800",
    "平泉世界遺産": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "浄土ヶ浜": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800",
    "仙台城址": "https://images.unsplash.com/photo-1714999667643-d811c009309e?w=800",
    "松島湾・瑞巌寺": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "鳴子温泉郷": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "角館の武家屋敷通り": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "田沢湖": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800",
    "男鹿半島のなまはげ館": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "山寺の立石寺": "https://images.unsplash.com/photo-1608223019906-a24aa2c60193?w=800", // その場所（山寺・立石寺）
    "蔵王連峰・御釜": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800",
    "銀山温泉": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "会津若松城（鶴ヶ城）": "https://images.unsplash.com/photo-1741265517565-0ce4dafc696e?w=800", // その場所（会津若松城・福島・雪景色）
    "五色沼": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800",
    "大内宿": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    // 関東（庭園・神社・滝・温泉・街並み・テーマパーク・水族館）
    "偕楽園": "https://images.unsplash.com/photo-1665655319790-50af4629d01d?w=800",
    "日立海浜公園": "https://images.unsplash.com/photo-1590559899731-a382839e5549?w=800",
    "鹿島神宮": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "日光東照宮": "https://images.unsplash.com/photo-1669002231631-aee9a55f8ef0?w=800", // その場所（日光・東照宮エリア）
    "華厳の滝": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800",
    "那須どうぶつ王国": "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=800",
    "草津温泉": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "富岡製糸場": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "尾瀬ヶ原": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800",
    "川越の蔵造りの街並み": "https://images.unsplash.com/photo-1763469866790-7eed99ab9e2b?w=800", // その場所（川越・蔵造りの街並み）
    "長瀞ライン下り": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800",
    "秩父神社": "https://images.unsplash.com/photo-uFqlxvjWIlI?w=800", // その場所（秩父神社・雪景色）
    "東京ディズニーリゾート": "https://images.unsplash.com/photo-1744793840798-d79b039fe88e?w=800",
    "鴨川シーワールド": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800",
    "成田山新勝寺": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "東京スカイツリー": "https://images.unsplash.com/photo-1744793840798-d79b039fe88e?w=800", // その場所（桜とスカイツリー）
    "浅草寺": "https://images.unsplash.com/photo-1565707990801-71e6d5f10ac6?w=800", // その場所（浅草の夜景）
    "明治神宮": "https://images.unsplash.com/photo-1696462550207-8ac325fa5c81?w=800", // その場所（明治神宮・東京）
    "東京タワー": "https://images.unsplash.com/photo-1505814360303-5bfcf2a8acb6?w=800", // その場所（東京タワー）
    // "コクーンタワー": ローカルアセット「コクーンタワー」を使用
    "鎌倉大仏（高徳院）": "https://images.unsplash.com/photo-1723525631604-95a0aad5a764?w=800", // その場所（鎌倉大仏）
    "鶴岡八幡宮": "https://images.unsplash.com/photo-1752953600512-e03897783d8c?w=800", // その場所（鶴岡八幡宮・鎌倉）
    "横浜・みなとみらい": "https://images.unsplash.com/photo-1757132592984-815256033d97?w=800", // その場所（横浜・みなとみらい・観覧車と高層ビル）
    // 甲信越・北陸（金山・温泉・山・ダム・合掌・庭園・市場・海岸）
    "佐渡金山": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "越後湯沢温泉エリア": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "弥彦山": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800",
    "黒部ダム": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800",
    "立山黒部アルペンルート": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800",
    "五箇山合掌造り集落": "https://images.unsplash.com/photo-1748092817952-cbf777887681?w=800", // その場所（五箇山・富山）
    "金沢城跡／兼六園": "https://images.unsplash.com/photo-1665655319790-50af4629d01d?w=800",
    "21世紀美術館": "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=800",
    "近江町市場": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "東尋坊": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800",
    "恐竜博物館": "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=800",
    "越前海岸": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800",
    // 東海・中部（富士山・湧水・城・寺・山・合掌・温泉・海岸・城・神社・古道・水族館・湖）
    "富士山（河口湖周辺・五合目エリア）": "https://images.unsplash.com/photo-1740815881087-b311652cdf0b?w=800", // その場所（富士山）
    "忍野八海": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800",
    "甲府城跡": "https://images.unsplash.com/photo-1714999667643-d811c009309e?w=800",
    "松本城": "https://images.unsplash.com/photo-1656430713615-dcf481d53c25?w=800", // その場所（松本城・長野）
    "善光寺": "https://images.unsplash.com/photo-1669002231631-aee9a55f8ef0?w=800",
    "上高地": "https://images.unsplash.com/photo-1733227939867-832b1d1a462f?w=800", // その場所（上高地・長野）
    "白川郷合掌造り集落": "https://images.unsplash.com/photo-1744000457806-888d82ab4d99?w=800", // その場所（白川郷）
    "高山の古い町並み": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "郡上八幡城": "https://images.unsplash.com/photo-1714999667643-d811c009309e?w=800",
    "富士山（世界遺産・周辺エリア）": "https://images.unsplash.com/photo-1528164344705-47542687000d?w=800", // その場所（富士山）
    "熱海温泉": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800",
    "三保の松原": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800",
    "名古屋城": "https://images.unsplash.com/photo-1747546314703-6c4fc20c5a37?w=800", // その場所（名古屋城）
    "熱田神宮": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "犬山城": "https://images.unsplash.com/photo-1714999667643-d811c009309e?w=800",
    "伊勢神宮": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "熊野古道": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800",
    "鳥羽水族館": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800",
    "琵琶湖": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800",
    "彦根城": "https://images.unsplash.com/photo-1757852805475-e3d5689c4814?w=800", // その場所（彦根城・庭園）
    "比叡山延暦寺": "https://images.unsplash.com/photo-1669002231631-aee9a55f8ef0?w=800",
    // 京都・関西（その場所の写真に差し替え済み）
    "清水寺": "https://images.unsplash.com/photo-1669002231631-aee9a55f8ef0?w=800", // その場所（清水寺・京都）
    "金閣寺（鹿苑寺）": "https://images.unsplash.com/photo-1665655319790-50af4629d01d?w=800", // その場所（金閣寺・京都）
    "伏見稲荷大社": "https://images.unsplash.com/photo-1763918036264-34d5da82052c?w=800", // その場所（伏見稲荷大社・千本鳥居）
    "大阪城": "https://images.unsplash.com/photo-1758075105467-2a19f67c3424?w=800", // その場所（大阪城・池に映る）
    "道頓堀": "https://images.unsplash.com/photo-1593327478947-d530033a86ff?w=800", // その場所（道頓堀・大阪）
    "ユニバーサル・スタジオ・ジャパン": "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=800",
    "姫路城": "https://images.unsplash.com/photo-1559145673-a670a11ac647?w=800", // その場所（姫路城・桜）
    "有馬温泉": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "神戸・北野異人館街": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "東大寺": "https://images.unsplash.com/photo-1684098936131-7c39b4974013?w=800", // その場所（東大寺・大仏）
    "奈良公園": "https://images.unsplash.com/photo-1558429121-58002cad3b1f?w=800", // その場所（奈良公園・鹿）
    "吉野山": "https://images.unsplash.com/photo-1590559899731-a382839e5549?w=800",
    "那智の滝": "https://images.unsplash.com/photo-1670312690283-01e9153c5b67?w=800", // その場所（那智の滝・和歌山）
    "高野山": "https://images.unsplash.com/photo-1610623757759-e94661873465?w=800", // その場所（高野山・和歌山・雪景色）
    // 中国・四国（砂丘・神社・街並み・城・庭園・公園・橋・渓谷・温泉・海）
    "鳥取砂丘": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800",
    "白兎神社": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "倉吉の白壁土蔵群": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "出雲大社": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "石見銀山遺跡": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "松江城": "https://images.unsplash.com/photo-1714999667643-d811c009309e?w=800",
    "後楽園": "https://images.unsplash.com/photo-1665655319790-50af4629d01d?w=800",
    "岡山城": "https://images.unsplash.com/photo-1714999667643-d811c009309e?w=800",
    "倉敷美観地区": "https://images.unsplash.com/photo-1496430598224-bfe65f200517?w=800", // その場所（倉敷美観地区・岡山）
    "広島平和記念公園・原爆ドーム": "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=800",
    "宮島（厳島神社）": "https://images.unsplash.com/photo-1753736382549-b39e69a6e27d?w=800", // その場所（厳島神社・大鳥居）
    "呉の大和ミュージアム": "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=800",
    "秋吉台カルスト台地": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800",
    "瑠璃光寺五重塔": "https://images.unsplash.com/photo-1669002231631-aee9a55f8ef0?w=800",
    "角島大橋": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800",
    "阿波おどり会館": "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=800",
    "渦の道": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800",
    "鳴門公園（大鳴門橋架橋記念公園）": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800",
    "栗林公園": "https://images.unsplash.com/photo-1665655319790-50af4629d01d?w=800",
    "金刀比羅宮": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "小豆島・寒霞渓": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800",
    "道後温泉": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "松山城": "https://images.unsplash.com/photo-1591272324753-2680b46eaa3f?w=800", // その場所（松山城・愛媛）
    "しまなみ海道": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800",
    "高知城": "https://images.unsplash.com/photo-1714999667643-d811c009309e?w=800",
    "桂浜": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800",
    "四万十川": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800",
    // 九州・沖縄（神社・タワー・公園・城・海岸・温泉・渓谷・水族館・城跡）
    "太宰府天満宮": "https://images.unsplash.com/photo-1680304052180-68bd94d4224c?w=800", // その場所（太宰府天満宮・福岡・桜）
    "福岡タワー": "https://images.unsplash.com/photo-1505814360303-5bfcf2a8acb6?w=800",
    "大濠公園": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800",
    "佐賀城跡": "https://images.unsplash.com/photo-1714999667643-d811c009309e?w=800",
    "虹の松原": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800",
    "吉野ヶ里歴史公園": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "グラバー園": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "稲佐山夜景": "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=800",
    "長崎原爆資料館・平和公園": "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=800",
    "熊本城": "https://images.unsplash.com/photo-1714999667643-d811c009309e?w=800",
    "阿蘇山": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800",
    "黒川温泉": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "別府温泉": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800",
    "湯布院": "https://images.unsplash.com/photo-1760243875175-064c835a0b40?w=800", // その場所（湯布院・大分）
    "高崎山自然動物園": "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=800",
    "高千穂峡": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800",
    "日南海岸": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800",
    "青島神社": "https://images.unsplash.com/photo-1542767673-ee5103fedbb1?w=800",
    "屋久島": "https://images.unsplash.com/photo-1685355119945-95ada646d133?w=800", // その場所（屋久島・鹿児島・森と川）
    "桜島": "https://images.unsplash.com/photo-1516537219851-920e2670c6e3?w=800", // その場所（桜島・鹿児島・噴火）
    "指宿温泉": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800",
    "美ら海水族館": "https://images.unsplash.com/photo-1709432406576-12e154445772?w=800", // その場所（美ら海水族館・沖縄）
    "首里城": "https://images.unsplash.com/photo-1714999667643-d811c009309e?w=800",
    "今帰仁城跡": "https://images.unsplash.com/photo-1701193039901-1303b111d3cb?w=800" // その場所（今帰仁城跡・沖縄）
]

// ローカルアセット名（URLがない場合のフォールバック用）
private let spotImageOverrides: [String: String] = [
    // 東京
    "東京スカイツリー": "spot_東京スカイツリー",
    "浅草寺": "spot_浅草寺",
    "明治神宮": "spot_明治神宮",
    "東京タワー": "spot_東京タワー",
    "コクーンタワー": "spot_コクーンタワー",
    // 千葉
    "東京ディズニーリゾート": "spot_東京ディズニーリゾート",
    "鴨川シーワールド": "spot_鴨川シーワールド",
    "成田山新勝寺": "spot_成田山新勝寺",
    // 神奈川
    "鎌倉大仏（高徳院）": "spot_鎌倉大仏",
    "鶴岡八幡宮": "spot_鶴岡八幡宮",
    "横浜・みなとみらい": "spot_横浜みなとみらい",
    // 新潟
    "佐渡金山": "spot_佐渡金山",
    "越後湯沢温泉エリア": "spot_越後湯沢温泉エリア",
    "弥彦山": "spot_弥彦山",
    // 富山
    "黒部ダム": "spot_黒部ダム",
    "立山黒部アルペンルート": "spot_立山黒部アルペンルート",
    "五箇山合掌造り集落": "spot_五箇山合掌造り集落",
    // 石川
    "金沢城跡／兼六園": "spot_金沢城跡兼六園",
    "21世紀美術館": "spot_21世紀美術館",
    "近江町市場": "spot_近江町市場",
    // 福井
    "東尋坊": "spot_東尋坊",
    "恐竜博物館": "spot_恐竜博物館",
    "越前海岸": "spot_越前海岸"
]

private let spotDescriptionOverrides: [String: String] = [
    // 北海道
    "札幌時計台": "札幌を象徴する歴史的建造物。",
    "小樽運河": "石造倉庫が並ぶ風情ある運河。",
    "富良野・美瑛のラベンダー畑": "夏に広がる紫の花畑が名物。",
    // 青森
    "弘前城": "桜の名所として知られる名城。",
    "十和田湖・奥入瀬渓流": "透明な湖と渓流の絶景が楽しめる。",
    "三内丸山遺跡": "縄文時代の大規模集落跡。",
    // 岩手
    "中尊寺": "金色堂で有名な古刹。",
    "平泉世界遺産": "浄土思想の遺産が残る世界遺産。",
    "浄土ヶ浜": "白い岩と青い海が美しい海岸。",
    // 宮城
    "仙台城址": "伊達政宗ゆかりの城跡。",
    "松島湾・瑞巌寺": "日本三景の一つ。寺院と景勝地。",
    "鳴子温泉郷": "湯けむり漂う名湯エリア。",
    // 秋田
    "角館の武家屋敷通り": "武家屋敷と枝垂れ桜の街並み。",
    "田沢湖": "日本一深い湖。青い湖面が特徴。",
    "男鹿半島のなまはげ館": "なまはげ文化を体験できる施設。",
    // 山形
    "山寺の立石寺": "断崖の寺院。階段参道が有名。",
    "蔵王連峰・御釜": "エメラルド色の火口湖。",
    "銀山温泉": "大正浪漫の温泉街。",
    // 福島
    "会津若松城（鶴ヶ城）": "白亜の名城。歴史の舞台。",
    "五色沼": "色が変化する神秘的な湖沼群。",
    "大内宿": "茅葺き屋根の宿場町。",
    // 茨城
    "偕楽園": "日本三名園の一つ。",
    "日立海浜公園": "季節の花畑が広がる公園。",
    "鹿島神宮": "東国三社の一社。武道の神。",
    // 栃木
    "日光東照宮": "徳川家康を祀る世界遺産。",
    "華厳の滝": "中禅寺湖から落ちる名瀑。",
    "那須どうぶつ王国": "動物と触れ合えるテーマパーク。",
    // 群馬
    "草津温泉": "日本有数の湯量を誇る温泉地。",
    "富岡製糸場": "近代化を支えた世界遺産。",
    "尾瀬ヶ原": "湿原と木道が広がる自然景勝地。",
    // 埼玉
    "川越の蔵造りの街並み": "小江戸と呼ばれる歴史的街並み。",
    "長瀞ライン下り": "荒川の渓谷を下る舟遊び。",
    "秩父神社": "彫刻が美しい由緒ある神社。",
    // 千葉
    "東京ディズニーリゾート": "テーマパークとホテルが集まる一大リゾート。",
    "鴨川シーワールド": "シャチのショーが名物の水族館。",
    "成田山新勝寺": "成田山の大本山。歴史ある参道も人気。",
    // 東京
    "東京スカイツリー": "世界一高い電波塔。展望台からの眺めが人気。",
    "浅草寺": "東京最古の寺。雷門と仲見世通りが有名。",
    "明治神宮": "明治天皇を祀る神社。広大な森の参道。",
    "東京タワー": "赤と白のランドマーク。夜景スポットとして人気。",
    "コクーンタワー": "独特な繭型の高層ビル。新宿の象徴的建築。",
    // 山梨
    "富士山（河口湖周辺・五合目エリア）": "富士山を間近に感じる定番観光地。",
    "忍野八海": "湧水池が点在する名勝。",
    "甲府城跡": "城跡公園と石垣が残る名所。",
    // 長野
    "松本城": "黒い天守が美しい国宝の城。",
    "善光寺": "全国から参拝者が訪れる古刹。",
    "上高地": "北アルプスの絶景ハイキング地。",
    // 岐阜
    "白川郷合掌造り集落": "世界遺産の合掌造り集落。",
    "高山の古い町並み": "古い商家が並ぶ城下町。",
    "郡上八幡城": "山上に立つ小さな城。",
    // 静岡
    "富士山（世界遺産・周辺エリア）": "富士山の眺望スポットが点在。",
    "熱海温泉": "海辺の温泉街として人気。",
    "三保の松原": "松林と富士山の景観が有名。",
    // 愛知
    "名古屋城": "金のしゃちほこが有名な城。",
    "熱田神宮": "草薙剣を祀る由緒ある神社。",
    "犬山城": "現存天守を持つ国宝の城。",
    // 三重
    "伊勢神宮": "日本を代表する神社。",
    "鳥羽水族館": "日本最大級の水族館。",
    // 滋賀
    "琵琶湖": "日本最大の湖。湖畔散策が人気。",
    "彦根城": "現存天守を持つ国宝の城。",
    "比叡山延暦寺": "天台宗の総本山。",
    // 京都
    "清水寺": "舞台造りの本堂で有名。",
    "金閣寺（鹿苑寺）": "金色に輝く舎利殿。",
    "伏見稲荷大社": "千本鳥居が圧巻の神社。",
    // 大阪
    "大阪城": "豊臣秀吉ゆかりの名城。",
    "道頓堀": "グルメとネオンが有名な繁華街。",
    "ユニバーサル・スタジオ・ジャパン": "映画テーマの大型テーマパーク。",
    // 兵庫
    "姫路城": "白鷺城と呼ばれる世界遺産の城。",
    "有馬温泉": "日本三古湯の一つ。",
    "神戸・北野異人館街": "洋館が並ぶ異国情緒の街。",
    // 奈良
    "東大寺": "大仏で有名な世界遺産。",
    "奈良公園": "鹿と触れ合える広大な公園。",
    "吉野山": "桜の名所として全国的に有名。",
    // 和歌山
    "熊野古道": "世界遺産の巡礼道。",
    "那智の滝": "落差133mの名瀑。",
    "高野山": "真言宗の聖地。",
    // 鳥取
    "鳥取砂丘": "日本最大の砂丘。",
    "白兎神社": "因幡の白兎伝説の神社。",
    "倉吉の白壁土蔵群": "白壁の街並みが残る地区。",
    // 島根
    "出雲大社": "縁結びの神社として有名。",
    "石見銀山遺跡": "世界遺産の銀山跡。",
    "松江城": "現存天守を持つ国宝の城。",
    // 岡山
    "後楽園": "日本三名園の一つ。",
    "岡山城": "黒い天守が特徴の城。",
    "倉敷美観地区": "白壁の街並みと運河が美しい。",
    // 広島
    "広島平和記念公園・原爆ドーム": "平和を祈る世界遺産。",
    "宮島（厳島神社）": "海に浮かぶ大鳥居が有名。",
    "呉の大和ミュージアム": "戦艦大和の展示で有名。",
    // 山口
    "秋吉台カルスト台地": "日本最大級のカルスト地形。",
    "瑠璃光寺五重塔": "美しい五重塔が立つ寺。",
    "角島大橋": "海上を渡る絶景ドライブ橋。",
    // 徳島
    "阿波おどり会館": "阿波踊りを体験できる施設。",
    "渦の道": "鳴門の渦潮を間近で見られる。",
    "鳴門公園（大鳴門橋架橋記念公園）": "渦潮と大橋の景観スポット。",
    // 香川
    "栗林公園": "回遊式庭園として名高い。",
    "金刀比羅宮": "長い石段で有名な神社。",
    "小豆島・寒霞渓": "島と渓谷の絶景スポット。",
    // 愛媛
    "道後温泉": "日本最古級の温泉。",
    "松山城": "山上に立つ名城。",
    "しまなみ海道": "島々を結ぶサイクリングロード。",
    // 高知
    "高知城": "本丸御殿が残る城。",
    "桂浜": "坂本龍馬像と海岸の景観。",
    "四万十川": "清流として名高い川。",
    // 福岡
    "太宰府天満宮": "学問の神様で有名。",
    "福岡タワー": "海辺に立つ展望タワー。",
    "大濠公園": "湖と散策路がある都市公園。",
    // 佐賀
    "佐賀城跡": "歴史を感じる城跡公園。",
    "虹の松原": "海岸沿いの美しい松林。",
    "吉野ヶ里歴史公園": "弥生時代の遺跡公園。",
    // 長崎
    "グラバー園": "洋館が並ぶ歴史的観光地。",
    "稲佐山夜景": "世界新三大夜景の一つ。",
    "長崎原爆資料館・平和公園": "平和を学ぶ資料館と公園。",
    // 熊本
    "熊本城": "黒い外観が特徴の名城。",
    "阿蘇山": "世界最大級のカルデラ火山。",
    "黒川温泉": "情緒ある温泉街。",
    // 大分
    "別府温泉": "地獄めぐりで有名な温泉地。",
    "湯布院": "由布岳を望む人気温泉地。",
    "高崎山自然動物園": "野生のサルに出会える。",
    // 宮崎
    "高千穂峡": "柱状節理の峡谷と滝が美しい。",
    "日南海岸": "海岸線のドライブが人気。",
    "青島神社": "亜熱帯の島にある神社。",
    // 鹿児島
    "屋久島": "縄文杉で有名な世界遺産の島。",
    "桜島": "鹿児島の象徴的な活火山。",
    "指宿温泉": "砂むし温泉で有名。",
    // 沖縄
    "美ら海水族館": "巨大水槽がある人気水族館。",
    "首里城": "琉球王国の象徴的な城。",
    "今帰仁城跡": "世界遺産の城跡と絶景。",
]

// ローカルアセット表示時もクレジットはUnsplashに統一（商用利用の一貫性）
private let spotPhotoCredits: [String: String] = [
    "東京スカイツリー": "Unsplash",
    "浅草寺": "Unsplash",
    "明治神宮": "Unsplash",
    "東京タワー": "Unsplash",
    "東京ディズニーリゾート": "Unsplash",
    "鴨川シーワールド": "Unsplash",
    "成田山新勝寺": "Unsplash",
    "鎌倉大仏（高徳院）": "Unsplash",
    "鶴岡八幡宮": "Unsplash",
    "横浜・みなとみらい": "Unsplash",
    "偕楽園": "Unsplash",
    "日立海浜公園": "Unsplash",
    "鹿島神宮": "Unsplash",
    "日光東照宮": "Unsplash",
    "華厳の滝": "Unsplash",
    "那須どうぶつ王国": "Unsplash",
    "草津温泉": "Unsplash",
    "富岡製糸場": "Unsplash",
    "川越の蔵造りの街並み": "Unsplash",
    "長瀞ライン下り": "Unsplash",
    "佐渡金山": "Unsplash",
    "越後湯沢温泉エリア": "Unsplash",
    "弥彦山": "Unsplash",
    "黒部ダム": "Unsplash",
    "立山黒部アルペンルート": "Unsplash",
    "五箇山合掌造り集落": "Unsplash",
    "金沢城跡／兼六園": "Unsplash",
    "21世紀美術館": "Unsplash",
    "近江町市場": "Unsplash",
    "東尋坊": "Unsplash",
    "恐竜博物館": "Unsplash",
    "越前海岸": "Unsplash",
    "富士山（河口湖周辺・五合目エリア）": "Unsplash",
    "忍野八海": "Unsplash",
    "甲府城跡": "Unsplash",
    "松本城": "Unsplash",
    "善光寺": "Unsplash",
    "上高地": "Unsplash",
    "白川郷合掌造り集落": "Unsplash",
    "高山の古い町並み": "Unsplash"
]

private let defaultSpotPhotoCredit = "Unsplash"

private func isSpotPhotoEnabled(_ spotName: String) -> Bool {
    // 地図と詳細で同じ判定を使って表示不一致を防ぐ
    let displaySpots: Set<String> = [
        "東京スカイツリー", "浅草寺", "明治神宮", "東京タワー", "コクーンタワー"
    ]
    return displaySpots.contains(spotName)
}

/// 商用利用可能な観光写真URL（Unsplash）。東京都のみ。なければnil。
private func spotImageURL(for spotName: String) -> String? {
    // 対象スポットでない場合はnilを返す
    guard isSpotPhotoEnabled(spotName) else {
        return nil
    }
    
    return spotImageURLOverrides[spotName]
}

private func spotImageName(for spotName: String) -> String {
    if let mapped = spotImageOverrides[spotName] {
        return mapped
    }
    let normalized = spotName
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "・", with: "")
        .replacingOccurrences(of: "／", with: "")
        .replacingOccurrences(of: "（", with: "")
        .replacingOccurrences(of: "）", with: "")
        .replacingOccurrences(of: "ー", with: "")
        .replacingOccurrences(of: "－", with: "")
        .replacingOccurrences(of: "—", with: "")
        .replacingOccurrences(of: "〜", with: "")
    return "spot_\(normalized)"
}

private func spotDescription(for spotName: String) -> String? {
    if let mapped = spotDescriptionOverrides[spotName] {
        return mapped
    }
    return "\(spotName)の観光名所です。"
}

private struct SpotDetailSheet: View {
    let spot: Spot
    @ObservedObject var spotImageCache: SpotImageCache
    @State private var showPhotoCredit = false

    var body: some View {
        VStack(spacing: 16) {
            Text(spot.name)
                .font(.title2)
                .fontWeight(.bold)

            // 地図ピンと同じ判定で画像表示し、不一致を防ぐ
            if let image = spotImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .onTapGesture { showPhotoCredit.toggle() }
                if showPhotoCredit {
                    let credit = spotPhotoCredits[spot.name] ?? defaultSpotPhotoCredit
                    Text("写真提供: \(credit)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 220)
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 40))
                            .foregroundColor(.gray.opacity(0.7))
                        Text("開発者がゆっくり写真を")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.gray)
                        Text("入れていくのでお待ちください💦")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.gray)
                    }
                    .padding()
                }
            }

            if let description = spotDescription(for: spot.name) {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        }
        .padding()
    }

    var spotImagePlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.15))
                .frame(height: 220)
            ProgressView()
        }
    }

    var spotImage: UIImage? {
        guard isSpotPhotoEnabled(spot.name) else { return nil }

        // URL画像はキャッシュ済みのときだけ表示（地図ピンと同じ条件）
        if let cachedImage = spotImageCache.image(for: spot.name) {
            return cachedImage
        }

        // URL画像が未取得なら写真なし扱い（青ピン相当）
        if spotImageURL(for: spot.name) != nil {
            return nil
        }

        // URLがないスポットはローカル画像を表示
        return UIImage(named: spotImageName(for: spot.name))
    }
}

private struct MistEventPostSheet: View {
    let event: MistEvent
    let onPosted: () async -> Void
    let firestoreService = FirestoreService()
    @Environment(\.dismiss) private var dismiss
    @State private var emotionValue: Int = 1
    @State private var comment: String = ""
    @State private var isPosting = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("モヤ浄化投稿")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(event.prefectureName)
                    .font(.headline)

                VStack(spacing: 4) {
                    Text("HP: \(event.currentHP)/\(event.maxHP)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Text("😊 正の投稿:")
                            .font(.caption2)
                        Text("\(event.happyPostCount)/5")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(event.happyPostCount >= 5 ? .green : .secondary)
                    }
                }

                VStack(spacing: 8) {
                    Text(emotionLabel)
                        .font(.headline)
                    Slider(
                        value: Binding(
                            get: { Double(emotionValue) },
                            set: { emotionValue = Int($0.rounded()) }
                        ),
                        in: 1...5,
                        step: 1
                    )
                        .accentColor(.blue)
                    HStack {
                        Text("+1")
                            .font(.caption2)
                        Spacer()
                        Text("+5")
                            .font(.caption2)
                    }
                    
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("コメント（任意）")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    TextField("今の気持ちを書いてみよう", text: $comment, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Button(action: submit) {
                    HStack {
                        if isPosting {
                            ProgressView()
                        }
                        Text("投稿してモヤを小さくする")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isPosting)

                Button("キャンセル") {
                    dismiss()
                }
                .font(.footnote)
                .foregroundColor(.secondary)
            }
            .padding()
        }
    }

    var emotionLabel: String {
        EmotionLevel.clamped(emotionValue).localizedText
    }

    func submit() {
        guard !isPosting else { return }

        isPosting = true
        errorMessage = nil
        Task {
            do {
                // 通常の投稿として保存（地図に表示され、履歴にも残る）
                try await firestoreService.postEmotion(
                    level: EmotionLevel.clamped(emotionValue),
                    latitude: event.centerLatitude,
                    longitude: event.centerLongitude,
                    comment: comment.isEmpty ? nil : comment,
                    isMistCleanup: true
                )
                await onPosted()
                await MainActor.run {
                    isPosting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "投稿に失敗しました: \(error.localizedDescription)"
                    isPosting = false
                }
            }
        }
    }
}

private extension EmotionLevel {
    var localizedText: String {
        switch self {
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
}

private struct SupportEmojiPickerView: View {
    let post: EmotionPost
    let onSelect: (SupportEmoji) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text(post.isSadEmotion ? "応援メッセージを選んでください" : "共感メッセージを選んでください")
                    .font(.headline)
                    .padding(.top)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 20) {
                    ForEach(SupportEmoji.emojisForEmotion(level: post.level), id: \.self) { emoji in
                        Button(action: {
                            onSelect(emoji)
                        }) {
                            VStack(spacing: 8) {
                                Text(emoji.rawValue)
                                    .font(.system(size: 50))
                                Text(emoji.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(post.isSadEmotion ? Color.orange.opacity(0.1) : Color.yellow.opacity(0.1))
                            .cornerRadius(16)
                        }
                    }
                }
                .padding()
                
                Spacer()
            }
            .navigationTitle(post.isSadEmotion ? "応援を送る" : "共感を送る")
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
}

extension EmotionPost {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude ?? 0,
            longitude: longitude ?? 0
        )
    }
}

// クラスター内の投稿リストを表示するシート
private struct ClusterPostListSheet: View {
    let cluster: PostCluster
    let onSelectPost: (EmotionPost) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // クラスター情報ヘッダー
                    VStack(spacing: 8) {
                        Text("このエリアの投稿")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        HStack(spacing: 16) {
                            Text("\(cluster.postCount)件")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text(averageLevelText)
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .padding(.top)
                    
                    // 投稿リスト
                    LazyVStack(spacing: 12) {
                        ForEach(sortedPosts) { post in
                            Button(action: {
                                onSelectPost(post)
                            }) {
                                ClusterPostRow(post: post)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("投稿一覧")
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
    
    private var sortedPosts: [EmotionPost] {
        cluster.posts.sorted { $0.createdAt > $1.createdAt }
    }
    
    private var averageLevelText: String {
        let avg = cluster.averageLevel
        if avg > 2 {
            return "平均: とても嬉しい"
        } else if avg > 0 {
            return "平均: やや嬉しい"
        } else if avg > -2 {
            return "平均: やや悲しい"
        } else {
            return "平均: 悲しい"
        }
    }
}

// クラスター内の投稿行
private struct ClusterPostRow: View {
    let post: EmotionPost
    
    var body: some View {
        HStack(spacing: 12) {
            // 感情アイコン
            Text(postEmoji)
                .font(.system(size: 40))
            
            VStack(alignment: .leading, spacing: 4) {
                // 感情レベル
                Text(postLevelText)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // コメント（あれば）
                if let comment = post.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // 投稿時刻
                Text(formatPostTime(post.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // 応援数（あれば）
                if post.supportCount > 0 {
                    HStack(spacing: 4) {
                        Text(post.isSadEmotion ? "💪" : "🤗")
                            .font(.caption)
                        Text("\(post.supportCount)件の応援")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private var postEmoji: String {
        switch post.level {
        case .minusFive: return "😭"
        case .minusFour: return "😢"
        case .minusThree: return "😔"
        case .minusTwo: return "😕"
        case .minusOne: return "🙁"
        case .zero: return "😐"
        case .plusOne: return "🙂"
        case .plusTwo: return "😊"
        case .plusThree: return "😄"
        case .plusFour: return "😁"
        case .plusFive: return "🤩"
        }
    }
    
    private var postLevelText: String {
        switch post.level {
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
    
    private func formatPostTime(_ date: Date) -> String {
        let now = Date()
        let diff = now.timeIntervalSince(date)
        
        if diff < 60 {
            return "たった今"
        } else if diff < 3600 {
            let minutes = Int(diff / 60)
            return "\(minutes)分前"
        } else if diff < 86400 {
            let hours = Int(diff / 3600)
            return "\(hours)時間前"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d HH:mm"
            formatter.locale = Locale(identifier: "ja_JP")
            return formatter.string(from: date)
        }
    }
}

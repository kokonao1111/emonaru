import SwiftUI
import PhotosUI
import ImageIO
import Photos
import UIKit
import FirebaseFirestore

struct ProfileView: View {
    private let firestoreService = FirestoreService()
    private let timelineUseCase = TimelineUseCase(
        timelineRepository: IOSTimelineRepository()
    )
    
    @State private var myPosts: [EmotionPost] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var stats: UserStats?
    @State private var showNotifications = false
    @State private var showFriendsList = false
    @State private var showSettings = false
    @State private var showTitles = false
    @State private var showIconFrames = false
    @State private var showMissions = false
    @State private var showUserSearch = false
    @State private var showProfileShare = false
    @State private var unreadNotificationCount = 0
    @State private var displayName = "あなた"
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImage: UIImage?
    @State private var isDeleting = false
    @State private var isLoadingImage = false
    @State private var imageUpdateID = UUID() // ビューの強制更新用
    @State private var isProcessingPhoto = false // 写真処理中フラグ
    @State private var streakDays: Int? = nil // 連続投稿日数
    @State private var currentLevel: Int = 1
    @State private var levelProgress: Double = 0
    @State private var xpToNextLevel: Int = 100
    @State private var titles: [String] = []
    @State private var iconFrames: [String] = []
    @State private var selectedIconFrame: String?
    @State private var mistClearCount: Int = 0
    @State private var emotionPostCount: Int = 0

    private var levelMissions: [ProfileMissionItem] {
        let targets = [10, 20, 40, 50, 100]
        return targets.map { target in
            ProfileMissionItem(
                id: "level_\(target)",
                target: target,
                title: "レベルを\(target)まであげる",
                frameID: "level_\(target)",
                rewardTitle: "レベル\(target)達成",
                progress: min(currentLevel, target)
            )
        }
    }

    private var mistMissions: [ProfileMissionItem] {
        let targets = [10, 20, 30, 40, 50, 100]
        return targets.map { target in
            ProfileMissionItem(
                id: "mist_\(target)",
                target: target,
                title: "モヤを\(target)回浄化する",
                frameID: "mist_clear_\(target)",
                rewardTitle: "モヤ討伐\(target)回達成",
                progress: min(mistClearCount, target)
            )
        }
    }

    private var postMissions: [ProfileMissionItem] {
        let targets = [10, 20, 40, 50, 100]
        return targets.map { target in
            ProfileMissionItem(
                id: "post_\(target)",
                target: target,
                title: "感情投稿を\(target)回する",
                frameID: "post_\(target)",
                rewardTitle: "感情投稿\(target)回達成",
                progress: min(emotionPostCount, target)
            )
        }
    }
    
    @ViewBuilder
    private var toolbarButtons: some View {
        HStack(spacing: 16) {
            Button(action: {
                showUserSearch = true
            }) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
            }
            
            Button(action: {
                showProfileShare = true
            }) {
                Image(systemName: "qrcode")
                    .font(.title3)
            }
            
            Button(action: {
                showNotifications = true
            }) {
                notificationButton
            }
        }
    }
    
    @ViewBuilder
    private var notificationButton: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "bell.fill")
                .font(.title3)
            
            if unreadNotificationCount > 0 {
                Text("\(unreadNotificationCount)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.red)
                    .clipShape(Circle())
                    .offset(x: 8, y: -8)
            }
        }
    }
    
    @ViewBuilder
    private func actionButtonsRow(isSmallScreen: Bool) -> some View {
        HStack(spacing: isSmallScreen ? 8 : 10) {
            Button(action: { showTitles = true }) {
                actionButton(
                    icon: "crown.fill",
                    text: "称号",
                    color: .yellow,
                    isSmallScreen: isSmallScreen
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: { showIconFrames = true }) {
                actionButton(
                    icon: "square.dashed.inset.filled",
                    text: "アイコンフレーム",
                    color: .blue,
                    isSmallScreen: isSmallScreen
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: { showMissions = true }) {
                actionButton(
                    icon: "list.bullet.rectangle",
                    text: "ミッション",
                    color: .purple,
                    isSmallScreen: isSmallScreen
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.top, isSmallScreen ? 6 : 8)
    }
    
    @ViewBuilder
    private func actionButton(icon: String, text: String, color: Color, isSmallScreen: Bool) -> some View {
        HStack(spacing: isSmallScreen ? 4 : 6) {
            Image(systemName: icon)
                .font(.system(size: isSmallScreen ? 10 : 12))
                .foregroundColor(color)
            Text(text)
                .font(isSmallScreen ? .caption2 : .caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, isSmallScreen ? 10 : 12)
        .padding(.vertical, isSmallScreen ? 4 : 6)
        .background(color.opacity(color == .yellow ? 0.15 : 0.12))
        .cornerRadius(isSmallScreen ? 14 : 16)
    }
    
    @ViewBuilder
    private func statsRow(stats: UserStats, isSmallScreen: Bool) -> some View {
        HStack(spacing: isSmallScreen ? 24 : 32) {
            VStack(spacing: isSmallScreen ? 2 : 4) {
                Text("\(stats.postCount)")
                    .font(isSmallScreen ? .headline : .title3)
                    .fontWeight(.bold)
                Text("投稿")
                    .font(isSmallScreen ? .caption2 : .caption)
                    .foregroundColor(.secondary)
            }
            
            Button(action: { showFriendsList = true }) {
                VStack(spacing: isSmallScreen ? 2 : 4) {
                    Text("\(stats.friendCount)")
                        .font(isSmallScreen ? .headline : .title3)
                        .fontWeight(.bold)
                    Text("友達")
                        .font(isSmallScreen ? .caption2 : .caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.top, isSmallScreen ? 6 : 8)
    }
    
    var body: some View {
        GeometryReader { geometry in
            profileContent(geometry: geometry)
        }
    }
    
    @ViewBuilder
    private func profileContent(geometry: GeometryProxy) -> some View {
        let screenWidth: CGFloat = geometry.size.width
        let isSmallScreen: Bool = screenWidth <= 375
        let isIPad: Bool = UIDevice.current.userInterfaceIdiom == .pad
        let avatarSize: CGFloat = isSmallScreen ? 80 : (isIPad ? 70 : 100)
        let frameSize: CGFloat = isSmallScreen ? 156 : (isIPad ? 136 : 195)
        let frameOffset: (x: CGFloat, y: CGFloat) = isSmallScreen ? (-7.6, -3.6) : (isIPad ? (-6.6, -3.1) : (-9.5, -4.5))
        
        NavigationView {
            Group {
                if isIPad {
                    // iPadの場合はスクロールなし、コンパクトに表示
                    mainContentView(geometry: geometry, isSmallScreen: isSmallScreen, avatarSize: avatarSize, frameSize: frameSize, frameOffset: frameOffset, isIPad: true)
                } else {
                    // iPhoneの場合はスクロール可能
                    ScrollView {
                        mainContentView(geometry: geometry, isSmallScreen: isSmallScreen, avatarSize: avatarSize, frameSize: frameSize, frameOffset: frameOffset, isIPad: false)
                    }
                }
            }
            .navigationTitle("プロフィール")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    toolbarButtons
                }
            }
            .refreshable {
                await loadData()
            }
            .task {
                await loadData()
            }
            .sheet(isPresented: $showNotifications) {
                NotificationsView()
            }
            .sheet(isPresented: $showFriendsList) {
                FriendsListView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showTitles) {
                TitlesListSheet(titles: titles)
            }
            .sheet(isPresented: $showIconFrames) {
                IconFrameListSheet(
                    frames: iconFrames,
                    selected: selectedIconFrame,
                    onSelect: { frameID in
                        Task {
                            let userID = UserService.shared.currentUserID
                            try? await firestoreService.setSelectedIconFrame(userID: userID, frameID: frameID)
                            await MainActor.run {
                                selectedIconFrame = frameID
                            }
                        }
                    }
                )
            }
            .sheet(isPresented: $showMissions) {
                ProfileMissionsListSheet(
                    levelMissions: levelMissions,
                    mistMissions: mistMissions,
                    postMissions: postMissions
                )
            }
            .sheet(isPresented: $showUserSearch) {
                UserSearchView()
            }
            .sheet(isPresented: $showProfileShare) {
                ProfileShareView(
                    userName: displayName,
                    level: currentLevel,
                    profileImage: profileImage
                )
            }
            .onChange(of: selectedPhoto) { oldValue, newValue in
                print("🔄 onChange発火: oldValue=\(oldValue != nil ? "あり" : "なし"), newValue=\(newValue != nil ? "あり" : "なし")")
            }
            .onAppear {
                print("✅ ProfileViewが表示されました")
                loadProfileImage()
                updateDisplayName()
                refreshLevel()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ExperienceUpdated"))) { _ in
                refreshLevel()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NotificationsUpdated"))) { _ in
                Task {
                    await loadData()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PostCreated"))) { _ in
                Task {
                    await loadData()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SettingsUpdated"))) { _ in
                updateDisplayName()
            }
        }
    }
    
    @ViewBuilder
    private func mainContentView(geometry: GeometryProxy, isSmallScreen: Bool, avatarSize: CGFloat, frameSize: CGFloat, frameOffset: (x: CGFloat, y: CGFloat), isIPad: Bool) -> some View {
        VStack(spacing: isIPad ? 8 : (isSmallScreen ? 16 : 24)) {
                    // エラーメッセージ表示
                    if let errorMessage = errorMessage {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .fixedSize(horizontal: false, vertical: true) // 複数行表示を許可
                            
                            Button(action: {
                                self.errorMessage = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                    
                        // プロフィールヘッダー
                        VStack(spacing: isSmallScreen ? 12 : 16) {
                        // アバター
                        PhotosPicker(
                            selection: Binding(
                                get: { selectedPhoto },
                                set: { newValue in
                                    print("🔄 PhotosPickerのsetが呼ばれました: newValue=\(newValue != nil ? "あり" : "なし")")
                                    print("🔄 現在のisProcessingPhoto: \(isProcessingPhoto)")
                                    
                                    // 選択されたら即座に処理
                                    if let newValue = newValue {
                                        print("📸 写真が選択されました（Binding経由） - handlePhotoSelectionを呼び出します")
                                        selectedPhoto = newValue
                                        Task { @MainActor in
                                            await handlePhotoSelection(newValue)
                                        }
                                    } else {
                                        selectedPhoto = newValue
                                    }
                                }
                            ),
                            matching: .images
                        ) {
                            ZStack {
                                if isLoadingImage {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else if let profileImage = profileImage {
                                    Image(uiImage: profileImage)
                                        .resizable()
                                        .scaledToFill()
                                        .transition(.opacity)
                                        .id("image_\(imageUpdateID.uuidString)")
                                } else {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .overlay(
                                            Text("😊")
                                                .font(.system(size: isSmallScreen ? 40 : 50))
                                        )
                                }
                            }
                            .id("avatar_\(imageUpdateID.uuidString)")
                            .animation(.easeInOut(duration: 0.2), value: profileImage)
                            .animation(.easeInOut(duration: 0.2), value: imageUpdateID)
                            .frame(width: avatarSize, height: avatarSize)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: isSmallScreen ? 2 : 3)
                            )
                            .overlay(
                                frameOverlay(frameID: selectedIconFrame, size: frameSize)
                            )
                            .shadow(color: .black.opacity(0.2), radius: isSmallScreen ? 6 : 8)
                            .overlay(
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Image(systemName: "camera.fill")
                                            .font(isSmallScreen ? .system(size: 10) : .caption)
                                            .foregroundColor(.white)
                                            .padding(isSmallScreen ? 4 : 6)
                                            .background(Color.blue)
                                            .clipShape(Circle())
                                            .offset(x: isSmallScreen ? -4 : -5, y: isSmallScreen ? -4 : -5)
                                    }
                                }
                                .frame(width: avatarSize, height: avatarSize)
                            )
                        }
                        
                        // ユーザー名
                        Text(displayName)
                            .font(isSmallScreen ? .headline : .title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        // レベル表示
                        VStack(spacing: isSmallScreen ? 4 : 6) {
                            HStack(spacing: isSmallScreen ? 6 : 8) {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.yellow)
                                    .font(isSmallScreen ? .system(size: 10) : .caption)
                                Text("Lv \(currentLevel)")
                                    .font(isSmallScreen ? .caption : .subheadline)
                                    .fontWeight(.semibold)
                            }

                            GeometryReader { levelGeometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: isSmallScreen ? 4 : 6)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: isSmallScreen ? 6 : 8)

                                    RoundedRectangle(cornerRadius: isSmallScreen ? 4 : 6)
                                        .fill(Color.blue.opacity(0.8))
                                        .frame(width: levelGeometry.size.width * levelProgress, height: isSmallScreen ? 6 : 8)
                                }
                            }
                            .frame(height: isSmallScreen ? 6 : 8)

                            Text("次のレベルまで \(xpToNextLevel) XP")
                                .font(isSmallScreen ? .caption2 : .caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: isSmallScreen ? 180 : 220)
                        
                        // 連続投稿日数の表示
                        if let streakDays = streakDays, streakDays > 1 {
                            HStack(spacing: isSmallScreen ? 4 : 6) {
                                Image(systemName: "flame.fill")
                                    .foregroundColor(.orange)
                                    .font(isSmallScreen ? .system(size: 10) : .caption)
                                Text("\(streakDays)日連続投稿")
                                    .font(isSmallScreen ? .caption : .subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal, isSmallScreen ? 10 : 12)
                            .padding(.vertical, isSmallScreen ? 4 : 6)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(isSmallScreen ? 16 : 20)
                            .padding(.top, isSmallScreen ? 2 : 4)
                        }
                        
                        // 統計情報
                        if let stats = stats {
                            statsRow(stats: stats, isSmallScreen: isSmallScreen)
                            actionButtonsRow(isSmallScreen: isSmallScreen)
                        }
                        }
                        .padding(.top, isSmallScreen ? 16 : 20)
                        .padding(.bottom, isSmallScreen ? 12 : 16)
                    
                    // 投稿一覧
                    if isLoading {
                        ProgressView()
                            .padding()
                    } else if myPosts.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("まだ投稿がありません")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 60)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(sortedPosts) { post in
                                HStack {
                                    ProfilePostRow(post: post)
                                    
                                    Button(action: {
                                        Task {
                                            await deletePost(post)
                                        }
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                            .font(.body)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .padding(.leading, 8)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
        .padding(.bottom, isIPad ? 8 : 20)
    }
    
    private var sortedPosts: [EmotionPost] {
        // 新着順（作成日時の降順）
        myPosts.sorted { $0.createdAt > $1.createdAt }
    }
    
    // プロフィールアバタービュー
    @ViewBuilder
    private var profileAvatarView: some View {
        ZStack {
            if isLoadingImage {
                // 読み込み中はプログレスインジケーターを表示
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else if let profileImage = profileImage {
                Image(uiImage: profileImage)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
                    .id("image_\(imageUpdateID.uuidString)")
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Text("😊")
                            .font(.system(size: 50))
                    )
            }
        }
        .id("avatar_\(imageUpdateID.uuidString)") // ZStack全体にIDを適用して強制的に再描画
        .animation(.easeInOut(duration: 0.2), value: profileImage != nil)
        .animation(.easeInOut(duration: 0.2), value: imageUpdateID)
        .frame(width: 100, height: 100)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white, lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.2), radius: 8)
        .overlay(
            // 編集アイコン
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "camera.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .offset(x: -5, y: -5)
                }
            }
            .frame(width: 100, height: 100)
        )
    }
    
    private func loadData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 自分の投稿を取得
            let posts = try await timelineUseCase.loadMyPosts()
            
            // 統計情報を計算
            let postCount = posts.count
            let totalLikes = posts.reduce(0) { $0 + $1.likeCount }
            let totalSupports = posts.reduce(0) { $0 + $1.supportCount }
            
            // 友達数を取得
            let friendCount = (try? await firestoreService.fetchFriendCount()) ?? 0
            
            // 連続投稿日数を取得
            let currentUserID = UserService.shared.currentUserID
            let streak = try? await firestoreService.calculateStreakDays(userID: currentUserID)
            
            // 未読通知数を取得（Firestore通知のみをカウント）
            var unreadCount = 0
            do {
                let allNotifications = try await firestoreService.fetchAllNotifications()
                unreadCount = allNotifications.filter { !$0.isRead }.count
                print("📊 未読通知数: \(unreadCount)件")
            } catch {
                // インデックスエラーの場合は、エラーログを出力して通知数を0として扱う
                print("⚠️ 未読通知数の取得に失敗: \(error.localizedDescription)")
                // インデックスエラーの場合は、後でインデックスを作成してもらう必要がある
                if error.localizedDescription.contains("index") || error.localizedDescription.contains("インデックス") {
                    print("💡 Firestoreのインデックスが必要です。エラーログに表示されたURLからインデックスを作成してください。")
                }
            }
            
            // Firestoreから経験値を同期
            await UserService.shared.syncExperienceFromFirestore()
            
            await MainActor.run {
                myPosts = posts
                stats = UserStats(
                    postCount: postCount,
                    totalLikes: totalLikes,
                    totalSupports: totalSupports,
                    friendCount: friendCount
                )
                unreadNotificationCount = unreadCount
                streakDays = streak
                isLoading = false
                
                // レベル情報を更新
                refreshLevel()
            }

                let fetchedTitles = try? await firestoreService.fetchUserTitles()
                await MainActor.run {
                    titles = fetchedTitles ?? []
                }

                let frameData = try? await firestoreService.fetchUserIconFrames()
                await MainActor.run {
                    iconFrames = frameData?.frames ?? []
                    let selected = frameData?.selected
                    selectedIconFrame = (selected == "") ? nil : selected
                }

                let docRef = Firestore.firestore()
                    .collection("userPrefectureRegistrations")
                    .document(UserService.shared.currentUserID)
                let doc = try? await docRef.getDocument()
                let count = (doc?.get("mistClearCount") as? Int) ?? 0
                await MainActor.run {
                    mistClearCount = count
                }
                let emotionCount = (doc?.get("emotionPostCount") as? Int) ?? 0
                await MainActor.run {
                    emotionPostCount = emotionCount
                }
        } catch {
            await MainActor.run {
                errorMessage = "データの取得に失敗しました: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func deletePost(_ post: EmotionPost) async {
        guard !isDeleting else { return }
        
        isDeleting = true
        errorMessage = nil
        
        do {
            try await firestoreService.deletePost(postID: post.id)
            
            // リストから削除
            await MainActor.run {
                myPosts.removeAll { $0.id == post.id }
                
                // 統計情報を再計算
                let postCount = myPosts.count
                let totalLikes = myPosts.reduce(0) { $0 + $1.likeCount }
                let totalSupports = myPosts.reduce(0) { $0 + $1.supportCount }
                
                stats = UserStats(
                    postCount: postCount,
                    totalLikes: totalLikes,
                    totalSupports: totalSupports,
                    friendCount: stats?.friendCount ?? 0
                )
            }
        } catch {
            await MainActor.run {
                errorMessage = "投稿の削除に失敗しました: \(error.localizedDescription)"
            }
        }
        
        isDeleting = false
    }
    
    // プロフィール画像を読み込む
    private func loadProfileImage() {
        Task { @MainActor in
            let currentUserID = UserService.shared.currentUserID
            let imageKey = "profile_image_\(currentUserID)"
            
            // まずローカルから読み込む
            if let imageData = UserDefaults.standard.data(forKey: imageKey),
               let image = UIImage(data: imageData) {
                profileImage = image
                imageUpdateID = UUID() // ビューを更新
                print("✅ 保存されたプロフィール画像を読み込みました")
            } else {
                // ローカルになければFirebase Storageからダウンロード
                do {
                    if let downloadedImage = try await firestoreService.downloadProfileImage(userID: currentUserID) {
                        // ダウンロードした画像をローカルに保存
                        if let imageData = downloadedImage.jpegData(compressionQuality: 0.8) {
                            UserDefaults.standard.set(imageData, forKey: imageKey)
                        }
                        profileImage = downloadedImage
                        imageUpdateID = UUID()
                        print("✅ Firebase Storageからプロフィール画像を読み込みました")
                    } else {
                        print("ℹ️ プロフィール画像が見つかりませんでした")
                    }
                } catch {
                    print("⚠️ Firebase Storageからの読み込みに失敗: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // 選択した写真を読み込む
    @MainActor
    private func loadImage(from item: PhotosPickerItem) async -> Bool {
        print("🖼️ 画像の読み込みを開始")
        
        // まず、PhotosPickerItemからPHAssetを取得する方法を試す
        // PhotosPickerItemのitemIdentifierを使用（iOS 17.0以降）
        let itemIdentifier = item.itemIdentifier
        print("📋 PhotosPickerItem itemIdentifier: \(itemIdentifier ?? "nil")")
        
        if let identifier = itemIdentifier, !identifier.isEmpty {
            print("📋 PhotosPickerItem identifier: \(identifier)")
            
            // PHAssetを取得
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            if let asset = assets.firstObject {
                print("✅ PHAssetを取得しました")
                
                // PHImageManagerを使用して画像を読み込む（iCloudフォトライブラリにも対応）
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.isNetworkAccessAllowed = true // iCloudからのダウンロードを許可
                options.isSynchronous = false
                options.resizeMode = .fast
                
                // iCloudからのダウンロード進捗を表示
                options.progressHandler = { progress, error, stop, info in
                    if progress < 1.0 {
                        print("⏳ iCloudからダウンロード中: \(Int(progress * 100))%")
                        Task { @MainActor in
                            self.errorMessage = "iCloudから写真をダウンロード中... \(Int(progress * 100))%"
                        }
                    }
                    if let error = error {
                        print("❌ ダウンロードエラー: \(error.localizedDescription)")
                    }
                }
                
                return await withCheckedContinuation { continuation in
                    PHImageManager.default().requestImage(
                        for: asset,
                        targetSize: CGSize(width: 400, height: 400), // より高解像度で取得
                        contentMode: .aspectFill,
                        options: options
                    ) { image, info in
                        if let image = image {
                            // isDegradedをチェック（低品質プレビューの場合はスキップ）
                            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                            if isDegraded {
                                print("⚠️ 画像が劣化版です（高品質版を待機中...）")
                                return // 高品質版を待つ
                            }
                            
                            print("✅ PHImageManagerから画像を取得しました: \(image.size)")
                            Task { @MainActor in
                                let success = await self.processImage(image)
                                continuation.resume(returning: success)
                            }
                        } else {
                            if let info = info {
                                if let error = info[PHImageErrorKey] as? Error {
                                    print("❌ PHImageManagerエラー: \(error.localizedDescription)")
                                }
                            }
                            print("❌ PHImageManagerから画像を取得できませんでした")
                            continuation.resume(returning: false)
                        }
                    }
                }
            } else {
                print("⚠️ PHAssetを取得できませんでした（identifier: \(identifier)）")
            }
        } else {
            print("⚠️ PhotosPickerItemのitemIdentifierが取得できませんでした")
        }
        
        // PHAssetから読み込めない場合は、従来の方法を試す
        print("🔄 従来の方法で画像を読み込みます")
        
        // データを読み込む（iCloudフォトライブラリにも対応）
        var data: Data?
        var retryCount = 0
        let maxRetries = 5 // リトライ回数を増やす
        
        // リトライロジック（iCloudからのダウンロード待ちに対応）
        while retryCount < maxRetries {
            do {
                // まずDataとして読み込みを試みる
                data = try await item.loadTransferable(type: Data.self)
                if data != nil && data!.count > 0 {
                    print("✅ 画像データの読み込み成功（試行 \(retryCount + 1)）")
                    break
                }
            } catch {
                let errorDescription = error.localizedDescription
                let errorString = String(describing: error)
                let nsError = error as NSError
                let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
                
                print("❌ 画像データの読み込みエラー（試行 \(retryCount + 1)/\(maxRetries)）: \(errorDescription)")
                print("❌ エラー詳細: \(errorString)")
                print("❌ NSError domain: \(nsError.domain), code: \(nsError.code)")
                
                // iCloudフォトライブラリのエラーを検出（エラーチェーン全体を確認）
                var isICloudError = false
                var currentError: NSError? = underlyingError
                
                while let err = currentError {
                    if err.domain == "CloudPhotoLibraryErrorDomain" || 
                       err.domain == "PHAssetExportRequestErrorDomain" {
                        isICloudError = true
                        print("✅ iCloudフォトライブラリのエラーを検出: \(err.domain), code: \(err.code)")
                        break
                    }
                    currentError = err.userInfo[NSUnderlyingErrorKey] as? NSError
                }
                
                if isICloudError {
                    retryCount += 1
                    if retryCount < maxRetries {
                        let waitTime = UInt64(retryCount * 3) * 1_000_000_000 // 3秒、6秒、9秒...と増やす
                        print("⏳ iCloudフォトライブラリのダウンロードを待機中...（\(waitTime / 1_000_000_000)秒）")
                        try? await Task.sleep(nanoseconds: waitTime)
                        continue
                    } else {
                        print("❌ iCloudフォトライブラリのエラーが続いています（\(maxRetries)回試行後）")
                    }
                } else {
                    // その他のエラーの場合も、リトライを試みる
                    retryCount += 1
                    if retryCount < maxRetries {
                        print("⏳ エラーが発生しましたが、リトライを試みます...（試行 \(retryCount + 1)/\(maxRetries)）")
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒待つ
                        continue
                    } else {
                        print("❌ 画像の読み込みに失敗しました（\(maxRetries)回試行後）")
                    }
                }
            }
            
            retryCount += 1
            if retryCount < maxRetries && (data == nil || data!.count == 0) {
                print("⏳ 画像データの読み込みをリトライ中...")
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒待つ
            }
        }
        
        guard let imageData = data, imageData.count > 0 else {
            print("❌ 画像データがnilまたは空です（\(maxRetries)回試行後）")
            print("💡 ヒント: iCloudフォトライブラリの写真の場合、写真を一度開いてローカルにダウンロードしてから再度お試しください")
            // エラーメッセージを設定
            errorMessage = "写真の読み込みに失敗しました。iCloudフォトライブラリの写真の場合、写真アプリで写真を一度開いてローカルにダウンロードしてから再度お試しください。"
            return false
        }
        
        print("✅ 画像データを読み込みました: \(imageData.count) bytes")
        
        // UIImageを作成（すべての画像形式に対応）
        var image: UIImage?
        
        // まず通常の方法で読み込む
        image = UIImage(data: imageData)
        
        // 読み込めない場合は、異なる方法を試す
        if image == nil {
            // HEIC形式などの場合、ImageIOを使用して読み込む
            if let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
                image = UIImage(cgImage: cgImage)
                print("✅ CGImageSourceを使用して画像を作成しました")
            }
        }
        
        guard let finalImage = image else {
            print("❌ UIImageの作成に失敗しました（データサイズ: \(imageData.count) bytes）")
            return false
        }
        
        print("✅ UIImageを作成しました: \(finalImage.size)")
        
        // 画像を処理する
        return await processImage(finalImage)
    }
    
    // 画像を処理して保存する
    @MainActor
    private func processImage(_ image: UIImage) async -> Bool {
        print("🖼️ 画像の処理を開始: \(image.size)")
        
        // 画像をリサイズ（200x200に合わせる）
        let resizedImage = resizeImage(image: image, targetSize: CGSize(width: 200, height: 200))
        print("✅ 画像をリサイズしました: \(resizedImage.size)")
        
        // UserDefaultsに保存
        let currentUserID = UserService.shared.currentUserID
        let imageKey = "profile_image_\(currentUserID)"
        
        guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            print("❌ JPEGデータの変換に失敗しました")
            return false
        }
        
        UserDefaults.standard.set(imageData, forKey: imageKey)
        UserDefaults.standard.synchronize() // 確実に保存
        print("✅ UserDefaultsに保存しました")
        
        // Firebase Storageにアップロード
        var uploadSuccess = false
        do {
            print("📤 Firebase Storageへのアップロード開始...")
            let uploadedURL = try await firestoreService.uploadProfileImage(resizedImage, userID: currentUserID)
            print("✅ Firebase Storageにアップロード成功!")
            print("   - URL: \(uploadedURL)")
            uploadSuccess = true
        } catch {
            print("❌ Firebase Storageへのアップロードに失敗!")
            print("   - エラー: \(error.localizedDescription)")
            
            // エラーメッセージをユーザーに表示
            errorMessage = "⚠️ プロフィール画像のアップロードに失敗しました。\n\n原因:\n・インターネット接続が不安定\n・Firebaseサーバーに接続できない\n\nもう一度試すか、ネットワーク接続を確認してください。"
            
            // ローカルの画像をクリア（サーバーと同期されていないため）
            UserDefaults.standard.removeObject(forKey: imageKey)
            profileImage = nil
            imageUpdateID = UUID()
            
            print("⚠️ アップロード失敗のため、ローカル画像もクリアしました")
            return false
        }
        
        // アップロードが成功した場合のみ、画像を表示
        if uploadSuccess {
            // メインスレッドで確実に画像を更新（@MainActorなので直接更新可能）
            // 直接新しい画像を設定
            profileImage = resizedImage
            imageUpdateID = UUID() // ビューを強制的に再描画
            print("✅ プロフィール画像を設定しました: \(resizedImage.size)")
            print("✅ ビューIDを更新しました: \(imageUpdateID)")
            print("✅ profileImageの状態: \(profileImage != nil ? "設定済み" : "nil")")
            print("✅ profileImageの実際の値: \(profileImage?.size ?? CGSize.zero)")
        }
        
        // 次のフレームまで待つ（UIの更新を確実にする）
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒待つ
        
        // もう一度IDを更新して確実に反映させる
        imageUpdateID = UUID()
        print("✅ 最終的なビューIDを更新しました: \(imageUpdateID)")
        print("✅ profileImageの最終状態: \(profileImage != nil ? "設定済み" : "nil")")
        print("✅ profileImageの最終的な値: \(profileImage?.size ?? CGSize.zero)")
        
        return true
    }
    
    // 画像をリサイズ
    private func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        
        var newSize: CGSize
        if widthRatio > heightRatio {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
        }
        
        let rect = CGRect(origin: .zero, size: newSize)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? image
    }
    
    // 表示名を更新
    private func updateDisplayName() {
        displayName = UserService.shared.userName
    }

    private func refreshLevel() {
        currentLevel = UserService.shared.level
        levelProgress = UserService.shared.levelProgress
        xpToNextLevel = UserService.shared.xpToNextLevel
    }
    
    // 写真選択の処理
    @MainActor
    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        print("📸 写真が選択されました - 処理を開始")
        
        // 処理中フラグを設定
        isProcessingPhoto = true
        isLoadingImage = true
        errorMessage = nil // エラーメッセージをクリア
        print("🔄 処理開始: isProcessingPhoto=true, isLoadingImage=true")
        
        // 画像を読み込む
        let success = await loadImage(from: item)
        
        if success {
            print("✅ 画像の読み込みが成功しました")
            errorMessage = nil
        } else {
            print("❌ 画像の読み込みが失敗しました")
            // iCloudフォトライブラリのエラーの場合、ユーザーにメッセージを表示
            errorMessage = "写真の読み込みに失敗しました。iCloudフォトライブラリの写真の場合、写真を一度開いてローカルにダウンロードしてから再度お試しください。"
        }
        
        isLoadingImage = false
        print("🔄 画像読み込み完了: isLoadingImage=false")
        
        // 画像が確実に表示されるまで待つ
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒待つ
        
        // 処理中フラグを解除
        isProcessingPhoto = false
        print("✅ 処理完了: isProcessingPhoto=false")
        
        // さらに少し待ってからselectedPhotoをリセット（再度選択できるようにする）
        // PhotosPickerのUIが安定するのを待つ
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒待つ（長めに待つ）
        
        // 確実にリセットする
        selectedPhoto = nil
        imageUpdateID = UUID()
        print("✅ selectedPhotoをリセットしました（再度選択可能）")
    }
    
}

struct UserStats {
    let postCount: Int
    let totalLikes: Int
    let totalSupports: Int
    let friendCount: Int
}

private struct TitlesListSheet: View {
    let titles: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTitle: String?

    var body: some View {
        NavigationView {
            ScrollView {
                if titles.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "crown")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("称号はまだありません")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(titles, id: \.self) { title in
                            Button(action: {
                                selectedTitle = title
                            }) {
                                VStack(spacing: 8) {
                                    let assetName = profileTitleAssetName(for: title)
                                    if let image = UIImage(named: assetName) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 64, height: 64)
                                            .clipShape(Circle())
                                    } else {
                                        Image(systemName: "crown")
                                            .font(.system(size: 28))
                                            .foregroundColor(.yellow)
                                            .frame(width: 64, height: 64)
                                            .background(Color.yellow.opacity(0.15))
                                            .clipShape(Circle())
                                            .onAppear {
                                                print("⚠️ 称号画像が見つかりません:")
                                                print("   - 称号名: \(title)")
                                                print("   - アセット名: \(assetName)")
                                            }
                                    }
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity)
                                .background(Color.gray.opacity(0.08))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("称号")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedTitle != nil },
            set: { if !$0 { selectedTitle = nil } }
        )) {
            if let title = selectedTitle {
                TitleDetailSheet(title: title)
            }
        }
    }
}

private struct TitleDetailSheet: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            if let image = UIImage(named: profileTitleAssetName(for: title)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
            } else {
                Image(systemName: "crown")
                    .font(.system(size: 64))
                    .foregroundColor(.yellow)
            }

            Text(title)
                .font(.title2)
                .fontWeight(.bold)

            Text("称号の詳細")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("閉じる") {
                dismiss()
            }
            .padding(.top, 8)
        }
        .padding()
    }
}

private func profileTitleAssetName(for title: String) -> String {
    let normalized = title
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "・", with: "")
        .replacingOccurrences(of: "／", with: "")
        .replacingOccurrences(of: "（", with: "")
        .replacingOccurrences(of: "）", with: "")
        .replacingOccurrences(of: "ー", with: "")
        .replacingOccurrences(of: "－", with: "")
        .replacingOccurrences(of: "—", with: "")
        .replacingOccurrences(of: "〜", with: "")
    return "title_\(normalized)"
}

private struct ProfileMissionItem: Identifiable {
    let id: String
    let target: Int
    let title: String
    let frameID: String
    let rewardTitle: String
    let progress: Int

    var isCompleted: Bool {
        progress >= target
    }
}

private func frameAssetName(for frameID: String) -> String {
    let normalized = frameID
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "・", with: "")
        .replacingOccurrences(of: "／", with: "")
        .replacingOccurrences(of: "（", with: "")
        .replacingOccurrences(of: "）", with: "")
        .replacingOccurrences(of: "ー", with: "")
        .replacingOccurrences(of: "－", with: "")
        .replacingOccurrences(of: "—", with: "")
        .replacingOccurrences(of: "〜", with: "")
    return "frame_\(normalized)"
}

// フレームごとのオフセット値（ProfileView用）
private func frameOffset(for frameID: String) -> CGSize {
    switch frameID {
    case "level_10":
        return CGSize(width: -7, height: -7)
    case "level_20":
        return CGSize(width: 10, height: -9)
    case "level_50":
        return CGSize(width: -4.5, height: 1)
    case "post_10":
        return CGSize(width: -7, height: -3)  // もう少し左に移動
    case "post_40":
        return CGSize(width: 12, height: -3)
    case "post_50":
        return CGSize(width: 0, height: -10)
    case "support_5":
        return CGSize(width: -3, height: -2)
    case "comment_10":
        return CGSize(width: -2, height: -1)
    default:
        return CGSize(width: 0, height: 0)
    }
}

// フレームオーバーレイを作成
@ViewBuilder
private func frameOverlay(frameID: String?, size: CGFloat) -> some View {
    if let frameID = frameID,
       let frameImage = UIImage(named: frameAssetName(for: frameID)) {
        let offset = frameOffset(for: frameID)
        Image(uiImage: frameImage)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .offset(x: offset.width, y: offset.height)
    }
}

private struct IconFrameListSheet: View {
    let frames: [String]
    let selected: String?
    let onSelect: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    private let columns = Array(repeating: GridItem(.flexible()), count: 3)

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    Button("フレームなし") {
                        onSelect(nil)
                        dismiss()
                    }
                    .foregroundColor(.secondary)

                    if frames.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "square.dashed.inset.filled")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("フレームはまだありません")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(frames, id: \.self) { frameID in
                                Button(action: {
                                    onSelect(frameID)
                                    dismiss()
                                }) {
                                    ZStack(alignment: .topTrailing) {
                                        if let image = UIImage(named: frameAssetName(for: frameID)) {
                                            Image(uiImage: image)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 130, height: 130)
                                                .offset(x: frameID == "post_40" ? 8 : 0, y: 0)
                                        } else {
                                            Image(systemName: "square.dashed.inset.filled")
                                                .font(.system(size: 28))
                                                .foregroundColor(.blue)
                                                .frame(width: 130, height: 130)
                                        }
                                        if frameID == selected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .background(Color.white.clipShape(Circle()))
                                        }
                                    }
                                    .frame(width: 130, height: 130)
                                    .padding(8)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 12)
            }
            .navigationTitle("アイコンフレーム")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

}

private struct ProfileMissionsListSheet: View {
    let levelMissions: [ProfileMissionItem]
    let mistMissions: [ProfileMissionItem]
    let postMissions: [ProfileMissionItem]
    @Environment(\.dismiss) private var dismiss

    // 全ミッションクリア判定
    private var isAllMissionsCompleted: Bool {
        let allMissions = levelMissions + mistMissions + postMissions
        return !allMissions.isEmpty && allMissions.allSatisfy { $0.isCompleted }
    }

    var body: some View {
        NavigationView {
            if isAllMissionsCompleted {
                // 全ミッションクリア時の表示
                VStack(spacing: 24) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("PERFECT")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange, .pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("全てのミッションをクリアしました！")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("ミッション")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("閉じる") {
                            dismiss()
                        }
                    }
                }
            } else {
                // 未完了ミッションがある場合の通常表示
                List {
                    Section("レベル") {
                        if isCategoryCompleted(levelMissions) {
                            completedCategoryView()
                        } else {
                            ForEach(visibleMissions(levelMissions)) { mission in
                                missionRow(mission)
                            }
                        }
                    }
                    Section("モヤ浄化") {
                        if isCategoryCompleted(mistMissions) {
                            completedCategoryView()
                        } else {
                            ForEach(visibleMissions(mistMissions)) { mission in
                                missionRow(mission)
                            }
                        }
                    }
                    Section("感情投稿") {
                        if isCategoryCompleted(postMissions) {
                            completedCategoryView()
                        } else {
                            ForEach(visibleMissions(postMissions)) { mission in
                                missionRow(mission)
                            }
                        }
                    }
                }
                .navigationTitle("ミッション")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("閉じる") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
    
    // カテゴリー全クリア判定
    private func isCategoryCompleted(_ missions: [ProfileMissionItem]) -> Bool {
        return !missions.isEmpty && missions.allSatisfy { $0.isCompleted }
    }
    
    // カテゴリー全クリア時の表示
    @ViewBuilder
    private func completedCategoryView() -> some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
                Text("コンプリート！")
                    .font(.headline)
                    .foregroundColor(.green)
            }
            .padding(.vertical, 20)
            Spacer()
        }
    }

    @ViewBuilder
    private func missionRow(_ mission: ProfileMissionItem) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                Text("報酬")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    VStack(spacing: 4) {
                        Text("フレーム")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let image = UIImage(named: frameAssetName(for: mission.frameID)) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                        } else {
                            Image(systemName: "square.dashed.inset.filled")
                                .font(.system(size: 26))
                                .foregroundColor(.blue)
                                .frame(width: 48, height: 48)
                        }
                    }
                    VStack(spacing: 4) {
                        Text("称号")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let image = UIImage(named: profileTitleAssetName(for: mission.rewardTitle)) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                        } else {
                            Image(systemName: "flag.checkered")
                                .font(.system(size: 26))
                                .foregroundColor(.orange)
                                .frame(width: 48, height: 48)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(mission.title)
                    .font(.headline)
                Text("\(mission.progress)/\(mission.target)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func visibleMissions(_ missions: [ProfileMissionItem]) -> [ProfileMissionItem] {
        // 未完了のミッションのみを表示、最大2つまで（クリアしたミッションは消える）
        let incomplete = missions.filter { !$0.isCompleted }
        return Array(incomplete.prefix(2))
    }
}

struct ProfilePostRow: View {
    let post: EmotionPost
    
    var body: some View {
        HStack(spacing: 16) {
            // 感情レベル表示
            ZStack {
                Circle()
                    .fill(emotionColor.opacity(0.3))
                    .frame(width: 60, height: 60)
                
                Text("\(post.level.rawValue)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            
            // 投稿情報
            VStack(alignment: .leading, spacing: 8) {
                Text(emotionLevelText)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // コメント表示（友達のみの投稿でコメントがある場合）
                if let comment = post.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .padding(.top, 4)
                }
                
                HStack(spacing: 16) {
                    Text(formatDate(post.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if post.supportCount > 0 {
                        HStack(spacing: 4) {
                            Text(post.isSadEmotion ? "💪" : "🤗")
                                .font(.caption)
                            Text("\(post.supportCount)")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var emotionColor: Color {
        let t = Double(post.level.rawValue + 5) / 10
        let hue = 0.62 - 0.62 * t
        return Color(hue: hue, saturation: 0.55, brightness: 0.95)
    }
    
    private var emotionLevelText: String {
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

import SwiftUI
import FirebaseFirestore

struct UserProfileView: View {
    let userID: String
    @State private var isFriend: Bool // 友達一覧から開いた場合はtrue
    @Environment(\.dismiss) private var dismiss
    
    private let firestoreService = FirestoreService()
    
    @State private var userPosts: [EmotionPost] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var friendRequestStatus: FriendRequestStatus?
    @State private var isProcessing = false
    @State private var showBlockAlert = false
    @State private var showBlockConfirmation = false
    @State private var isBlocked = false
    @State private var userName: String = "ユーザー"
    @State private var userLevel: Int = 1
    @State private var userTitle: String?
    @State private var selectedIconFrame: String?
    @State private var streakDays: Int = 0
    @State private var profileImage: UIImage?
    
    init(userID: String, isFriend: Bool = false) {
        self.userID = userID
        _isFriend = State(initialValue: isFriend)
        // 友達一覧から開いた場合は、初期状態を「友達」に設定
        if isFriend {
            _friendRequestStatus = State(initialValue: FriendRequestStatus(status: "friends", isFromMe: nil))
        } else {
            // 地図などから開いた場合は、初期状態をnilにして「友達になる」ボタンを表示
            _friendRequestStatus = State(initialValue: nil)
        }
    }
    
    var body: some View {
        ScrollView {
                VStack(spacing: 24) {
                    // プロフィールヘッダー
                    VStack(spacing: 16) {
                        // アバター
                        ZStack {
                            if let profileImage = profileImage {
                                Image(uiImage: profileImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.green.opacity(0.6), Color.blue.opacity(0.6)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 100, height: 100)
                                    .overlay(
                                        Text("👤")
                                            .font(.system(size: 50))
                                    )
                            }
                        }
                        .overlay(
                            Group {
                                if let frameID = selectedIconFrame,
                                   let frameImage = UIImage(named: frameAssetName(for: frameID)) {
                                    let offset = frameOffset(for: frameID)
                                    Image(uiImage: frameImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 195, height: 195)
                                        .offset(x: offset.width, y: offset.height)
                                }
                            }
                        )
                        .shadow(color: .black.opacity(0.2), radius: 8)
                        
                        // ユーザー名
                        Text(userDisplayName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        // レベル
                        Text("Lv \(userLevel)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        // 統計情報
                        HStack(spacing: 32) {
                            VStack(spacing: 4) {
                                Text("\(userPosts.count)")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                Text("投稿")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 8)

                        if streakDays > 1 {
                            HStack(spacing: 6) {
                                Image(systemName: "flame.fill")
                                    .foregroundColor(.orange)
                                Text("\(streakDays)日連続投稿")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            }
                            .padding(.top, 4)
                        }
                        
                        // 友達申請ボタン
                        Group {
                            if let status = friendRequestStatus {
                                if status.status == "friends" {
                                    VStack(spacing: 12) {
                                        Button(action: {}) {
                                            HStack {
                                                Image(systemName: "checkmark.circle.fill")
                                                Text("友達")
                                            }
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.green)
                                            .cornerRadius(25)
                                        }
                                        .disabled(true)
                                        
                                        Button(action: {
                                            Task {
                                                await removeFriend()
                                            }
                                        }) {
                                            HStack {
                                                Image(systemName: "person.badge.minus")
                                                Text("友達をやめる")
                                            }
                                            .font(.subheadline)
                                            .foregroundColor(.red)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(Color.red.opacity(0.1))
                                            .cornerRadius(20)
                                        }
                                        .disabled(isProcessing)
                                    }
                                } else if status.status == "pending" {
                                    if status.isFromMe == true {
                                        Button(action: {
                                            Task {
                                                await cancelFriendRequest()
                                            }
                                        }) {
                                            HStack {
                                                Image(systemName: "clock.fill")
                                                Text("申請中")
                                            }
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.gray)
                                            .cornerRadius(25)
                                        }
                                        .disabled(isProcessing)
                                    } else {
                                        // 相手からの申請を承認/拒否できる状態
                                        HStack(spacing: 12) {
                                            Button(action: {
                                                Task {
                                                    await acceptFriendRequest()
                                                }
                                            }) {
                                                HStack {
                                                    Image(systemName: "checkmark.circle.fill")
                                                    Text("承認")
                                                }
                                                .font(.headline)
                                                .foregroundColor(.white)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(Color.green)
                                                .cornerRadius(25)
                                            }
                                            .disabled(isProcessing)
                                            
                                            Button(action: {
                                                Task {
                                                    await rejectFriendRequest()
                                                }
                                            }) {
                                                HStack {
                                                    Image(systemName: "xmark.circle.fill")
                                                    Text("拒否")
                                                }
                                                .font(.headline)
                                                .foregroundColor(.white)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(Color.red)
                                                .cornerRadius(25)
                                            }
                                            .disabled(isProcessing)
                                        }
                                    }
                                } else {
                                    // 予期しない状態の場合は「友達になる」ボタンを表示
                                    Button(action: {
                                        Task {
                                            await sendFriendRequest()
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "person.badge.plus")
                                            Text("友達になる")
                                        }
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.blue)
                                        .cornerRadius(25)
                                    }
                                    .disabled(isProcessing)
                                }
                            } else {
                                // 友達申請ボタン（friendRequestStatusがnilの場合）
                                Button(action: {
                                    Task {
                                        await sendFriendRequest()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "person.badge.plus")
                                        Text("友達になる")
                                    }
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.blue)
                                    .cornerRadius(25)
                                }
                                .disabled(isProcessing)
                            }
                        }
                        
                        // ブロックボタン（自分のプロフィールでない場合）
                        if userID != UserService.shared.currentUserID {
                            Button(action: {
                                if isBlocked {
                                    showBlockConfirmation = true
                                } else {
                                    showBlockAlert = true
                                }
                            }) {
                                HStack {
                                    Image(systemName: isBlocked ? "hand.raised.slash.fill" : "hand.raised.slash")
                                    Text(isBlocked ? "ブロック解除" : "ユーザーをブロック")
                                }
                                .font(.subheadline)
                                .foregroundColor(isBlocked ? .blue : .red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(isBlocked ? Color.blue.opacity(0.1) : Color.red.opacity(0.1))
                                .cornerRadius(20)
                            }
                            .disabled(isProcessing)
                            .padding(.top, 8)
                        }
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                    .padding(.horizontal)
                    
                    // 投稿一覧（友達の場合のみ表示）
                    if friendRequestStatus?.status == "friends" {
                        if isLoading {
                            ProgressView()
                                .padding()
                        } else if userPosts.isEmpty {
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
                                ForEach(userPosts) { post in
                                    ProfilePostRow(post: post)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .navigationTitle("プロフィール")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadData()
            }
            .alert("ユーザーをブロック", isPresented: $showBlockAlert) {
                Button("ブロックする", role: .destructive) {
                    Task {
                        await blockUser()
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("このユーザーをブロックすると、このユーザーの投稿があなたのフィードから即座に非表示になります。友達関係も解除されます。")
            }
            .alert("ブロックを解除", isPresented: $showBlockConfirmation) {
                Button("解除する") {
                    Task {
                        await unblockUser()
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("このユーザーのブロックを解除しますか？")
            }
    }
    
    private func loadData() async {
        isLoading = true
        errorMessage = nil
        
        // ブロック状態を確認
        do {
            let blocked = try await firestoreService.isUserBlocked(userID: userID)
            await MainActor.run {
                isBlocked = blocked
            }
        } catch {
            print("⚠️ ブロック状態の確認に失敗: \(error.localizedDescription)")
        }
        
        // 地図などから開いた場合は、まず「友達になる」ボタンを表示
        if !isFriend {
            await MainActor.run {
                friendRequestStatus = nil
                print("📋 UserProfileView - 初期状態: friendRequestStatus = nil (isFriend = false)")
            }
        }
        
        do {
            // 友達状態を先に判定（未承認時の情報露出を防ぐ）
            let status: FriendRequestStatus?
            if isFriend {
                status = FriendRequestStatus(status: "friends", isFromMe: nil)
            } else {
                status = try? await firestoreService.getFriendRequestStatus(with: userID)
            }
            let canShowPrivateProfile = (status?.status == "friends")

            if canShowPrivateProfile {
                // 友達のみ、名前/アイコン/投稿などを取得
                let posts = try await firestoreService.fetchUserPosts(userID: userID)
                let fetchedUserName = try? await firestoreService.fetchUserName(userID: userID)
                let exp = try? await firestoreService.fetchUserExperiencePoints(userID: userID)
                let frames = try? await firestoreService.fetchUserIconFrames(userID: userID)
                let titles = try? await firestoreService.fetchUserTitles(userID: userID)
                let streak = try? await firestoreService.calculateStreakDays(userID: userID)

                let imageKey = "profile_image_\(userID)"
                var latestProfileImage: UIImage? = nil
                do {
                    latestProfileImage = try await firestoreService.downloadProfileImage(userID: userID, forceServerFetch: true)
                    if let downloadedImage = latestProfileImage,
                       let imageData = downloadedImage.jpegData(compressionQuality: 0.8) {
                        UserDefaults.standard.set(imageData, forKey: imageKey)
                    } else {
                        UserDefaults.standard.removeObject(forKey: imageKey)
                    }
                } catch {
                    if let imageData = UserDefaults.standard.data(forKey: imageKey),
                       let cachedImage = UIImage(data: imageData) {
                        latestProfileImage = cachedImage
                    }
                }

                await MainActor.run {
                    userPosts = posts
                    if let fetchedUserName = fetchedUserName, !fetchedUserName.isEmpty {
                        userName = fetchedUserName
                    } else {
                        userName = "ユーザー"
                    }
                    if let exp = exp {
                        userLevel = levelFromExperience(exp)
                    } else {
                        userLevel = 1
                    }
                    if let selected = frames?.selected, !selected.isEmpty {
                        selectedIconFrame = selected
                    } else {
                        selectedIconFrame = nil
                    }
                    if let titles = titles, !titles.isEmpty {
                        userTitle = titles.first
                    } else {
                        userTitle = nil
                    }
                    streakDays = streak ?? 0
                    profileImage = latestProfileImage
                    friendRequestStatus = status
                    isLoading = false
                }
            } else {
                // 未承認（pending含む）は匿名表示
                await MainActor.run {
                    userPosts = []
                    userName = "ユーザー"
                    userLevel = 1
                    userTitle = nil
                    selectedIconFrame = nil
                    streakDays = 0
                    profileImage = nil
                    friendRequestStatus = status
                    isLoading = false
                }
            }
        } catch {
            print("❌ UserProfileView - データ取得エラー: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = "データの取得に失敗しました: \(error.localizedDescription)"
                // エラー時でも、友達関係が解除された場合は「友達になる」ボタンを表示
                if !isFriend {
                    friendRequestStatus = nil
                    print("📋 UserProfileView - エラー時: friendRequestStatus = nil")
                }
                isLoading = false
            }
        }
    }
    
    private func sendFriendRequest() async {
        isProcessing = true
        errorMessage = nil
        
        do {
            try await firestoreService.sendFriendRequest(to: userID)
            
            // 通知は申請を受けた側（相手）に送られるべきなので、ここでは送信しない
            // 実際の実装では、Firestoreのリスナーで検知して相手のデバイスに通知を送る必要があります
            
            // 状態を更新
            await MainActor.run {
                friendRequestStatus = FriendRequestStatus(status: "pending", isFromMe: true)
                isProcessing = false
            }
        } catch {
            // エラーが発生した場合は、状態を再読み込みしてボタンの表示を更新
            await MainActor.run {
                isProcessing = false
            }
            // 状態を再読み込み（友達関係が既にある場合など、ボタンが「友達」に変わる）
            await loadData()
        }
    }
    
    private func acceptFriendRequest() async {
        isProcessing = true
        
        do {
            // 保留中の申請を取得
            let requests = try await firestoreService.fetchPendingFriendRequests()
            if let request = requests.first(where: { $0.fromUserID == userID }) {
                try await firestoreService.acceptFriendRequest(requestID: request.id)
                
                // 通知を送信
                NotificationService.shared.sendFriendAcceptedNotification()
                
                // 状態を更新
                await MainActor.run {
                    friendRequestStatus = FriendRequestStatus(status: "friends", isFromMe: nil)
                    isProcessing = false
                }
                
                // ユーザーデータを再読み込み（名前や投稿を表示するため）
                await loadData()
            }
        } catch {
            await MainActor.run {
                errorMessage = "友達申請の承認に失敗しました: \(error.localizedDescription)"
                isProcessing = false
            }
        }
    }
    
    private var userDisplayName: String {
        // 友達でない場合は「ユーザー」と表示
        if friendRequestStatus?.status == "friends" {
            return userName
        } else {
            return "ユーザー"
        }
    }

    private func blockUser() async {
        isProcessing = true
        
        do {
            try await firestoreService.blockUser(blockedUserID: userID)
            await MainActor.run {
                isBlocked = true
                isProcessing = false
                // ブロック後は友達関係も解除されるので、状態をリセット
                friendRequestStatus = nil
            }
        } catch {
            await MainActor.run {
                errorMessage = "ユーザーのブロックに失敗しました: \(error.localizedDescription)"
                isProcessing = false
            }
        }
    }
    
    private func unblockUser() async {
        isProcessing = true
        
        do {
            try await firestoreService.unblockUser(blockedUserID: userID)
            await MainActor.run {
                isBlocked = false
                isProcessing = false
            }
            // ブロック解除後、友達関係を再確認
            await loadData()
        } catch {
            await MainActor.run {
                errorMessage = "ブロック解除に失敗しました: \(error.localizedDescription)"
                isProcessing = false
            }
        }
    }
    
    private func levelFromExperience(_ experience: Int) -> Int {
        max(1, experience / 100 + 1)
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
    
    // フレームごとのオフセット値（大きいサイズ用）
    private func frameOffset(for frameID: String) -> CGSize {
        switch frameID {
        case "level_10":
            return CGSize(width: -8, height: -8)
        case "level_20":
            return CGSize(width: 12, height: -10)
        case "level_50":
            return CGSize(width: -5.5, height: 0)
        case "post_10":
            return CGSize(width: -8, height: -6)  // さらに右に移動
        case "post_40":
            return CGSize(width: 14, height: -4)
        case "post_50":
            return CGSize(width: 0, height: -12)
        case "support_5":
            return CGSize(width: -6, height: -4)
        case "comment_10":
            return CGSize(width: -4, height: -2)
        default:
            return CGSize(width: 0, height: 0)
        }
    }
    
    private func rejectFriendRequest() async {
        isProcessing = true
        
        do {
            // 保留中の申請を取得
            let requests = try await firestoreService.fetchPendingFriendRequests()
            if let request = requests.first(where: { $0.fromUserID == userID }) {
                try await firestoreService.rejectFriendRequest(requestID: request.id)
                
                // 状態を更新
                await MainActor.run {
                    friendRequestStatus = nil
                    isProcessing = false
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "友達申請の拒否に失敗しました: \(error.localizedDescription)"
                isProcessing = false
            }
        }
    }
    
    private func removeFriend() async {
        isProcessing = true
        
        do {
            try await firestoreService.removeFriendship(with: userID)
            
            // 友達関係を解除したので、isFriendフラグをfalseにする
            await MainActor.run {
                isFriend = false
                // 友達解除後は、すぐに「友達になる」ボタンを表示するためにnilに設定
                friendRequestStatus = nil
                isProcessing = false
            }
            
            // データを再読み込み（友達申請の状態を再確認して「友達になる」ボタンを表示）
            await loadData()
        } catch {
            await MainActor.run {
                errorMessage = "友達関係の解除に失敗しました: \(error.localizedDescription)"
                isFriend = false
                // エラーが発生しても、友達関係は解除されたので「友達になる」ボタンを表示
                friendRequestStatus = nil
                isProcessing = false
            }
        }
    }
    
    // 友達申請を取り消す（改善版: FirestoreServiceを使用）
    private func cancelFriendRequest() async {
        isProcessing = true
        
        do {
            // FirestoreServiceの関数を使用して、友達申請と通知を削除
            try await firestoreService.cancelFriendRequest(to: userID)
            
            // 状態を更新（「友達になる」ボタンに戻す）
            await MainActor.run {
                friendRequestStatus = nil
                isProcessing = false
            }
            
            print("✅ 友達申請を取り消しました（通知も削除済み）")
        } catch {
            await MainActor.run {
                errorMessage = "友達申請の取り消しに失敗しました: \(error.localizedDescription)"
                isProcessing = false
            }
            print("❌ 友達申請の取り消しに失敗: \(error.localizedDescription)")
        }
    }
}

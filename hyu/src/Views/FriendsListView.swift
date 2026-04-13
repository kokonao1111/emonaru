import SwiftUI

struct FriendsListView: View {
    private let firestoreService = FirestoreService()
    
    @State private var friends: [Friend] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var refreshID = UUID() // 画像更新用
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding()
                } else if friends.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("友達がいません")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(friends) { friend in
                        FriendRow(friend: friend, refreshID: refreshID)
                    }
                }
            }
            .navigationTitle("友達")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .refreshable {
                // プロフィール画像のキャッシュをクリア
                clearFriendsImageCache()
                await loadFriends()
                // 画像を再読み込み
                refreshID = UUID()
            }
            .task {
                await loadFriends()
            }
        }
    }
    
    private func loadFriends() async {
        print("\n========================================")
        print("👥 友達一覧の読み込み開始")
        print("========================================")
        
        isLoading = true
        errorMessage = nil
        
        do {
            let friendList = try await firestoreService.fetchFriends()
            print("\n✅ 友達一覧を取得成功: \(friendList.count)人")
            for (index, friend) in friendList.enumerated() {
                print("   \(index + 1). \(friend.username) (\(friend.userID))")
            }
            await MainActor.run {
                friends = friendList
                isLoading = false
            }
            print("\n各友達のプロフィール画像を順次読み込みます...")
        } catch {
            print("\n❌ 友達の取得エラー: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = "友達の取得に失敗しました: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func clearFriendsImageCache() {
        print("\n🗑️ プロフィール画像キャッシュのクリア開始")
        // 友達のプロフィール画像キャッシュをクリア
        for friend in friends {
            let imageKey = "profile_image_\(friend.userID)"
            UserDefaults.standard.removeObject(forKey: imageKey)
            print("   - クリア: \(friend.username)")
        }
        print("✅ 友達のプロフィール画像キャッシュをクリアしました (\(friends.count)人)\n")
    }
}

struct FriendRow: View {
    let friend: Friend
    let refreshID: UUID
    @State private var showUserProfile = false
    @State private var profileImage: UIImage?
    @State private var selectedIconFrame: String?
    
    private let firestoreService = FirestoreService()
    
    var body: some View {
        Button(action: {
            showUserProfile = true
        }) {
            HStack(spacing: 16) {
                // アバター（プロフィール画像 + アイコンフレーム）
                ZStack {
                    if let profileImage = profileImage {
                        Image(uiImage: profileImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
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
                            .frame(width: 50, height: 50)
                            .overlay(
                                Text("👤")
                                    .font(.system(size: 25))
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
                                .frame(width: 97.5, height: 97.5)
                                .offset(x: offset.width, y: offset.height)
                        }
                    }
                )
                
                // ユーザー情報
                VStack(alignment: .leading, spacing: 4) {
                    Text(friend.username)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("友達になった日: \(formatDate(friend.createdAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .task {
            await loadUserData()
        }
        .onChange(of: refreshID) { _, _ in
            // 画像とフレームをクリアして再読み込み
            profileImage = nil
            selectedIconFrame = nil
            Task {
                await loadUserData()
            }
        }
        .sheet(isPresented: $showUserProfile) {
            NavigationView {
                UserProfileView(userID: friend.userID, isFriend: true)
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
    
    private func loadUserData() async {
        print("\n👤 友達データの読み込み開始")
        print("   - 友達: \(friend.username)")
        print("   - ユーザーID: \(friend.userID)")
        
        // プロフィール画像を読み込む（強制的にサーバーから最新をダウンロード）
        let imageKey = "profile_image_\(friend.userID)"
        
        do {
            // forceServerFetch: trueで必ずサーバーから最新の画像URLと画像を取得
            if let downloadedImage = try await firestoreService.downloadProfileImage(userID: friend.userID, forceServerFetch: true) {
                // ダウンロードした画像をローカルに保存（キャッシュ更新）
                if let imageData = downloadedImage.jpegData(compressionQuality: 0.8) {
                    let cacheSize = imageData.count
                    UserDefaults.standard.set(imageData, forKey: imageKey)
                    print("💾 キャッシュに保存: \(cacheSize) bytes")
                }
                await MainActor.run {
                    profileImage = downloadedImage
                }
                print("✅ 友達のプロフィール画像を最新に更新完了: \(friend.username)")
            } else {
                // プロフィール画像が設定されていない場合、キャッシュをクリア
                print("ℹ️ プロフィール画像なし - キャッシュをクリア")
                UserDefaults.standard.removeObject(forKey: imageKey)
                await MainActor.run {
                    profileImage = nil
                }
            }
        } catch {
            // ネットワークエラーなどの場合のみキャッシュを使用
            print("⚠️ プロフィール画像のダウンロードに失敗")
            print("   - エラー: \(error.localizedDescription)")
            if let imageData = UserDefaults.standard.data(forKey: imageKey),
               let image = UIImage(data: imageData) {
                print("💾 キャッシュから復元: \(imageData.count) bytes")
                await MainActor.run {
                    profileImage = image
                }
            } else {
                print("⚠️ キャッシュも見つかりませんでした")
            }
        }
        
        // アイコンフレームを読み込む
        print("\n🖼️ アイコンフレームの読み込み開始")
        do {
            let (frames, selected) = try await firestoreService.fetchUserIconFrames(userID: friend.userID)
            print("✅ アイコンフレーム取得成功")
            print("   - 所持フレーム数: \(frames.count)")
            print("   - 選択中: \(selected ?? "なし")")
            await MainActor.run {
                if let selected = selected, !selected.isEmpty {
                    selectedIconFrame = selected
                    print("✅ フレームを表示: \(selected)")
                } else {
                    print("ℹ️ フレーム未選択")
                }
            }
        } catch {
            print("❌ アイコンフレームの取得に失敗")
            print("   - エラー: \(error.localizedDescription)")
        }
        
        print("✅ 友達データの読み込み完了\n")
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
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
    
    // フレームごとのオフセット値
    private func frameOffset(for frameID: String) -> CGSize {
        // フレームIDに応じてオフセットを返す
        // 必要に応じて個別に調整してください
        switch frameID {
        case "level_10":
            return CGSize(width: -5, height: -5)
        case "level_20":
            return CGSize(width: 6, height: -6)
        case "level_50":
            return CGSize(width: -3.5, height: 1)
        case "post_10":
            return CGSize(width: -3, height: -1)  // 左に移動
        case "post_40":
            return CGSize(width: 9, height: -2)
        case "post_50":
            return CGSize(width: 0, height: -8)
        case "support_5":
            return CGSize(width: -3, height: -2)
        case "comment_10":
            return CGSize(width: -2, height: -1)
        default:
            return CGSize(width: 0, height: 0)  // デフォルトはオフセットなし
        }
    }
}

// MARK: - 友達モデル

struct Friend: Identifiable {
    let id: String
    let userID: String
    let username: String
    let createdAt: Date
}

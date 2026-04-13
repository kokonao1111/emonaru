import SwiftUI

struct AdminPostListView: View {
    @State private var posts: [EmotionPost] = []
    @State private var userNameByID: [String: String] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText: String = ""

    private let firestoreService = FirestoreService()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            ForEach(filteredPosts) { post in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Lv \(post.level.rawValue)")
                            .font(.headline)
                        Spacer()
                        Text(dateFormatter.string(from: post.createdAt))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let comment = post.comment, !comment.isEmpty {
                        Text(comment)
                            .font(.subheadline)
                    } else {
                        Text("コメントなし")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Text("投稿者: \(displayAuthorLabel(for: post))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let latitude = post.latitude, let longitude = post.longitude {
                        Text("lat: \(latitude), lon: \(longitude)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await deletePost(post) }
                    } label: {
                        Text("削除")
                    }
                }
            }
        }
        .navigationTitle("投稿管理")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "コメント/投稿者ID/ユーザー名で検索")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("更新") {
                    Task { await loadPosts() }
                }
                .disabled(isLoading)
            }
        }
        .task {
            await loadPosts()
        }
    }

    private func loadPosts() async {
        isLoading = true
        errorMessage = nil
        do {
            async let fetchedPosts = firestoreService.fetchAllPosts(limit: 200)
            async let fetchedUsers = firestoreService.fetchAllUsers()
            let fetched = try await fetchedPosts
            let users = try await fetchedUsers
            let userMap = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0.userName ?? "-") })
            await MainActor.run {
                posts = fetched
                userNameByID = userMap
            }
        } catch {
            errorMessage = "投稿の取得に失敗しました"
        }
        isLoading = false
    }

    private func deletePost(_ post: EmotionPost) async {
        do {
            try await firestoreService.adminDeletePost(postID: post.id)
            await loadPosts()
        } catch {
            errorMessage = "投稿の削除に失敗しました"
        }
    }

    private var filteredPosts: [EmotionPost] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return posts }
        return posts.filter { post in
            let commentMatch = (post.comment ?? "").localizedCaseInsensitiveContains(keyword)
            let authorMatch = (post.authorID ?? "").localizedCaseInsensitiveContains(keyword)
            let userNameMatch: Bool = {
                guard let authorID = post.authorID else { return false }
                return (userNameByID[authorID] ?? "").localizedCaseInsensitiveContains(keyword)
            }()
            return commentMatch || authorMatch || userNameMatch
        }
    }

    private func displayAuthorLabel(for post: EmotionPost) -> String {
        guard let authorID = post.authorID else { return "-" }
        let userName = userNameByID[authorID] ?? "-"
        return "\(userName) (\(authorID))"
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }
}

import SwiftUI

struct TimelinePageView: View {
    private let firestoreService = FirestoreService()
    let onPostTapped: (EmotionPost) -> Void
    
    @State private var posts: [EmotionPost] = []
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var timelineContentHeight: CGFloat = UIScreen.main.bounds.height

    var body: some View {
        ZStack {
            // 背景を真っ黒に
            Color.black
                .ignoresSafeArea()
            
            // HTML/CSSタイムラインのみを使用
            ScrollView(.vertical, showsIndicators: true) {
                HTMLTimelineView(posts: sortedPosts, contentHeight: $timelineContentHeight, onPostTapped: onPostTapped)
                    .frame(height: timelineContentHeight, alignment: .top)
                    .frame(maxWidth: .infinity)
                    .id("timeline-content") // IDを設定してスクロール位置の安定化を図る
            }
            .padding(.top, 60)
            .refreshable {
                await refreshPosts()
            }

            VStack {
                // エラーメッセージ表示
                if let errorMessage = errorMessage {
                    VStack(spacing: 8) {
                        HStack {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .lineLimit(3)
                            Button(action: {
                                self.errorMessage = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.95))
                        .cornerRadius(12)
                        .shadow(radius: 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Spacer()
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .task {
            await loadPosts()
        }
    }
    
    private var sortedPosts: [EmotionPost] {
        // 新着順（作成日時の降順）
        posts.sorted { $0.createdAt > $1.createdAt }
    }
    
    private func loadPosts() async {
        do {
            let fetchedPosts = try await firestoreService.fetchRecentEmotions(lastHours: 24)
            await MainActor.run {
                // 24時間以内の投稿のみを表示し、自分の投稿は除外
                let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
                let currentUserID = UserService.shared.currentUserID
                let filteredPosts = fetchedPosts.filter { post in
                    // 時間制限チェック
                    guard post.createdAt >= cutoff else { return false }
                    // 自分の投稿を除外（authorIDがnilまたは現在のユーザーIDと一致する場合は除外）
                    if let authorID = post.authorID {
                        return authorID != currentUserID
                    }
                    // authorIDがnilの場合は表示しない（安全のため）
                    return false
                }
                
                posts = filteredPosts
                
                // 投稿が表示されたときに閲覧を記録（友達の場合のみ通知を送る）
                Task {
                    for post in filteredPosts {
                        if let authorID = post.authorID {
                            await firestoreService.recordPostView(postID: post.id, authorID: authorID)
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "データの取得に失敗しました: \(error.localizedDescription)"
            }
        }
    }
    
    private func refreshPosts() async {
        isRefreshing = true
        await loadPosts()
        isRefreshing = false
    }
}

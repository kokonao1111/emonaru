import SwiftUI

struct MyPostsHistoryView: View {
    @State private var posts: [EmotionPost]
    @Environment(\.dismiss) private var dismiss
    @State private var isDeleting = false
    @State private var errorMessage: String?
    
    private let firestoreService = FirestoreService()
    
    init(posts: [EmotionPost]) {
        _posts = State(initialValue: posts)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // 常に黒い背景
                Color.black
                    .ignoresSafeArea()
                
                List {
                    if sortedPosts.isEmpty {
                        VStack(spacing: 16) {
                            Text("📝")
                                .font(.system(size: 60))
                            Text("まだ投稿がありません")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(sortedPosts) { post in
                            TimelinePostRow(post: post)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.black)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Task {
                                            await deletePost(post)
                                        }
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("自分の投稿履歴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .alert("エラー", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }
    
    private var sortedPosts: [EmotionPost] {
        // 新着順（作成日時の降順）
        posts.sorted { $0.createdAt > $1.createdAt }
    }
    
    private func deletePost(_ post: EmotionPost) async {
        guard !isDeleting else { return }
        
        isDeleting = true
        errorMessage = nil
        
        do {
            try await firestoreService.deletePost(postID: post.id)
            
            // リストから削除
            await MainActor.run {
                posts.removeAll { $0.id == post.id }
            }
        } catch {
            await MainActor.run {
                errorMessage = "投稿の削除に失敗しました: \(error.localizedDescription)"
            }
        }
        
        isDeleting = false
    }
}

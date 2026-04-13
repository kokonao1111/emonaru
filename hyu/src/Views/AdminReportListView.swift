import SwiftUI
import FirebaseFirestore

struct AdminReportListView: View {
    @State private var reports: [[String: Any]] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var postAuthors: [String: String] = [:] // postID: authorID
    @State private var userNames: [String: String] = [:] // userID: userName
    @State private var posts: [String: EmotionPost] = [:] // postID: post
    
    private let firestoreService = FirestoreService()
    
    var body: some View {
        List {
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            if reports.isEmpty && !isLoading {
                Text("報告された投稿はありません")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
            
            ForEach(Array(reports.enumerated()), id: \.offset) { index, report in
                VStack(alignment: .leading, spacing: 12) {
                    // ヘッダー
                    HStack {
                        Text("報告 #\(index + 1)")
                            .font(.headline)
                            .foregroundColor(.red)
                        Spacer()
                        if let createdAt = (report["createdAt"] as? Timestamp)?.dateValue() {
                            Text(formatDate(createdAt))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // 投稿内容
                    if let postID = report["postID"] as? String,
                       let post = posts[postID] {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("投稿内容")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fontWeight(.semibold)
                            
                            HStack(spacing: 12) {
                                // 感情レベル
                                Text(emotionText(for: post.level))
                                    .font(.title2)
                                    .foregroundColor(emotionColor(for: post.level))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("感情レベル: \(post.level.rawValue)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    if let comment = post.comment, !comment.isEmpty {
                                        Text("「\(comment)」")
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    
                    Divider()
                    
                    // 投稿者
                    if let postID = report["postID"] as? String,
                       let authorID = postAuthors[postID] {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("投稿者")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(userNames[authorID] ?? authorID)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    // 報告者
                    if let reporterID = report["reporterID"] as? String {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("報告者")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(userNames[reporterID] ?? reporterID)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // 報告理由
                    VStack(alignment: .leading, spacing: 4) {
                        Text("報告理由")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontWeight(.semibold)
                        Text(report["reason"] as? String ?? "-")
                            .font(.body)
                            .foregroundColor(.red)
                    }
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            Task {
                                await deletePost(reportID: report["reportID"] as? String ?? "", postID: report["postID"] as? String ?? "")
                            }
                        }) {
                            Text("投稿を削除")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red)
                                .cornerRadius(8)
                        }
                        
                        Button(action: {
                            Task {
                                await dismissReport(reportID: report["reportID"] as? String ?? "")
                            }
                        }) {
                            Text("報告を却下")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.gray)
                                .cornerRadius(8)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("報告された投稿")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("更新") {
                    Task {
                        await loadReports()
                    }
                }
                .disabled(isLoading)
            }
        }
        .task {
            await loadReports()
        }
    }
    
    private func loadReports() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let fetchedReports = try await firestoreService.getReportedPosts()
            
            // 各投稿の投稿者IDと投稿内容を取得
            var authors: [String: String] = [:]
            var fetchedPosts: [String: EmotionPost] = [:]
            var userIDs: Set<String> = []
            
            for report in fetchedReports {
                if let postID = report["postID"] as? String,
                   let uuid = UUID(uuidString: postID) {
                    if let post = try? await firestoreService.fetchPost(postID: uuid) {
                        authors[postID] = post.authorID
                        fetchedPosts[postID] = post
                        if let authorID = post.authorID {
                            userIDs.insert(authorID)
                        }
                    }
                }
                
                // 報告者IDも収集
                if let reporterID = report["reporterID"] as? String {
                    userIDs.insert(reporterID)
                }
            }
            
            // ユーザー名を取得
            var names: [String: String] = [:]
            for userID in userIDs {
                if let user = try? await firestoreService.fetchUserProfile(userID: userID) {
                    names[userID] = user["userName"] as? String ?? "ユーザー"
                }
            }
            
            await MainActor.run {
                reports = fetchedReports
                postAuthors = authors
                posts = fetchedPosts
                userNames = names
                isLoading = false
                print("✅ 報告を読み込み: \(fetchedReports.count)件、投稿: \(fetchedPosts.count)件、ユーザー名: \(names.count)人")
            }
        } catch {
            await MainActor.run {
                errorMessage = "報告の取得に失敗しました: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func deletePost(reportID: String, postID: String) async {
        do {
            // 投稿を削除
            if let uuid = UUID(uuidString: postID) {
                try await firestoreService.adminDeletePost(postID: uuid)
            }
            
            // 報告を解決済みにする
            try await firestoreService.resolveReport(reportID: reportID, action: "投稿を削除")
            
            // リストを更新
            await loadReports()
        } catch {
            await MainActor.run {
                errorMessage = "投稿の削除に失敗しました: \(error.localizedDescription)"
            }
        }
    }
    
    private func dismissReport(reportID: String) async {
        do {
            try await firestoreService.resolveReport(reportID: reportID, action: "報告を却下")
            await loadReports()
        } catch {
            await MainActor.run {
                errorMessage = "報告の処理に失敗しました: \(error.localizedDescription)"
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
    
    private func emotionText(for level: EmotionLevel) -> String {
        switch level.rawValue {
        case -5: return "😭"
        case -4: return "😢"
        case -3: return "😔"
        case -2: return "😞"
        case -1: return "😕"
        case 0: return "😐"
        case 1: return "🙂"
        case 2: return "😊"
        case 3: return "😄"
        case 4: return "😆"
        case 5: return "🤩"
        default: return "😐"
        }
    }
    
    private func emotionColor(for level: EmotionLevel) -> Color {
        if level.rawValue < 0 {
            return .blue
        } else if level.rawValue > 0 {
            return .orange
        } else {
            return .gray
        }
    }
}

#Preview {
    NavigationView {
        AdminReportListView()
    }
}

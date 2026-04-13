import SwiftUI

struct FriendRequestsView: View {
    private let firestoreService = FirestoreService()
    
    @State private var friendRequests: [FriendRequest] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
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
                } else if friendRequests.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("友達申請はありません")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(friendRequests) { request in
                        FriendRequestRow(request: request) {
                            await loadFriendRequests()
                        }
                    }
                }
            }
            .navigationTitle("友達申請")
            .refreshable {
                await loadFriendRequests()
            }
            .task {
                await loadFriendRequests()
            }
        }
    }
    
    private func loadFriendRequests() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let requests = try await firestoreService.fetchPendingFriendRequests()
            await MainActor.run {
                friendRequests = requests
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "友達申請の取得に失敗しました: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}

struct FriendRequestRow: View {
    let request: FriendRequest
    let onUpdate: () async -> Void
    
    private let firestoreService = FirestoreService()
    
    @State private var isProcessing = false
    
    var body: some View {
        HStack(spacing: 16) {
            // アバター
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
            
            // ユーザー情報
            VStack(alignment: .leading, spacing: 4) {
                Text(userDisplayName(request.fromUserID))
                    .font(.headline)
                Text(formatDate(request.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 承認/拒否ボタン
            if isProcessing {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                HStack(spacing: 8) {
                    Button(action: {
                        Task {
                            await acceptRequest()
                        }
                    }) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                    }
                    
                    Button(action: {
                        Task {
                            await rejectRequest()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.title2)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func acceptRequest() async {
        isProcessing = true
        
        do {
            try await firestoreService.acceptFriendRequest(requestID: request.id)
            
            // 通知を送信
            NotificationService.shared.sendFriendAcceptedNotification()
            
            await onUpdate()
        } catch {
            print("友達申請の承認に失敗しました: \(error.localizedDescription)")
        }
        
        isProcessing = false
    }
    
    private func rejectRequest() async {
        isProcessing = true
        
        do {
            try await firestoreService.rejectFriendRequest(requestID: request.id)
            await onUpdate()
        } catch {
            print("友達申請の拒否に失敗しました: \(error.localizedDescription)")
        }
        
        isProcessing = false
    }
    
    private func userDisplayName(_ userID: String) -> String {
        return "ユーザー"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

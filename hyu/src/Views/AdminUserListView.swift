import SwiftUI

struct AdminUserListView: View {
    @State private var users: [AdminUser] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var searchText: String = ""
    @State private var targetUserForPostGrant: AdminUser?
    @State private var postGrantAmountText: String = "1"

    private let firestoreService = FirestoreService()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            if let successMessage {
                Text(successMessage)
                    .font(.caption)
                    .foregroundColor(.green)
            }

            ForEach(filteredUsers, id: \.id) { user in
                VStack(alignment: .leading, spacing: 6) {
                    Text(user.userName ?? "ユーザー")
                        .font(.headline)
                    Text("ID: \(user.id)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if user.isFrozen {
                        Text("凍結中")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                    if user.isBanned {
                        Text("BAN中")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                    if user.bannedDeviceCount > 0 {
                        Text("BAN端末: \(user.bannedDeviceCount)台")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text("投稿可能回数の累計付与: +\(user.grantedPostLimitBonusTotal)回")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let updatedAt = user.updatedAt {
                        Text("更新: \(dateFormatter.string(from: updatedAt))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Toggle("公開アカウント", isOn: bindingForPublicAccount(userID: user.id))
                    Toggle("凍結", isOn: bindingForFrozen(userID: user.id))
                    Toggle("BAN", isOn: bindingForBanned(userID: user.id))
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        targetUserForPostGrant = user
                        postGrantAmountText = "1"
                    } label: {
                        Text("投稿可能回数付与")
                    }
                    .tint(.orange)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await deleteUser(user) }
                    } label: {
                        Text("削除")
                    }
                }
            }
        }
        .navigationTitle("ユーザー管理")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "ユーザー名/IDで検索")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("更新") {
                    Task { await loadUsers() }
                }
                .disabled(isLoading)
            }
        }
        .task {
            await loadUsers()
        }
        .sheet(item: $targetUserForPostGrant) { user in
            PostLimitGrantSheetView(
                user: user,
                amountText: $postGrantAmountText,
                onSubmit: { userID, amount in
                    Task { await grantPostLimitBonus(userID: userID, addCount: amount) }
                }
            )
        }
    }

    private func loadUsers() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await firestoreService.fetchAllUsers()
            await MainActor.run {
                users = fetched
            }
        } catch {
            errorMessage = "ユーザーの取得に失敗しました"
        }
        isLoading = false
    }

    private func updatePublicAccount(userID: String, isPublic: Bool) async {
        do {
            try await firestoreService.updateUserPublicAccount(userID: userID, isPublicAccount: isPublic)
        } catch {
            errorMessage = "ユーザーの更新に失敗しました"
            await loadUsers()
        }
    }

    private func updateFrozen(userID: String, isFrozen: Bool) async {
        do {
            try await firestoreService.updateUserFrozen(userID: userID, isFrozen: isFrozen)
        } catch {
            errorMessage = "ユーザーの更新に失敗しました"
            await loadUsers()
        }
    }

    private func updateBanned(userID: String, isBanned: Bool) async {
        do {
            try await firestoreService.updateUserBanned(userID: userID, isBanned: isBanned)
        } catch {
            errorMessage = "ユーザーの更新に失敗しました"
            await loadUsers()
        }
    }

    private func deleteUser(_ user: AdminUser) async {
        do {
            try await firestoreService.deleteUser(userID: user.id)
            successMessage = nil
            await loadUsers()
        } catch {
            errorMessage = "ユーザーの削除に失敗しました"
        }
    }

    private func grantPostLimitBonus(userID: String, addCount: Int) async {
        guard addCount > 0 else {
            errorMessage = "付与回数は1以上で入力してください"
            return
        }
        guard let index = users.firstIndex(where: { $0.id == userID }) else {
            errorMessage = "対象ユーザーが見つかりません"
            return
        }

        do {
            try await firestoreService.grantPostLimitBonusToUser(userID: userID, amount: addCount)
            await MainActor.run {
                users[index].grantedPostLimitBonusTotal += addCount
                errorMessage = nil
                successMessage = "\(users[index].userName ?? userID): 投稿可能回数 +\(addCount)回を付与しました（累計 +\(users[index].grantedPostLimitBonusTotal)回）"
                targetUserForPostGrant = nil
            }
        } catch {
            await MainActor.run {
                errorMessage = "投稿可能回数の付与に失敗しました"
                successMessage = nil
            }
        }
    }

    private var filteredUsers: [AdminUser] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return users }
        return users.filter { user in
            let name = user.userName ?? ""
            return name.localizedCaseInsensitiveContains(keyword)
                || user.id.localizedCaseInsensitiveContains(keyword)
        }
    }

    private func bindingForPublicAccount(userID: String) -> Binding<Bool> {
        Binding(
            get: { users.first(where: { $0.id == userID })?.isPublicAccount ?? true },
            set: { newValue in
                if let index = users.firstIndex(where: { $0.id == userID }) {
                    users[index].isPublicAccount = newValue
                }
                Task { await updatePublicAccount(userID: userID, isPublic: newValue) }
            }
        )
    }

    private func bindingForFrozen(userID: String) -> Binding<Bool> {
        Binding(
            get: { users.first(where: { $0.id == userID })?.isFrozen ?? false },
            set: { newValue in
                if let index = users.firstIndex(where: { $0.id == userID }) {
                    users[index].isFrozen = newValue
                }
                Task { await updateFrozen(userID: userID, isFrozen: newValue) }
            }
        )
    }

    private func bindingForBanned(userID: String) -> Binding<Bool> {
        Binding(
            get: { users.first(where: { $0.id == userID })?.isBanned ?? false },
            set: { newValue in
                if let index = users.firstIndex(where: { $0.id == userID }) {
                    users[index].isBanned = newValue
                }
                Task { await updateBanned(userID: userID, isBanned: newValue) }
            }
        )
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }
}

private struct PostLimitGrantSheetView: View {
    let user: AdminUser
    @Binding var amountText: String
    @Environment(\.dismiss) private var dismiss
    let onSubmit: (String, Int) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("対象ユーザー") {
                    Text(user.userName ?? "ユーザー")
                    Text(user.id)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("現在の累計付与: +\(user.grantedPostLimitBonusTotal)回")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("付与する投稿可能回数") {
                    TextField("付与回数（1以上）", text: $amountText)
                        .keyboardType(.numberPad)
                    Text("例: 1, 5, 10")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    Button("付与する") {
                        guard let amount = Int(amountText), amount > 0 else {
                            return
                        }
                        onSubmit(user.id, amount)
                    }
                    .disabled((Int(amountText) ?? 0) <= 0)
                }
            }
            .navigationTitle("投稿可能回数を付与")
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

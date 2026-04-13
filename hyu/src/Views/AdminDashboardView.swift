import SwiftUI

struct AdminDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var authService: AdminAuthService
    @State private var showNotificationSentAlert = false
    @State private var notificationSentMessage: String = ""
    @State private var prefectureStats: [String: Int] = [:]
    @State private var totalUsers: Int = 0
    @State private var isLoadingStats = false
    @State private var isSendingUpdateNotification = false
    @State private var isCompensatingRewards = false
    @State private var showCompensationConfirmation = false
    
    // 新機能の状態
    @State private var isResettingGauges = false
    @State private var showGaugeResetConfirmation = false
    @State private var showUserExperienceSheet = false
    @State private var showUserBanSheet = false
    @State private var showCustomNotificationSheet = false
    @State private var showUserMissionRewardSheet = false
    @State private var showMistClearSheet = false
    @State private var showEmotionPostSheet = false
    @State private var customNotificationTitle = ""
    @State private var customNotificationMessage = ""
    @State private var targetUserID = ""
    @State private var experienceAmount = ""
    @State private var banReason = ""
    @State private var missionRewardUserID = ""
    @State private var mistClearUserID = ""
    @State private var mistClearCount = ""
    @State private var emotionPostUserID = ""
    @State private var emotionPostCount = ""
    
    private let firestoreService = FirestoreService()

    var body: some View {
        List {
            // 統計情報
            Section("統計情報") {
                if isLoadingStats {
                    HStack {
                        ProgressView()
                        Text("読み込み中...")
                            .foregroundColor(.secondary)
                    }
                } else {
                    NavigationLink {
                        PrefectureStatsView(stats: prefectureStats, totalUsers: totalUsers)
                    } label: {
                        HStack {
                            Image(systemName: "map.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("都道府県別ユーザー数")
                                    .font(.body)
                                Text("合計 \(totalUsers) 人")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Section("管理") {
                NavigationLink("スポット管理") {
                    AdminSpotListView()
                }
                NavigationLink("投稿管理") {
                    AdminPostListView()
                }
                NavigationLink("ユーザー管理") {
                    AdminUserListView()
                }
                NavigationLink("報告された投稿") {
                    AdminReportListView()
                }
            }
            
            Section("通知管理") {
                Button(action: {
                    NotificationService.shared.sendManualEmotionNotification()
                    notificationSentMessage = "ランダムな感情リマインダー通知を送信しました"
                    showNotificationSentAlert = true
                }) {
                    HStack {
                        Image(systemName: "bell.fill")
                            .foregroundColor(.blue)
                        Text("ランダム通知を送信")
                        Spacer()
                        Image(systemName: "paperplane.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text("午前・午後に自動送信されるランダム通知を手動で送信します")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(action: {
                    Task {
                        await sendUpdateNotification(
                            title: "新しいアップデート！",
                            message: "アップデートが来ました！アップデートしてください"
                        )
                    }
                }) {
                    HStack {
                        Image(systemName: "megaphone.fill")
                            .foregroundColor(.orange)
                        Text("アップデート通知を送信")
                        Spacer()
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(isSendingUpdateNotification)
                
                if isSendingUpdateNotification {
                    HStack {
                        ProgressView()
                        Text("送信中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text("タップすると全ユーザーに「アップデートが来ました！アップデートしてください」という通知を送信します")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("報酬補償") {
                Button(action: {
                    showCompensationConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "gift.fill")
                            .foregroundColor(.red)
                        Text("ミッション報酬を補償")
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .disabled(isCompensatingRewards)
                
                if isCompensatingRewards {
                    HStack {
                        ProgressView()
                        Text("補償中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text("既にミッションを達成していたが報酬がもらえなかったユーザーに、報酬とお詫びの経験値50を配布します")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("ゲージ管理") {
                Button(action: {
                    showGaugeResetConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "gauge.badge.exclamationmark")
                            .foregroundColor(.orange)
                        Text("異常なゲージを一括リセット")
                        Spacer()
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(isResettingGauges)
                
                if isResettingGauges {
                    HStack {
                        ProgressView()
                        Text("リセット中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text("maxValueの2倍を超えているゲージを0にリセットします")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("ユーザー管理") {
                Button(action: {
                    showUserExperienceSheet = true
                }) {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.yellow)
                        Text("経験値を付与/削除")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: {
                    showUserBanSheet = true
                }) {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .foregroundColor(.red)
                        Text("ユーザーをBAN/復元")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: {
                    showUserMissionRewardSheet = true
                }) {
                    HStack {
                        Image(systemName: "gift.fill")
                            .foregroundColor(.green)
                        Text("ミッション報酬を再付与")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text("達成済みだが報酬が付与されていないミッションの報酬を強制的に付与します")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("ミッション進捗管理") {
                Button(action: {
                    showMistClearSheet = true
                }) {
                    HStack {
                        Image(systemName: "cloud.sun.fill")
                            .foregroundColor(.teal)
                        Text("モヤ浄化カウント設定")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: {
                    showEmotionPostSheet = true
                }) {
                    HStack {
                        Image(systemName: "note.text")
                            .foregroundColor(.orange)
                        Text("感情投稿カウント設定")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text("ユーザーのミッション進捗を設定し、達成報酬を自動付与します")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("カスタム通知") {
                Button(action: {
                    showCustomNotificationSheet = true
                }) {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.purple)
                        Text("カスタム通知を送信")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text("タイトルと本文を自由に設定して全ユーザーに通知を送信します")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .confirmationDialog("報酬補償の確認", isPresented: $showCompensationConfirmation) {
            Button("補償を実行", role: .destructive) {
                Task {
                    await compensateMissionRewards()
                }
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("既にミッション達成済みのユーザーに報酬とお詫びの経験値50を配布します。この処理は取り消せません。実行しますか？")
        }
        .confirmationDialog("ゲージリセットの確認", isPresented: $showGaugeResetConfirmation) {
            Button("リセットを実行", role: .destructive) {
                Task {
                    await resetAbnormalGauges()
                }
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("maxValueの2倍を超えているゲージを0にリセットします。この処理は取り消せません。実行しますか？")
        }
        .sheet(isPresented: $showUserExperienceSheet) {
            UserExperienceManagementView(
                userID: $targetUserID,
                amount: $experienceAmount,
                onSubmit: { userID, amount in
                    Task {
                        await addExperienceToUser(userID: userID, amount: amount)
                    }
                }
            )
        }
        .sheet(isPresented: $showUserBanSheet) {
            UserBanManagementView(
                userID: $targetUserID,
                reason: $banReason,
                onBan: { userID, reason in
                    Task {
                        await banUser(userID: userID, reason: reason)
                    }
                },
                onUnban: { userID in
                    Task {
                        await unbanUser(userID: userID)
                    }
                }
            )
        }
        .sheet(isPresented: $showCustomNotificationSheet) {
            CustomNotificationView(
                title: $customNotificationTitle,
                message: $customNotificationMessage,
                onSend: { title, message in
                    Task {
                        await sendCustomNotification(title: title, body: message)
                    }
                }
            )
        }
        .sheet(isPresented: $showUserMissionRewardSheet) {
            UserMissionRewardView(
                userID: $missionRewardUserID,
                onSubmit: { userID in
                    Task {
                        await forceAwardMissionRewards(userID: userID)
                    }
                }
            )
        }
        .sheet(isPresented: $showMistClearSheet) {
            MissionProgressView(
                userID: $mistClearUserID,
                count: $mistClearCount,
                missionType: "モヤ浄化",
                onSubmit: { userID, count in
                    Task {
                        await setMistClearCount(userID: userID, count: count)
                    }
                }
            )
        }
        .sheet(isPresented: $showEmotionPostSheet) {
            MissionProgressView(
                userID: $emotionPostUserID,
                count: $emotionPostCount,
                missionType: "感情投稿",
                onSubmit: { userID, count in
                    Task {
                        await setEmotionPostCount(userID: userID, count: count)
                    }
                }
            )
        }
        .navigationTitle("管理者画面")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("ログアウト") {
                    authService.signOut()
                    dismiss()
                }
            }
        }
        .alert("通知を送信しました", isPresented: $showNotificationSentAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(notificationSentMessage)
        }
        .onAppear {
            Task {
                await loadPrefectureStats()
            }
        }
    }
    
    private func loadPrefectureStats() async {
        isLoadingStats = true
        do {
            let stats = try await firestoreService.fetchPrefectureUserStats()
            await MainActor.run {
                prefectureStats = stats
                totalUsers = stats.values.reduce(0, +)
                isLoadingStats = false
            }
        } catch {
            print("❌ 都道府県統計の読み込みに失敗: \(error.localizedDescription)")
            await MainActor.run {
                isLoadingStats = false
            }
        }
    }
    
    private func sendUpdateNotification(title: String, message: String) async {
        await MainActor.run {
            isSendingUpdateNotification = true
        }
        
        do {
            try await firestoreService.sendUpdateNotificationToAllUsers(title: title, message: message)
            await MainActor.run {
                isSendingUpdateNotification = false
                notificationSentMessage = "全ユーザーにアップデート通知を送信しました（\(totalUsers) 人）"
                showNotificationSentAlert = true
            }
            print("✅ アップデート通知を全ユーザーに送信しました")
        } catch {
            print("❌ アップデート通知の送信に失敗: \(error.localizedDescription)")
            await MainActor.run {
                isSendingUpdateNotification = false
            }
        }
    }
    
    private func compensateMissionRewards() async {
        await MainActor.run {
            isCompensatingRewards = true
        }
        
        do {
            let result = try await firestoreService.compensateMissionRewards()
            await MainActor.run {
                isCompensatingRewards = false
                notificationSentMessage = "報酬補償完了: \(result.affectedUsers)人のユーザーに報酬を配布しました"
                showNotificationSentAlert = true
            }
            print("✅ 報酬補償を完了しました: \(result.affectedUsers)人")
        } catch {
            print("❌ 報酬補償に失敗: \(error.localizedDescription)")
            await MainActor.run {
                isCompensatingRewards = false
                notificationSentMessage = "エラー: \(error.localizedDescription)"
                showNotificationSentAlert = true
            }
        }
    }
    
    private func resetAbnormalGauges() async {
        await MainActor.run {
            isResettingGauges = true
        }
        
        do {
            let resetCount = try await firestoreService.resetAbnormalGauges()
            await MainActor.run {
                isResettingGauges = false
                notificationSentMessage = "異常ゲージリセット完了: \(resetCount)個のゲージをリセットしました"
                showNotificationSentAlert = true
            }
            print("✅ 異常ゲージリセットを完了しました: \(resetCount)個")
        } catch {
            print("❌ 異常ゲージリセットに失敗: \(error.localizedDescription)")
            await MainActor.run {
                isResettingGauges = false
                notificationSentMessage = "エラー: \(error.localizedDescription)"
                showNotificationSentAlert = true
            }
        }
    }
    
    private func addExperienceToUser(userID: String, amount: Int) async {
        do {
            try await firestoreService.addExperienceToUser(userID: userID, amount: amount)
            await MainActor.run {
                notificationSentMessage = "ユーザー \(userID) に経験値 \(amount) を付与しました"
                showNotificationSentAlert = true
                showUserExperienceSheet = false
                targetUserID = ""
                experienceAmount = ""
            }
        } catch {
            print("❌ 経験値付与に失敗: \(error.localizedDescription)")
            await MainActor.run {
                notificationSentMessage = "エラー: \(error.localizedDescription)"
                showNotificationSentAlert = true
            }
        }
    }
    
    private func banUser(userID: String, reason: String) async {
        do {
            try await firestoreService.banUser(userID: userID, reason: reason)
            await MainActor.run {
                notificationSentMessage = "ユーザー \(userID) をBANしました"
                showNotificationSentAlert = true
                showUserBanSheet = false
                targetUserID = ""
                banReason = ""
            }
        } catch {
            print("❌ BAN処理に失敗: \(error.localizedDescription)")
            await MainActor.run {
                notificationSentMessage = "エラー: \(error.localizedDescription)"
                showNotificationSentAlert = true
            }
        }
    }
    
    private func unbanUser(userID: String) async {
        do {
            try await firestoreService.unbanUser(userID: userID)
            await MainActor.run {
                notificationSentMessage = "ユーザー \(userID) のBANを解除しました"
                showNotificationSentAlert = true
                showUserBanSheet = false
                targetUserID = ""
            }
        } catch {
            print("❌ BAN解除に失敗: \(error.localizedDescription)")
            await MainActor.run {
                notificationSentMessage = "エラー: \(error.localizedDescription)"
                showNotificationSentAlert = true
            }
        }
    }
    
    private func sendCustomNotification(title: String, body: String) async {
        do {
            let sentCount = try await firestoreService.sendCustomNotificationToAllUsers(title: title, body: body)
            await MainActor.run {
                notificationSentMessage = "カスタム通知を \(sentCount) 人のユーザーに送信しました"
                showNotificationSentAlert = true
                showCustomNotificationSheet = false
                customNotificationTitle = ""
                customNotificationMessage = ""
            }
        } catch {
            print("❌ カスタム通知送信に失敗: \(error.localizedDescription)")
            await MainActor.run {
                notificationSentMessage = "エラー: \(error.localizedDescription)"
                showNotificationSentAlert = true
            }
        }
    }
    
    private func forceAwardMissionRewards(userID: String) async {
        do {
            let result = try await firestoreService.forceAwardMissionRewards(userID: userID)
            await MainActor.run {
                notificationSentMessage = result
                showNotificationSentAlert = true
                showUserMissionRewardSheet = false
                missionRewardUserID = ""
            }
        } catch {
            print("❌ ミッション報酬の再付与に失敗: \(error.localizedDescription)")
            await MainActor.run {
                notificationSentMessage = "エラー: \(error.localizedDescription)"
                showNotificationSentAlert = true
            }
        }
    }
    
    private func setMistClearCount(userID: String, count: Int) async {
        do {
            let result = try await firestoreService.setMistClearCount(userID: userID, count: count)
            await MainActor.run {
                notificationSentMessage = result
                showNotificationSentAlert = true
                showMistClearSheet = false
                mistClearUserID = ""
                mistClearCount = ""
            }
        } catch {
            print("❌ モヤ浄化カウント設定に失敗: \(error.localizedDescription)")
            await MainActor.run {
                notificationSentMessage = "エラー: \(error.localizedDescription)"
                showNotificationSentAlert = true
            }
        }
    }
    
    private func setEmotionPostCount(userID: String, count: Int) async {
        do {
            let result = try await firestoreService.setEmotionPostCount(userID: userID, count: count)
            await MainActor.run {
                notificationSentMessage = result
                showNotificationSentAlert = true
                showEmotionPostSheet = false
                emotionPostUserID = ""
                emotionPostCount = ""
            }
        } catch {
            print("❌ 感情投稿カウント設定に失敗: \(error.localizedDescription)")
            await MainActor.run {
                notificationSentMessage = "エラー: \(error.localizedDescription)"
                showNotificationSentAlert = true
            }
        }
    }
}

// 都道府県別ユーザー数の詳細ビュー
struct PrefectureStatsView: View {
    let stats: [String: Int]
    let totalUsers: Int
    
    var sortedStats: [(prefecture: String, count: Int)] {
        stats.map { ($0.key, $0.value) }
            .sorted { $0.count > $1.count }
    }
    
    var body: some View {
        List {
            Section {
                HStack {
                    Text("合計ユーザー数")
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(totalUsers) 人")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                .padding(.vertical, 8)
            }
            
            Section("都道府県別") {
                if sortedStats.isEmpty {
                    Text("まだユーザーがいません")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(sortedStats, id: \.prefecture) { stat in
                        HStack {
                            Text(stat.prefecture.isEmpty ? "未設定" : stat.prefecture)
                                .font(.body)
                            Spacer()
                            Text("\(stat.count) 人")
                                .font(.headline)
                                .foregroundColor(.blue)
                            
                            // パーセンテージ
                            if totalUsers > 0 {
                                Text("(\(Int(Double(stat.count) / Double(totalUsers) * 100))%)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("都道府県別ユーザー数")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// 経験値管理ビュー
struct UserExperienceManagementView: View {
    @Binding var userID: String
    @Binding var amount: String
    @Environment(\.dismiss) private var dismiss
    let onSubmit: (String, Int) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section("ユーザー情報") {
                    TextField("ユーザーID", text: $userID)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
                
                Section("経験値") {
                    TextField("付与する経験値（マイナスで削除）", text: $amount)
                        .keyboardType(.numberPad)
                    
                    Text("例: 100 で付与、-50 で削除")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button("実行") {
                        guard !userID.isEmpty,
                              let experienceAmount = Int(amount) else {
                            return
                        }
                        onSubmit(userID, experienceAmount)
                    }
                    .disabled(userID.isEmpty || amount.isEmpty)
                }
            }
            .navigationTitle("経験値管理")
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

// BAN管理ビュー
struct UserBanManagementView: View {
    @Binding var userID: String
    @Binding var reason: String
    @Environment(\.dismiss) private var dismiss
    let onBan: (String, String) -> Void
    let onUnban: (String) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section("ユーザー情報") {
                    TextField("ユーザーID", text: $userID)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
                
                Section("BAN理由") {
                    TextField("理由", text: $reason)
                    
                    Text("例: 不適切な投稿、スパム行為など")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button("BANする") {
                        guard !userID.isEmpty, !reason.isEmpty else {
                            return
                        }
                        onBan(userID, reason)
                    }
                    .foregroundColor(.red)
                    .disabled(userID.isEmpty || reason.isEmpty)
                    
                    Button("BAN解除") {
                        guard !userID.isEmpty else {
                            return
                        }
                        onUnban(userID)
                    }
                    .foregroundColor(.green)
                    .disabled(userID.isEmpty)
                }
            }
            .navigationTitle("BAN管理")
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

// カスタム通知ビュー
struct CustomNotificationView: View {
    @Binding var title: String
    @Binding var message: String
    @Environment(\.dismiss) private var dismiss
    let onSend: (String, String) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section("通知タイトル") {
                    TextField("タイトル", text: $title)
                    
                    Text("例: 重要なお知らせ")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("通知本文") {
                    TextEditor(text: $message)
                        .frame(minHeight: 100)
                    
                    Text("例: 本日メンテナンスを実施します")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button("全ユーザーに送信") {
                        guard !title.isEmpty, !message.isEmpty else {
                            return
                        }
                        onSend(title, message)
                    }
                    .disabled(title.isEmpty || message.isEmpty)
                }
            }
            .navigationTitle("カスタム通知")
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

// ミッション報酬再付与ビュー
struct UserMissionRewardView: View {
    @Binding var userID: String
    @Environment(\.dismiss) private var dismiss
    let onSubmit: (String) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section("ユーザー情報") {
                    TextField("ユーザーID", text: $userID)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
                
                Section("説明") {
                    Text("このユーザーの現在のレベルに応じて、まだ受け取っていないミッション報酬（称号、アイコンフレーム、経験値ボーナス）を付与します。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button("報酬を再付与") {
                        guard !userID.isEmpty else {
                            return
                        }
                        onSubmit(userID)
                    }
                    .disabled(userID.isEmpty)
                }
            }
            .navigationTitle("ミッション報酬を再付与")
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

// ミッション進捗管理ビュー
struct MissionProgressView: View {
    @Binding var userID: String
    @Binding var count: String
    let missionType: String
    @Environment(\.dismiss) private var dismiss
    let onSubmit: (String, Int) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section("ユーザー情報") {
                    TextField("ユーザーID", text: $userID)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
                
                Section("\(missionType)回数") {
                    TextField("回数", text: $count)
                        .keyboardType(.numberPad)
                    
                    Text("例: 10, 20, 50, 100")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("説明") {
                    Text("このユーザーの\(missionType)カウントを設定し、達成したミッションの報酬（称号、アイコンフレーム、経験値）を自動付与します。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button("設定して報酬を付与") {
                        guard !userID.isEmpty,
                              let missionCount = Int(count) else {
                            return
                        }
                        onSubmit(userID, missionCount)
                    }
                    .disabled(userID.isEmpty || count.isEmpty)
                }
            }
            .navigationTitle("\(missionType)カウント設定")
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

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var userName: String = ""
    @State private var isNotificationEnabled = true
    @State private var systemNotificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isPublicAccount: Bool = true
    @State private var homePrefectureName: String = ""
    @State private var initialHomePrefectureName: String = ""
    @State private var isSaving = false
    @State private var showAdminLogin = false
    @State private var showUserAuth = false
    @State private var showRestartAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var showDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var isCleaningNotifications = false
    @State private var showCleanupAlert = false
    @State private var cleanupMessage = ""
    @State private var showNotificationSettingsAlert = false
    @State private var showUserNameErrorAlert = false
    @State private var userNameErrorMessage = ""
    @StateObject private var authService = LocalAuthService.shared
    
    private let firestoreService = FirestoreService()
    private let authUseCase = AuthUseCase(
        authRepository: IOSAuthRepository(),
        userProfileRepository: IOSUserProfileRepository()
    )
    private let settingsUseCase = SettingsUseCase(
        userProfileRepository: IOSUserProfileRepository()
    )
    private let maxUserNameLength = 10
    
    var body: some View {
        NavigationView {
            List {
                accountSection
                prefectureSection
                notificationSection
                helpSection
                otherSection
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await saveSettings()
                            await MainActor.run {
                                dismiss()
                            }
                        }
                    }) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("完了")
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                loadSettings()
                Task {
                    await checkNotificationStatus()
                }
            }
            .sheet(isPresented: $showAdminLogin) {
                NavigationView {
                    AdminLoginView()
                }
            }
            .sheet(isPresented: $showUserAuth) {
                UserAuthView(authService: authService)
            }
            .alert("チュートリアルを再表示", isPresented: $showRestartAlert) {
                Button("OK") {
                    // OKが押された時のみフラグを変更してアプリを終了
                    UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                    exit(0) // アプリを終了
                }
                Button("キャンセル", role: .cancel) {
                    // キャンセルの場合は何もしない（フラグは変更しない）
                }
            } message: {
                Text("チュートリアルを表示するため、アプリを再起動してください。OKを押すとアプリが終了します。")
            }
            .alert("アカウントを削除", isPresented: $showDeleteAccountAlert) {
                Button("削除する", role: .destructive) {
                    showDeleteAccountConfirmation = true
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("アカウントを削除すると、すべてのデータ（投稿、友達関係、プロフィール情報など）が永久に削除され、復元できません。この操作は取り消せません。")
            }
            .alert("本当に削除しますか？", isPresented: $showDeleteAccountConfirmation) {
                Button("削除する", role: .destructive) {
                    Task {
                        isDeletingAccount = true
                        let success: Bool
                        do {
                            try await authUseCase.deleteCurrentAccount()
                            success = true
                        } catch {
                            authService.errorMessage = error.localizedDescription
                            success = false
                        }
                        isDeletingAccount = false
                        if success {
                            dismiss()
                        }
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この操作は取り消せません。すべてのデータが永久に削除されます。")
            }
            .alert("通知のクリーンアップ", isPresented: $showCleanupAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(cleanupMessage)
            }
            .alert("通知が許可されていません", isPresented: $showNotificationSettingsAlert) {
                Button("設定を開く") {
                    openAppSettings()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("通知を受け取るには、端末の設定でアプリの通知を許可してください。")
            }
            .alert("ユーザー名エラー", isPresented: $showUserNameErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(userNameErrorMessage)
            }
        }
    }
    
    private func loadSettings() {
        // UserDefaultsから設定を読み込む
        userName = UserService.shared.userName
        isPublicAccount = UserService.shared.isPublicAccount
        isNotificationEnabled = UserDefaults.standard.bool(forKey: "notification_enabled")
        if UserDefaults.standard.object(forKey: "notification_enabled") == nil {
            isNotificationEnabled = true // デフォルトは有効
        }
        homePrefectureName = UserService.shared.homePrefectureName
        initialHomePrefectureName = homePrefectureName
    }
    
    // MARK: - View Sections
    
    private var accountSection: some View {
        Section("アカウント") {
            HStack {
                Text("ユーザー名")
                Spacer()
                TextField("ユーザー名", text: $userName)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 150)
                    .onChange(of: userName) { newValue in
                        if newValue.count > maxUserNameLength {
                            userName = String(newValue.prefix(maxUserNameLength))
                        }
                    }
            }
            
            Toggle("公開アカウント", isOn: $isPublicAccount)
            
            Text(isPublicAccount ? "誰でもあなたの投稿を見ることができます" : "友達のみがあなたの投稿を見ることができます")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var prefectureSection: some View {
        Section("居住地") {
            Picker("住んでいる県", selection: $homePrefectureName) {
                Text("未設定").tag("")
                ForEach(Prefecture.allCases) { prefecture in
                    Text(prefecture.rawValue).tag(prefecture.rawValue)
                }
            }
            .disabled(!initialHomePrefectureName.isEmpty)
            Text("ミニゲームの位置はここで選んだ県になります")
                .font(.caption)
                .foregroundColor(.secondary)
            if !initialHomePrefectureName.isEmpty {
                Text("一度登録すると変更できません")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var notificationSection: some View {
        Section("通知") {
            Toggle("通知を受け取る", isOn: $isNotificationEnabled)
                .onChange(of: isNotificationEnabled) { newValue in
                    handleNotificationToggle(newValue)
                }
            
            if systemNotificationStatus == .denied {
                Text("端末の設定で通知が許可されていません")
                    .font(.caption)
                    .foregroundColor(.red)
                Button("設定を開く") {
                    openAppSettings()
                }
                .font(.caption)
            } else {
                Text("端末側: \(notificationStatusText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button(action: {
                Task {
                    await cleanupOldNotifications()
                }
            }) {
                HStack {
                    Image(systemName: "trash.circle")
                    Text("古い通知を削除")
                    Spacer()
                    if isCleaningNotifications {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                }
                .contentShape(Rectangle())
            }
            .disabled(isCleaningNotifications)
            
            Text("取り消された友達申請や削除された投稿に関する通知など、不要な通知を削除します")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var helpSection: some View {
        Section("ヘルプ") {
            Button(action: {
                showRestartAlert = true
            }) {
                HStack {
                    Image(systemName: "questionmark.circle")
                    Text("チュートリアルを再表示")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
        }
    }
    
    private var otherSection: some View {
        Section("その他") {
            Button(action: {
                if authService.isLoggedIn {
                    Task {
                        await authUseCase.signOut()
                        await MainActor.run {
                            dismiss()
                        }
                    }
                } else {
                    showUserAuth = true
                }
            }) {
                HStack {
                    Text(authService.isLoggedIn ? "ログアウト" : "ログイン / 新規登録")
                    Spacer()
                    if authService.isLoggedIn, let username = authService.currentUsername {
                        Text(username)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 10.0)
                    .onEnded { _ in
                        showAdminLogin = true
                    }
            )
            
            if authService.isLoggedIn {
                Button(role: .destructive, action: {
                    showDeleteAccountAlert = true
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("アカウントを削除")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .disabled(isDeletingAccount)
            }
        }
    }
    
    // ユーザー名のバリデーションと重複チェック
    private func validateAndCheckUserName() async -> Bool {
        let trimmedUserName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 空チェック
        if trimmedUserName.isEmpty {
            await MainActor.run {
                userNameErrorMessage = "ユーザー名を入力してください"
                showUserNameErrorAlert = true
            }
            return false
        }

        // 文字数チェック
        if trimmedUserName.count > maxUserNameLength {
            await MainActor.run {
                userNameErrorMessage = "ユーザー名は\(maxUserNameLength)文字以内で入力してください"
                showUserNameErrorAlert = true
            }
            return false
        }
        
        // 既存のユーザー名と異なる場合のみ重複チェック
        if trimmedUserName != UserService.shared.userName {
            do {
                let exists = try await firestoreService.checkUserNameExists(
                    userName: trimmedUserName,
                    excludeUserID: UserService.shared.currentUserID
                )
                
                if exists {
                    await MainActor.run {
                        userNameErrorMessage = "このユーザー名は既に使用されています。\n別のユーザー名を入力してください。"
                        showUserNameErrorAlert = true
                    }
                    return false
                }
            } catch {
                print("⚠️ ユーザー名の重複チェックに失敗: \(error.localizedDescription)")
                // チェックに失敗した場合は続行（ネットワークエラー等を考慮）
            }
        }
        
        return true
    }
    
    // 居住地設定の保存
    private func savePrefectureSettings() async {
        let previousHomePrefecture = initialHomePrefectureName
        UserService.shared.homePrefectureName = homePrefectureName
        initialHomePrefectureName = homePrefectureName
        
        if !homePrefectureName.isEmpty && previousHomePrefecture.isEmpty {
            if let prefecture = Prefecture(rawValue: homePrefectureName) {
                do {
                    try await firestoreService.registerToPrefecture(prefecture)
                    print("✅ \(homePrefectureName)に自動登録しました")
                } catch {
                    print("⚠️ 都道府県の自動登録に失敗しました: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func saveSettings() async {
        await MainActor.run {
            isSaving = true
        }
        
        // 確実にisSavingをfalseに戻すためにdeferを使用
        defer {
            Task { @MainActor in
                isSaving = false
                print("✅ isSaving = false に設定しました")
            }
        }
        
        // ユーザー名のバリデーションと重複チェック
        guard await validateAndCheckUserName() else {
            return
        }
        
        // UserDefaultsに通知設定を保存
        UserDefaults.standard.set(isNotificationEnabled, forKey: "notification_enabled")
        
        // 居住地の設定を保存（都道府県自動登録の副作用を維持）
        await savePrefectureSettings()
        
        // 共通UseCase経由でプロフィールを保存
        do {
            try await settingsUseCase.save(
                input: SettingsInput(
                    userName: userName,
                    isPublicAccount: isPublicAccount,
                    homePrefectureName: homePrefectureName
                )
            )
            print("✅ ユーザー設定を保存しました")
        } catch {
            print("⚠️ ユーザー設定の保存に失敗しました: \(error.localizedDescription)")
        }
        
        // 設定が更新されたことを通知
        NotificationCenter.default.post(name: NSNotification.Name("SettingsUpdated"), object: nil)
    }
    
    // 古い通知をクリーンアップ
    private func cleanupOldNotifications() async {
        isCleaningNotifications = true
        
        do {
            // 古い友達申請通知を削除
            try await firestoreService.cleanupOldFriendRequestNotifications()
            
            // 無効な投稿に関する通知を削除
            try await firestoreService.cleanupInvalidPostNotifications()
            
            await MainActor.run {
                cleanupMessage = "不要な通知を削除しました"
                showCleanupAlert = true
                isCleaningNotifications = false
            }
        } catch {
            await MainActor.run {
                cleanupMessage = "通知の削除に失敗しました: \(error.localizedDescription)"
                showCleanupAlert = true
                isCleaningNotifications = false
            }
        }
    }
    
    // システムの通知許可状態を確認
    private func checkNotificationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        await MainActor.run {
            systemNotificationStatus = settings.authorizationStatus
            
            // システムの状態に合わせてアプリ内の設定を同期
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                // システムで許可されている場合、アプリ内の設定をオンに
                if !isNotificationEnabled {
                    isNotificationEnabled = true
                    UserDefaults.standard.set(true, forKey: "notification_enabled")
                }
                print("✅ 通知許可: システム=許可, アプリ=\(isNotificationEnabled)")
            case .denied:
                // システムで拒否されている場合、アプリ内の設定をオフに
                if isNotificationEnabled {
                    isNotificationEnabled = false
                    UserDefaults.standard.set(false, forKey: "notification_enabled")
                }
                print("⚠️ 通知許可: システム=拒否, アプリ=\(isNotificationEnabled)")
            case .notDetermined:
                // まだ決まっていない場合は現在の設定を維持
                print("⚠️ 通知許可: システム=未決定, アプリ=\(isNotificationEnabled)")
            @unknown default:
                break
            }
        }
    }
    
    // 通知トグルの変更を処理
    private func handleNotificationToggle(_ newValue: Bool) {
        Task {
            await checkNotificationStatus()
            
            // システムで拒否されている場合は設定画面に案内
            if systemNotificationStatus == .denied && newValue {
                await MainActor.run {
                    isNotificationEnabled = false
                    showNotificationSettingsAlert = true
                }
            } else if systemNotificationStatus == .notDetermined && newValue {
                // 許可を求める
                let center = UNUserNotificationCenter.current()
                do {
                    let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                    await MainActor.run {
                        isNotificationEnabled = granted
                        UserDefaults.standard.set(granted, forKey: "notification_enabled")
                    }
                    await checkNotificationStatus()
                } catch {
                    print("⚠️ 通知許可の要求に失敗: \(error)")
                    await MainActor.run {
                        isNotificationEnabled = false
                    }
                }
            } else {
                // 通常の保存
                UserDefaults.standard.set(newValue, forKey: "notification_enabled")
            }
        }
    }
    
    // アプリの設定画面を開く
    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    // 通知ステータスのテキスト表示
    private var notificationStatusText: String {
        switch systemNotificationStatus {
        case .authorized:
            return "許可"
        case .denied:
            return "拒否"
        case .notDetermined:
            return "未設定"
        case .provisional:
            return "仮承認"
        case .ephemeral:
            return "一時的に許可"
        @unknown default:
            return "不明"
        }
    }
}

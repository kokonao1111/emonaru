import SwiftUI

struct UserAuthView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var authService: LocalAuthService
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var age: String = ""
    @State private var selectedGender: String = "無回答"
    @State private var mode: AuthMode = .login
    @State private var showEULA = false
    @State private var hasAgreedToEULA = false
    let allowDismiss: Bool
    private let authUseCase = AuthUseCase(
        authRepository: IOSAuthRepository(),
        userProfileRepository: IOSUserProfileRepository()
    )
    private let maxUserNameLength = 10

    init(authService: LocalAuthService, allowDismiss: Bool = true) {
        self.authService = authService
        self.allowDismiss = allowDismiss
    }

    enum AuthMode: String, CaseIterable {
        case login = "ログイン"
        case signup = "新規登録"
    }
    
    private let genderOptions = ["男性", "女性", "その他", "無回答"]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // ヘッダー
                    VStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 120 : 80))
                            .foregroundColor(.blue)
                            .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? 60 : 30)
                        
                        Text("ユーザーログイン")
                            .font(UIDevice.current.userInterfaceIdiom == .pad ? .largeTitle : .title2)
                            .fontWeight(.bold)
                            .padding(.bottom, UIDevice.current.userInterfaceIdiom == .pad ? 40 : 20)
                    }
                    
                    // コンテンツエリア（最大幅を制限）
                    VStack(spacing: UIDevice.current.userInterfaceIdiom == .pad ? 32 : 20) {
                        // モード切替
                        Picker("認証", selection: $mode) {
                            ForEach(AuthMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        
                        // 入力フォーム
                        VStack(spacing: UIDevice.current.userInterfaceIdiom == .pad ? 24 : 16) {
                            // ユーザー名
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ユーザー名")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("ユーザー名を入力", text: $username)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: username) { newValue in
                                        if newValue.count > maxUserNameLength {
                                            username = String(newValue.prefix(maxUserNameLength))
                                        }
                                    }
                            }
                            .padding(.horizontal)
                            
                            // パスワード
                            VStack(alignment: .leading, spacing: 8) {
                                Text("パスワード")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                SecureField("パスワードを入力", text: $password)
                                    .textFieldStyle(.roundedBorder)
                            }
                            .padding(.horizontal)
                            
                            // 新規登録時の追加項目
                            if mode == .signup {
                                // 年齢
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("年齢")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    TextField("年齢を入力", text: $age)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(.roundedBorder)
                                }
                                .padding(.horizontal)
                                
                                // 性別
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("性別")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Picker("性別", selection: $selectedGender) {
                                        ForEach(genderOptions, id: \.self) { gender in
                                            Text(gender).tag(gender)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                                .padding(.horizontal)
                                
                                // 利用規約同意
                                Button(action: {
                                    showEULA = true
                                }) {
                                    HStack {
                                        Image(systemName: hasAgreedToEULA ? "checkmark.square.fill" : "square")
                                            .foregroundColor(hasAgreedToEULA ? .blue : .gray)
                                            .font(.title3)
                                        Text("利用規約に同意する")
                                            .font(.subheadline)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(10)
                                }
                                .foregroundColor(.primary)
                                .padding(.horizontal)
                            }
                        }
                        
                        // エラーメッセージ
                        if let errorMessage = authService.errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal)
                                .padding(.top, 8)
                        }
                        
                        // ログイン/登録ボタン
                        Button(action: handleAuthAction) {
                            Text(mode == .login ? "ログイン" : "登録")
                                .font(UIDevice.current.userInterfaceIdiom == .pad ? .title3 : .headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(UIDevice.current.userInterfaceIdiom == .pad ? 20 : 16)
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? 32 : 20)
                    }
                    .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 900 : .infinity) // iPadでは900pt、iPhoneでは画面幅いっぱい
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 60 : 0) // iPadでは左右に余白を追加
                    
                    Spacer(minLength: UIDevice.current.userInterfaceIdiom == .pad ? 80 : 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if allowDismiss {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("閉じる") {
                            dismiss()
                        }
                    }
                }
            }
            .sheet(isPresented: $showEULA) {
                EULAView(isPresented: $showEULA) {
                    hasAgreedToEULA = true
                }
            }
            .onAppear {
                // 既に同意済みか確認
                hasAgreedToEULA = UserDefaults.standard.bool(forKey: "hasAgreedToEULA")
            }
        }
        .navigationViewStyle(.stack) // iPadでもスタックスタイルを強制
    }
    
    private func handleAuthAction() {
        let trimmedUserName = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserName.isEmpty else {
            authService.errorMessage = "ユーザー名を入力してください"
            return
        }
        guard trimmedUserName.count <= maxUserNameLength else {
            authService.errorMessage = "ユーザー名は\(maxUserNameLength)文字以内で入力してください"
            return
        }

        if mode == .login {
            Task {
                do {
                    _ = try await authUseCase.signIn(username: trimmedUserName, password: password)
                    if allowDismiss {
                        dismiss()
                    }
                } catch {
                    authService.errorMessage = error.localizedDescription
                }
            }
        } else {
            // 新規登録時のバリデーション
            guard let ageValue = Int(age), ageValue > 0 else {
                authService.errorMessage = "年齢を入力してください"
                return
            }
            
            guard ageValue >= 13 else {
                authService.errorMessage = "13歳以上のみ登録できます"
                return
            }
            
            guard ageValue <= 120 else {
                authService.errorMessage = "正しい年齢を入力してください"
                return
            }
            
            guard hasAgreedToEULA else {
                authService.errorMessage = "利用規約への同意が必要です"
                return
            }
            
            Task {
                do {
                    _ = try await authUseCase.signUp(
                        username: trimmedUserName,
                        password: password,
                        age: ageValue,
                        gender: selectedGender
                    )
                    if allowDismiss {
                        dismiss()
                    }
                } catch {
                    authService.errorMessage = error.localizedDescription
                }
            }
        }
    }
}



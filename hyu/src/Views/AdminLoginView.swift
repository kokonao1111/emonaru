import SwiftUI

struct AdminLoginView: View {
    @StateObject private var authService = AdminAuthService()
    @State private var adminID: String = ""
    @State private var password: String = ""
    @State private var isShowingDashboard = false
    @State private var isLoading = false

    var body: some View {
        Form {
            Section("管理者ログイン") {
                TextField("管理者ID", text: $adminID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("パスワード", text: $password)
            }

            Button("ログイン") {
                guard !isLoading else { return }
                isLoading = true
                Task {
                    let success = await authService.signIn(adminID: adminID, password: password)
                    await MainActor.run {
                        isLoading = false
                        if success {
                            isShowingDashboard = true
                        }
                    }
                }
            }
            .disabled(isLoading)

            if let errorMessage = authService.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .navigationTitle("管理者ログイン")
        .navigationBarTitleDisplayMode(.inline)
        .background(
            NavigationLink(
                destination: AdminDashboardView(authService: authService),
                isActive: $isShowingDashboard
            ) {
                EmptyView()
            }
            .hidden()
        )
    }
}

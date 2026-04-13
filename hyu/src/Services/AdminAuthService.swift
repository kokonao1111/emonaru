import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class AdminAuthService: ObservableObject {
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var authenticatedID: String?
    @Published private(set) var errorMessage: String?

    private let db = Firestore.firestore()

    func signIn(adminID: String, password: String) async -> Bool {
        let normalizedID = adminID.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        do {
            let adminDoc = try await db.collection("admins").document(normalizedID).getDocument()
            let isAdmin = adminDoc.get("isAdmin") as? Bool ?? false
            let storedPassword = adminDoc.get("password") as? String

            guard isAdmin else {
                isAuthenticated = false
                authenticatedID = nil
                errorMessage = "管理者権限がありません"
                return false
            }

            guard storedPassword == password else {
                isAuthenticated = false
                authenticatedID = nil
                errorMessage = "IDまたはパスワードが違います"
                return false
            }

            isAuthenticated = true
            authenticatedID = normalizedID
            return true
        } catch {
            isAuthenticated = false
            authenticatedID = nil
            errorMessage = "ログインに失敗しました"
            return false
        }
    }

    func signOut() {
        isAuthenticated = false
        authenticatedID = nil
        errorMessage = nil
    }
}

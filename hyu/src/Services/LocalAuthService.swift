import Foundation
import Combine
import CryptoKit
import UIKit

@MainActor
final class LocalAuthService: ObservableObject {
    static let shared = LocalAuthService()

    @Published private(set) var isLoggedIn: Bool = false
    @Published private(set) var currentUsername: String?
    @Published var errorMessage: String?

    private let usersKey = "com.nao.hyu.auth.users"
    private let currentUserKey = "com.nao.hyu.auth.currentUsername"
    private let deviceInstallIDKey = "com.nao.hyu.auth.deviceInstallID"
    private let firestoreService = FirestoreService()
    private let maxUserNameLength = 10

    struct LocalAuthUser: Codable {
        let userID: String
        let password: String
    }
    
    // パスワードをハッシュ化
    private func hashPassword(_ password: String) -> String {
        let inputData = Data(password.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func currentDeviceFingerprint() -> String {
        let rawID: String
        if let idfv = UIDevice.current.identifierForVendor?.uuidString, !idfv.isEmpty {
            rawID = "idfv:\(idfv)"
        } else {
            let existing = UserDefaults.standard.string(forKey: deviceInstallIDKey)
            let installID = existing ?? UUID().uuidString
            if existing == nil {
                UserDefaults.standard.set(installID, forKey: deviceInstallIDKey)
            }
            rawID = "install:\(installID)"
        }
        return hashPassword(rawID)
    }

    init() {
        currentUsername = UserDefaults.standard.string(forKey: currentUserKey)
        isLoggedIn = currentUsername != nil
    }

    func signUp(username: String, password: String, age: Int, gender: String) async -> Bool {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceFingerprint = currentDeviceFingerprint()
        guard !normalized.isEmpty else {
            errorMessage = "ユーザー名を入力してください"
            return false
        }
        guard normalized.count <= maxUserNameLength else {
            errorMessage = "ユーザー名は\(maxUserNameLength)文字以内で入力してください"
            return false
        }
        guard !password.isEmpty else {
            errorMessage = "パスワードを入力してください"
            return false
        }

        // BAN対象端末かどうかチェック
        do {
            let isDeviceBanned = try await firestoreService.isDeviceFingerprintBanned(deviceFingerprint)
            if isDeviceBanned {
                errorMessage = "この端末では新規登録できません"
                return false
            }

            // Firestoreでユーザー名の重複チェック
            let exists = try await firestoreService.checkUsernameExists(username: normalized)
            if exists {
                errorMessage = "そのユーザー名は既に使われています"
                return false
            }
        } catch {
            errorMessage = "ネットワークエラーが発生しました。もう一度お試しください"
            return false
        }

        let userID = UUID().uuidString
        let passwordHash = hashPassword(password)

        // Firestoreに認証情報を保存
        do {
            try await firestoreService.saveAuthInfo(username: normalized, userID: userID, passwordHash: passwordHash)
            
            // ローカルにも保存（オフライン対応）
            var users = loadUsers()
            let user = LocalAuthUser(userID: userID, password: password)
            users[normalized] = user
            saveUsers(users)

            setLoggedIn(username: normalized, userID: userID)
            UserService.shared.resetUserScopedData(defaultUserName: normalized)
            
            // 年齢と性別を保存（ローカル）
            UserService.shared.userAge = age
            UserService.shared.userGender = gender
            
            // Firestoreにユーザープロファイルも保存
            try await firestoreService.saveUserProfile()
            try? await firestoreService.addDeviceFingerprintToUser(userID: userID, fingerprint: deviceFingerprint)
            print("✅ 新規登録情報をFirestoreに保存しました")
            
            errorMessage = nil
            return true
        } catch {
            errorMessage = "登録に失敗しました: \(error.localizedDescription)"
            return false
        }
    }

    func signIn(username: String, password: String) async -> Bool {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceFingerprint = currentDeviceFingerprint()
        guard !normalized.isEmpty else {
            errorMessage = "ユーザー名を入力してください"
            return false
        }
        guard !password.isEmpty else {
            errorMessage = "パスワードを入力してください"
            return false
        }

        let passwordHash = hashPassword(password)

        // まずFirestoreから認証情報を取得
        do {
            if let authInfo = try await firestoreService.getAuthInfo(username: normalized) {
                // Firestoreに認証情報がある場合
                if authInfo.passwordHash == passwordHash {
                    // BAN状態のアカウントはログイン不可
                    if try await firestoreService.isUserBanned(userID: authInfo.userID) {
                        errorMessage = "このアカウントはBANされています"
                        return false
                    }
                    setLoggedIn(username: normalized, userID: authInfo.userID)
                    try? await firestoreService.addDeviceFingerprintToUser(userID: authInfo.userID, fingerprint: deviceFingerprint)
                    UserService.shared.resetUserScopedData(defaultUserName: normalized)
                    
                    // Firestoreからユーザー情報を復元
                    do {
                        try await firestoreService.loadCurrentUserProfile()
                        print("✅ Firestoreからユーザー情報を復元しました")
                    } catch {
                        print("❌ Firestoreからの読み込みに失敗: \(error.localizedDescription)")
                    }
                    
                    // ローカルにも保存（オフライン対応）
                    var users = loadUsers()
                    let user = LocalAuthUser(userID: authInfo.userID, password: password)
                    users[normalized] = user
                    saveUsers(users)
                    
                    errorMessage = nil
                    return true
                } else {
                    errorMessage = "ユーザー名またはパスワードが違います"
                    return false
                }
            } else {
                // Firestoreに認証情報がない場合、ローカルを確認（既存ユーザーのため）
                let users = loadUsers()
                if let user = users[normalized], user.password == password {
                    if try await firestoreService.isUserBanned(userID: user.userID) {
                        errorMessage = "このアカウントはBANされています"
                        return false
                    }
                    setLoggedIn(username: normalized, userID: user.userID)
                    try? await firestoreService.addDeviceFingerprintToUser(userID: user.userID, fingerprint: deviceFingerprint)
                    UserService.shared.resetUserScopedData(defaultUserName: normalized)
                    
                    // Firestoreに認証情報を移行（非同期）
                    Task {
                        do {
                            try await firestoreService.saveAuthInfo(username: normalized, userID: user.userID, passwordHash: passwordHash)
                            print("✅ 認証情報をFirestoreに移行しました")
                        } catch {
                            print("❌ Firestoreへの移行に失敗: \(error.localizedDescription)")
                        }
                    }
                    
                    // Firestoreからユーザー情報を復元
                    Task {
                        do {
                            try await firestoreService.loadCurrentUserProfile()
                            print("✅ Firestoreからユーザー情報を復元しました")
                        } catch {
                            print("❌ Firestoreからの読み込みに失敗: \(error.localizedDescription)")
                        }
                    }
                    
                    errorMessage = nil
                    return true
                } else {
                    errorMessage = "ユーザー名またはパスワードが違います"
                    return false
                }
            }
        } catch {
            // ネットワークエラーの場合、ローカルを確認
            let users = loadUsers()
            if let user = users[normalized], user.password == password {
                setLoggedIn(username: normalized, userID: user.userID)
                UserService.shared.resetUserScopedData(defaultUserName: normalized)
                errorMessage = "オフラインモードでログインしました"
                return true
            } else {
                errorMessage = "ネットワークエラーが発生しました。もう一度お試しください"
                return false
            }
        }
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: currentUserKey)
        currentUsername = nil
        isLoggedIn = false
        errorMessage = nil
        UserService.shared.resetUserScopedData()
        UserService.shared.resetUserID()
    }
    
    func deleteAccount() async -> Bool {
        guard let username = currentUsername else {
            errorMessage = "ログインしていません"
            return false
        }
        
        let userID = UserService.shared.currentUserID
        
        do {
            // Firestoreからアカウントと関連データをすべて削除
            try await firestoreService.deleteUserAccount(userID: userID, username: username)
            
            // ローカルの認証情報を削除
            var users = loadUsers()
            users.removeValue(forKey: username)
            saveUsers(users)
            
            // ローカルのユーザー情報を削除
            UserDefaults.standard.removeObject(forKey: currentUserKey)
            UserDefaults.standard.removeObject(forKey: usersKey)
            UserService.shared.resetUserScopedData()
            UserService.shared.resetUserID()
            
            // ログアウト状態にする
            currentUsername = nil
            isLoggedIn = false
            errorMessage = nil
            
            print("✅ アカウントを削除しました")
            return true
        } catch {
            errorMessage = "アカウントの削除に失敗しました: \(error.localizedDescription)"
            return false
        }
    }

    private func setLoggedIn(username: String, userID: String) {
        UserDefaults.standard.set(username, forKey: currentUserKey)
        currentUsername = username
        isLoggedIn = true
        UserService.shared.setCurrentUserID(userID)
        UserService.shared.userName = username
    }

    private func loadUsers() -> [String: LocalAuthUser] {
        guard let data = UserDefaults.standard.data(forKey: usersKey) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: LocalAuthUser].self, from: data)) ?? [:]
    }

    private func saveUsers(_ users: [String: LocalAuthUser]) {
        if let data = try? JSONEncoder().encode(users) {
            UserDefaults.standard.set(data, forKey: usersKey)
        }
    }
}

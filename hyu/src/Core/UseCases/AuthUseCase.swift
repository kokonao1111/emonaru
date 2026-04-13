import Foundation

@MainActor
final class AuthUseCase {
    private let authRepository: AuthRepository
    private let userProfileRepository: UserProfileRepository

    init(
        authRepository: AuthRepository,
        userProfileRepository: UserProfileRepository
    ) {
        self.authRepository = authRepository
        self.userProfileRepository = userProfileRepository
    }

    func signIn(username: String, password: String) async throws -> CoreAuthUser {
        let user = try await authRepository.signIn(username: username, password: password)
        try? await userProfileRepository.loadUserProfile(userID: user.userID)
        return user
    }

    func signUp(username: String, password: String, age: Int, gender: String) async throws -> CoreAuthUser {
        let user = try await authRepository.signUp(
            username: username,
            password: password,
            age: age,
            gender: gender
        )
        try? await userProfileRepository.loadUserProfile(userID: user.userID)
        return user
    }

    func signOut() async {
        await authRepository.signOut()
    }

    func deleteCurrentAccount() async throws {
        try await authRepository.deleteCurrentAccount()
    }
}

import Foundation

struct SettingsInput {
    let userName: String
    let isPublicAccount: Bool
    let homePrefectureName: String
}

final class SettingsUseCase {
    private let userProfileRepository: UserProfileRepository
    private let maxUserNameLength = 10

    init(userProfileRepository: UserProfileRepository) {
        self.userProfileRepository = userProfileRepository
    }

    func save(input: SettingsInput) async throws {
        let trimmedName = input.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.count <= maxUserNameLength else {
            throw NSError(
                domain: "SettingsUseCase",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "ユーザー名は\(maxUserNameLength)文字以内で入力してください"]
            )
        }
        await userProfileRepository.updateUserName(trimmedName)
        await userProfileRepository.updatePublicFlag(input.isPublicAccount)
        await userProfileRepository.updateHomePrefecture(input.homePrefectureName)
        try await userProfileRepository.saveCurrentUserProfile()
    }
}

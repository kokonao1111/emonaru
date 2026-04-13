import Foundation

struct MistCombatResult {
    let nextHP: Int
    let nextHappyPostCount: Int
    let clearByHP: Bool
    let clearByCount: Bool
}

enum MistCombatMath {
    static func applyPositivePost(
        currentHP: Int,
        maxHP: Int,
        currentHappyPostCount: Int,
        isMistCleanupPost: Bool,
        elapsedSeconds: TimeInterval,
        regenPerSecond: Int,
        damagePerPost: Int,
        clearCountThreshold: Int
    ) -> MistCombatResult {
        let regenHP = Int(max(0.0, elapsedSeconds)) * max(0, regenPerSecond)
        let effectiveHP = min(maxHP, currentHP + regenHP)
        let reducedHP = max(0, effectiveHP - max(0, damagePerPost))

        let nextCount: Int
        if isMistCleanupPost {
            nextCount = currentHappyPostCount
        } else {
            nextCount = currentHappyPostCount + 1
        }

        let clearByCount = !isMistCleanupPost && nextCount >= clearCountThreshold
        let clearByHP = reducedHP <= 0

        return MistCombatResult(
            nextHP: reducedHP,
            nextHappyPostCount: nextCount,
            clearByHP: clearByHP,
            clearByCount: clearByCount
        )
    }
}

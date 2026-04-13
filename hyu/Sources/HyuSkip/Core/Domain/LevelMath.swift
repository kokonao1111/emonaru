import Foundation

enum LevelMath {
    static func totalExpForLevel(_ level: Int) -> Int {
        guard level > 1 else { return 0 }
        let n = level - 1
        return 25 * n * (n + 3)
    }

    static func calculateLevel(fromExp exp: Int) -> Int {
        guard exp > 0 else { return 1 }

        var low = 1
        var high = 1000

        while low < high {
            let mid = (low + high + 1) / 2
            if totalExpForLevel(mid) <= exp {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }

    static func expForNextLevel(_ currentLevel: Int) -> Int {
        50 * currentLevel + 50
    }
}

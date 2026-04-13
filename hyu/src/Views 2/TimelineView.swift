import SwiftUI
import Combine

struct TimelineView: View {
    var posts: [EmotionPost] = []

    @State private var now = Date()
    private let lifespan: TimeInterval = 60 * 60 * 24


    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(posts) { post in
                    EmotionShape(level: post.level, seed: post.id, container: proxy.size)
                        .opacity(opacity(for: post))
                        .animation(.easeInOut(duration: 0.5), value: now)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .onReceive(timer) { value in
                now = value
            }
        }
        .ignoresSafeArea()
    }

    private func opacity(for post: EmotionPost) -> Double {
        let age = now.timeIntervalSince(post.createdAt)
        let progress = min(max(age / lifespan, 0), 1)
        return 1 - progress
    }
}

private struct EmotionShape: View {
    let level: EmotionLevel
    let seed: UUID
    let container: CGSize

    var body: some View {
        let size = baseSize
        let position = point

        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: blur)
            .position(x: position.x, y: position.y)
    }

    private var baseSize: CGFloat {
        let t = CGFloat(level.rawValue + 5) / 10
        return 40 + t * 180
    }

    private var blur: CGFloat {
        let t = CGFloat(abs(level.rawValue)) / 5
        return 2 + t * 10
    }

    private var color: Color {
        let t = Double(level.rawValue + 5) / 10
        let hue = 0.62 - 0.62 * t
        return Color(hue: hue, saturation: 0.5, brightness: 0.95)
            .opacity(0.9)
    }

    private var point: CGPoint {
        let dx = seed.normalized(index: 0)
        let dy = seed.normalized(index: 1)
        let x = (dx * 0.8 + 0.1) * container.width
        let y = (dy * 0.8 + 0.1) * container.height
        return CGPoint(x: x, y: y)
    }
}

private extension UUID {
    func normalized(index: Int) -> CGFloat {
        var hasher = Hasher()
        hasher.combine(self)
        hasher.combine(index)
        let hash = hasher.finalize()
        var value = Int(bitPattern: UInt(truncatingIfNeeded: hash))
        if value == Int.min { value = 0 }
        value = abs(value % 10_000)
        return CGFloat(value) / 10_000
    }
}

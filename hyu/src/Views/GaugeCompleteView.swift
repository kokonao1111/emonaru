import SwiftUI

struct GaugeCompleteView: View {
    let prefecture: String
    let level: Int
    let experiencePoints: Int  // 獲得した経験値
    let postBonus: Int  // 獲得した投稿回数
    let nextMaxValue: Int
    @Binding var isPresented: Bool
    
    @State private var showContent = false
    @State private var showExperience = false
    @State private var showPostBonus = false
    @State private var showNextLevel = false
    @State private var particles: [Particle] = []
    @State private var rotation: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let isSmallScreen = screenWidth <= 375 // iPhone SE (375px) 以下
            let scale = min(screenWidth / 393.0, 1.2) // スケール係数
            
            ZStack {
                // 背景グラデーション
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.purple.opacity(0.8),
                        Color.blue.opacity(0.8),
                        Color.cyan.opacity(0.8)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .hueRotation(.degrees(rotation))
                
                // パーティクルエフェクト
                ForEach(particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .position(particle.position)
                        .opacity(particle.opacity)
                }
                
                // メインコンテンツ
                VStack(spacing: isSmallScreen ? 20 : 30) {
                // タイトル
                if showContent {
                    VStack(spacing: isSmallScreen ? 6 : 10) {
                        Text("🎊 COMPLETE! 🎊")
                            .font(.system(size: isSmallScreen ? 28 : 40, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .yellow, radius: 10)
                            .scaleEffect(showContent ? 1.0 : 0.5)
                            .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showContent)
                        
                        Text("\(prefecture) レベル\(level)")
                            .font(isSmallScreen ? .headline : .title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                
                // リザルトカード
                VStack(spacing: isSmallScreen ? 12 : 20) {
                    // 経験値獲得
                    if showExperience {
                        VStack(spacing: isSmallScreen ? 10 : 16) {
                            HStack(spacing: isSmallScreen ? 8 : 12) {
                                Image(systemName: "bolt.circle.fill")
                                    .font(.system(size: isSmallScreen ? 44 : 60))
                                    .foregroundColor(.yellow)
                                    .rotationEffect(.degrees(rotation))
                                    .shadow(color: .yellow.opacity(0.5), radius: 20)
                                
                                Spacer()
                            }
                            
                            VStack(spacing: isSmallScreen ? 4 : 8) {
                                Text("経験値獲得！")
                                    .font(isSmallScreen ? .headline : .title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                HStack(spacing: isSmallScreen ? 4 : 8) {
                                    Text("+\(experiencePoints)")
                                        .font(.system(size: isSmallScreen ? 36 : 48, weight: .heavy))
                                        .foregroundColor(.yellow)
                                        .shadow(color: .yellow.opacity(0.5), radius: 10)
                                    
                                    Text("EXP")
                                        .font(isSmallScreen ? .subheadline : .title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                        }
                        .padding(isSmallScreen ? 16 : 24)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(
                                            LinearGradient(
                                                gradient: Gradient(colors: [.yellow, .orange]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 3
                                        )
                                )
                        )
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    // 投稿回数ボーナス
                    if showPostBonus {
                        VStack(spacing: isSmallScreen ? 10 : 16) {
                            HStack(spacing: isSmallScreen ? 8 : 12) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: isSmallScreen ? 44 : 60))
                                    .foregroundColor(.green)
                                    .rotationEffect(.degrees(-rotation))
                                    .shadow(color: .green.opacity(0.5), radius: 20)
                                
                                Spacer()
                            }
                            
                            VStack(spacing: isSmallScreen ? 4 : 8) {
                                Text("投稿回数ボーナス！")
                                    .font(isSmallScreen ? .headline : .title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                HStack(spacing: isSmallScreen ? 4 : 8) {
                                    Text("+\(postBonus)")
                                        .font(.system(size: isSmallScreen ? 36 : 48, weight: .heavy))
                                        .foregroundColor(.green)
                                        .shadow(color: .green.opacity(0.5), radius: 10)
                                    
                                    Text("回")
                                        .font(isSmallScreen ? .subheadline : .title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                        }
                        .padding(isSmallScreen ? 16 : 24)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(
                                            LinearGradient(
                                                gradient: Gradient(colors: [.green, .cyan]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 3
                                        )
                                )
                        )
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    // 次のレベル
                    if showNextLevel {
                        VStack(spacing: isSmallScreen ? 8 : 12) {
                            Divider()
                                .background(Color.white.opacity(0.5))
                            
                            VStack(spacing: isSmallScreen ? 4 : 8) {
                                Text("次のレベル")
                                    .font(isSmallScreen ? .subheadline : .headline)
                                    .foregroundColor(.white.opacity(0.9))
                                
                                HStack {
                                    Text("必要ゲージ:")
                                        .foregroundColor(.white.opacity(0.7))
                                    Text("\(nextMaxValue)")
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                                .font(isSmallScreen ? .caption : .subheadline)
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(isSmallScreen ? 16 : 24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.3))
                        .shadow(color: .white.opacity(0.3), radius: 20)
                )
                .padding(.horizontal, isSmallScreen ? 20 : 30)
                
                Spacer()
                
                // ボタン
                if showNextLevel {
                    VStack(spacing: isSmallScreen ? 8 : 12) {
                        Button(action: {
                            withAnimation {
                                isPresented = false
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("続ける")
                                    .fontWeight(.semibold)
                            }
                            .font(isSmallScreen ? .subheadline : .headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(isSmallScreen ? 12 : 16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.purple]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(isSmallScreen ? 12 : 15)
                            .shadow(color: .blue.opacity(0.5), radius: 10)
                        }
                        .padding(.horizontal, isSmallScreen ? 20 : 30)
                        
                        Button(action: {
                            shareResult()
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("シェアする")
                            }
                            .font(isSmallScreen ? .caption : .subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                Spacer()
            }
            .padding(.top, isSmallScreen ? 40 : 60)
        }
        .onAppear {
            startAnimations()
            generateParticles()
        }
        }
    }
    
    private func startAnimations() {
        // グラデーションアニメーション
        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
            rotation = 360
        }
        
        // コンテンツを順番に表示
        withAnimation(.easeOut(duration: 0.5)) {
            showContent = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showExperience = true
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showPostBonus = true
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeOut(duration: 0.5)) {
                showNextLevel = true
            }
        }
    }
    
    private func generateParticles() {
        // 初期パーティクル生成
        for _ in 0..<30 {
            particles.append(Particle.random())
        }
        
        // パーティクルアニメーション
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if !isPresented {
                timer.invalidate()
                return
            }
            
            // 古いパーティクルを削除して新しいのを追加
            particles.removeAll { $0.opacity < 0.1 }
            if particles.count < 50 {
                particles.append(Particle.random())
            }
            
            // パーティクルを更新
            for i in particles.indices {
                particles[i].update()
            }
        }
    }
    
    private func shareResult() {
        // TODO: シェア機能の実装
        print("シェア機能")
    }
}

// パーティクル構造体
struct Particle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGPoint
    var size: CGFloat
    var color: Color
    var opacity: Double
    
    static func random() -> Particle {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        return Particle(
            position: CGPoint(
                x: CGFloat.random(in: 0...screenWidth),
                y: CGFloat.random(in: 0...screenHeight)
            ),
            velocity: CGPoint(
                x: CGFloat.random(in: -2...2),
                y: CGFloat.random(in: -5...(-1))
            ),
            size: CGFloat.random(in: 4...12),
            color: [.yellow, .orange, .pink, .purple, .cyan, .white].randomElement()!,
            opacity: Double.random(in: 0.5...1.0)
        )
    }
    
    mutating func update() {
        position.x += velocity.x
        position.y += velocity.y
        opacity -= 0.01
        
        // 画面外に出たら再生成
        if position.y < -50 {
            self = Particle.random()
        }
    }
}

#Preview {
    GaugeCompleteView(
        prefecture: "東京都",
        level: 1,
        experiencePoints: 100,
        postBonus: 1,
        nextMaxValue: 120,
        isPresented: .constant(true)
    )
}

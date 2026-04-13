import SwiftUI

struct MistEventTutorialView: View {
    @Binding var isPresented: Bool
    @State private var currentStep = 0
    
    private let steps: [TutorialStep] = [
        TutorialStep(
            emoji: "☁️",
            title: "モヤイベントが出現！",
            description: "地図上に悲しい感情が集まると、モヤイベントが発生します。\n\nモヤを晴らして、みんなの心を明るくしましょう！"
        ),
        TutorialStep(
            emoji: "✨",
            title: "モヤを晴らす方法",
            description: "モヤの黒い部分をタップして、ポジティブな感情を投稿すると、モヤが少しずつ晴れていきます。\n\n【2つの浄化方法】\n① HPを0にする（通常の投稿）\n② 😊 嬉しい投稿を5回する\n\n複数のユーザーで協力して、モヤを完全に晴らしましょう！"
        ),
        TutorialStep(
            emoji: "🎁",
            title: "報酬をゲット",
            description: "モヤを晴らすと、経験値や投稿回数などの報酬がもらえます。\n\nさあ、モヤイベントに挑戦してみましょう！"
        )
    ]
    
    var body: some View {
        ZStack {
            // 半透明の背景
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // 絵文字
                Text(steps[currentStep].emoji)
                    .font(.system(size: 80))
                
                VStack(alignment: .leading, spacing: 16) {
                    // ステップインジケーター
                    HStack(spacing: 8) {
                        ForEach(0..<steps.count, id: \.self) { index in
                            Capsule()
                                .fill(index == currentStep ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: index == currentStep ? 24 : 8, height: 8)
                                .animation(.easeInOut, value: currentStep)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                    // タイトル
                    Text(steps[currentStep].title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    // 説明
                    Text(steps[currentStep].description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineSpacing(6)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    
                    // ボタン
                    HStack {
                        if currentStep > 0 {
                            Button(action: {
                                withAnimation {
                                    currentStep -= 1
                                }
                            }) {
                                Text("戻る")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Button(action: {
                            completeTutorial()
                        }) {
                            Text("スキップ")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            if currentStep < steps.count - 1 {
                                withAnimation {
                                    currentStep += 1
                                }
                            } else {
                                completeTutorial()
                            }
                        }) {
                            Text(currentStep < steps.count - 1 ? "次へ" : "始める")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(24)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(16)
                .shadow(radius: 20)
            }
            .padding(.horizontal, 32)
        }
    }
    
    private func completeTutorial() {
        UserDefaults.standard.set(true, forKey: "hasSeenMistEventTutorial")
        withAnimation {
            isPresented = false
        }
    }
}

private struct TutorialStep {
    let emoji: String
    let title: String
    let description: String
}

#Preview {
    MistEventTutorialView(isPresented: .constant(true))
}

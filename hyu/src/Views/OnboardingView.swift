import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @Binding var selectedTab: Int
    @State private var currentStep = 0
    
    private let steps: [OnboardingStep] = [
        OnboardingStep(
            title: "ようこそ！",
            description: "エモナルは、感情と旅を記録する新しいSNSアプリです。\n使い方を簡単にご紹介します。",
            targetTab: nil,
            highlightArea: nil
        ),
        OnboardingStep(
            title: "投稿する",
            description: "「投稿」タブから、今の気持ちを記録できます。\n観光スポットや現在地で投稿してみましょう。\n\n📢 投稿回数について：\n午前と午後にランダムな時間に通知が届きます。\n通知から1分以内に投稿すると、1日10回まで投稿可能！\n時間内に投稿できなかった場合は5回までとなります。",
            targetTab: 1, // 投稿タブ
            highlightArea: .tab(1)
        ),
        OnboardingStep(
            title: "地図で感情を確認",
            description: "「地図」タブで、あなたや他のユーザーの感情を地図上で確認できます。\n投稿された場所に色がつきます。\n\n悲しい感情が集まってしまうと、、",
            targetTab: 2, // 地図タブ
            highlightArea: .map
        ),
        OnboardingStep(
            title: "プロフィールと設定",
            description: "「プロフィール」タブから、自分の投稿履歴や友達、設定を確認できます。\n通知設定もここから変更できます。",
            targetTab: 3, // プロフィールタブ
            highlightArea: .tab(3)
        ),
        OnboardingStep(
            title: "ミニゲームで楽しもう",
            description: "感情をたくさん投稿してゲージをいっぱいにしよう！\n\nゲージが満タンになると報酬がもらえます：\n⚡ 経験値 +100~\n➕ 投稿回数 +1~回\n\nレベルが上がるほど報酬も増えます！\nさあ、エモナルを始めましょう！",
            targetTab: 0, // ミニゲームタブ
            highlightArea: .tab(0)
        )
    ]
    
    var body: some View {
        ZStack {
            // 半透明の背景（最初のステップは濃く、それ以降は薄く）
            Color.black.opacity(currentStep == 0 ? 0.7 : 0.25)
                .ignoresSafeArea()
            
            VStack {
                // 説明カードを上部に配置
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
                    
                    // タイトル
                    Text(steps[currentStep].title)
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    // 説明
                    Text(steps[currentStep].description)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                    
                    // ボタン
                    HStack {
                        if currentStep > 0 {
                            Button(action: {
                                withAnimation {
                                    currentStep -= 1
                                    if let targetTab = steps[currentStep].targetTab {
                                        selectedTab = targetTab
                                    }
                                }
                            }) {
                                Text("戻る")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Button(action: {
                            completeOnboarding()
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
                                    if let targetTab = steps[currentStep].targetTab {
                                        selectedTab = targetTab
                                    }
                                }
                            } else {
                                completeOnboarding()
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
                .padding(20)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(16)
                .shadow(radius: 20)
                .padding(.horizontal, 20)
                .padding(.top, 80)
                
                Spacer()
            }
        }
        .onAppear {
            // 初回表示時はタブを移動しない
            if currentStep == 0 {
                // ウェルカム画面なので何もしない
            }
        }
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        withAnimation {
            isPresented = false
            selectedTab = 1  // 投稿タブに戻す
        }
    }
}

struct OnboardingStep {
    let title: String
    let description: String
    let targetTab: Int?
    let highlightArea: HighlightArea?
}

enum HighlightArea {
    case map
    case tab(Int)
}

#Preview {
    OnboardingView(isPresented: .constant(true), selectedTab: .constant(0))
}

import SwiftUI

struct EmotionPostView: View {
    private let firestoreService = FirestoreService()
    @StateObject private var locationService = LocationService()
    
    @State private var emotionLevel: EmotionLevel = .zero
    @State private var posts: [EmotionPost] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            TimelineView(posts: posts)

            VStack {
                // エラーメッセージ表示
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(8)
                        .background(Color.white.opacity(0.9))
                        .cornerRadius(8)
                        .padding(.top, 20)
                        .onTapGesture {
                            self.errorMessage = nil
                        }
                }
                
                Spacer()

                Slider(
                    value: Binding(
                        get: { Double(emotionLevel.rawValue) },
                        set: { emotionLevel = EmotionLevel.clamped(Int($0)) }
                    ),
                    in: -5...5,
                    step: 1
                )
                .tint(.white)
                .padding(.horizontal, 40)
                .disabled(isLoading)

                Spacer()

                Button(action: submit) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(isLoading ? 0.5 : 0.9))
                            .frame(width: 64, height: 64)
                        if isLoading {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Circle()
                                .fill(Color.black.opacity(0.15))
                                .frame(width: 24, height: 24)
                        }
                    }
                }
                .disabled(isLoading)
                .padding(.bottom, 48)
            }
        }
        .background(background)
        .ignoresSafeArea()
        .task {
            locationService.requestPermission()
            await loadPosts()
        }
    }

    private var background: some View {
        let base = emotionColor
        let darker = base.opacity(0.85)
        return LinearGradient(
            colors: [darker, base],
            startPoint: .top,
            endPoint: .bottom
        )
        .animation(.easeInOut(duration: 0.2), value: emotionLevel.rawValue)
    }

    private var emotionColor: Color {
        let t = Double(emotionLevel.rawValue + 5) / 10
        let hue = 0.62 - 0.62 * t
        return Color(hue: hue, saturation: 0.55, brightness: 0.95)
    }

    private func submit() {
        guard !isLoading else { return }
        
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                // 位置情報を取得
                let location = await locationService.getCurrentLocation()
                let latitude = location?.coordinate.latitude
                let longitude = location?.coordinate.longitude
                
                try await firestoreService.postEmotion(
                    level: emotionLevel,
                    visualType: .glow,
                    latitude: latitude,
                    longitude: longitude
                )
                
                // ローカルにも追加（即座に表示）
                let post = EmotionPost(
                    level: emotionLevel,
                    visualType: .glow,
                    latitude: latitude,
                    longitude: longitude
                )
                await MainActor.run {
                    posts.append(post)
                }
                
                // Firestoreから最新データを再取得
                await loadPosts()
            } catch {
                await MainActor.run {
                    errorMessage = "エラー: \(error.localizedDescription)"
                }
            }
            
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func loadPosts() async {
        do {
            let fetchedPosts = try await firestoreService.fetchRecentEmotions(lastHours: 6)
            await MainActor.run {
                posts = fetchedPosts
            }
        } catch {
            await MainActor.run {
                errorMessage = "データの取得に失敗しました: \(error.localizedDescription)"
            }
        }
    }
}

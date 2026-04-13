import SwiftUI
import MapKit

struct EmotionMapView: View {
    @StateObject private var locationService = LocationService()
    private let firestoreService = FirestoreService()
    
    @State private var posts: [EmotionPost] = []
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503), // 東京
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var selectedPost: EmotionPost?
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            Map(coordinateRegion: $region, annotationItems: postsWithLocation) { post in
                MapAnnotation(coordinate: post.coordinate) {
                    EmotionPin(post: post)
                        .onTapGesture {
                            selectedPost = post
                        }
                }
            }
            .ignoresSafeArea()
            .onAppear {
                locationService.requestPermission()
                Task {
                    await loadPosts()
                }
            }
            .onChange(of: region.center.latitude) { _ in
                Task {
                    await loadPostsForRegion()
                }
            }
            .onChange(of: region.center.longitude) { _ in
                Task {
                    await loadPostsForRegion()
                }
            }
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        Task {
                            await updateToCurrentLocation()
                        }
                    }) {
                        Image(systemName: "location.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .sheet(item: $selectedPost) { post in
            NavigationView {
                EmotionDetailSheet(post: post)
            }
        }
    }
    
    private var postsWithLocation: [EmotionPost] {
        posts.filter { $0.latitude != nil && $0.longitude != nil }
    }
    
    private func loadPosts() async {
        isLoading = true
        do {
            let fetchedPosts = try await firestoreService.fetchRecentEmotions(lastHours: 24)
            await MainActor.run {
                posts = fetchedPosts
                if let firstPost = fetchedPosts.first(where: { $0.latitude != nil && $0.longitude != nil }) {
                    region.center = firstPost.coordinate
                }
            }
        } catch {
            print("エラー: \(error.localizedDescription)")
        }
        isLoading = false
    }
    
    private func loadPostsForRegion() async {
        do {
            let fetchedPosts = try await firestoreService.fetchEmotionsInRegion(
                centerLatitude: region.center.latitude,
                centerLongitude: region.center.longitude,
                radiusKm: 10.0
            )
            await MainActor.run {
                posts = fetchedPosts
            }
        } catch {
            print("エラー: \(error.localizedDescription)")
        }
    }
    
    private func updateToCurrentLocation() async {
        if let location = await locationService.getCurrentLocation() {
            await MainActor.run {
                region.center = location.coordinate
            }
            await loadPostsForRegion()
        }
    }
}

private struct EmotionPin: View {
    let post: EmotionPost
    
    var body: some View {
        ZStack {
            Circle()
                .fill(pinColor)
                .frame(width: 30, height: 30)
                .shadow(radius: 3)
            
            Text(emoji)
                .font(.system(size: 16))
        }
    }
    
    private var pinColor: Color {
        let t = Double(post.level.rawValue + 5) / 10
        let hue = 0.62 - 0.62 * t
        return Color(hue: hue, saturation: 0.7, brightness: 0.9)
    }
    
    private var emoji: String {
        switch post.level {
        case .minusFive, .minusFour: return "😢"
        case .minusThree, .minusTwo: return "😔"
        case .minusOne: return "😐"
        case .zero: return "😊"
        case .plusOne: return "😄"
        case .plusTwo, .plusThree: return "😃"
        case .plusFour, .plusFive: return "🤩"
        }
    }
}

private struct EmotionDetailSheet: View {
    let post: EmotionPost
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
                Text(emoji)
                    .font(.system(size: 80))
                
                Text(levelText)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("\(post.level.rawValue)")
                    .font(.title)
                    .foregroundColor(.secondary)
                
                if let createdAt = formatDate(post.createdAt) {
                    Text(createdAt)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("感情の詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
    }
    
    private var emoji: String {
        switch post.level {
        case .minusFive, .minusFour: return "😢"
        case .minusThree, .minusTwo: return "😔"
        case .minusOne: return "😐"
        case .zero: return "😊"
        case .plusOne: return "😄"
        case .plusTwo, .plusThree: return "😃"
        case .plusFour, .plusFive: return "🤩"
        }
    }
    
    private var levelText: String {
        switch post.level {
        case .minusFive: return "とても悲しい"
        case .minusFour: return "悲しい"
        case .minusThree: return "少し悲しい"
        case .minusTwo: return "やや悲しい"
        case .minusOne: return "少し低い"
        case .zero: return "普通"
        case .plusOne: return "少し高い"
        case .plusTwo: return "やや嬉しい"
        case .plusThree: return "少し嬉しい"
        case .plusFour: return "嬉しい"
        case .plusFive: return "とても嬉しい"
        }
    }
    
    private func formatDate(_ date: Date) -> String? {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
}

extension EmotionPost {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude ?? 0,
            longitude: longitude ?? 0
        )
    }
}

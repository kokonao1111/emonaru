import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            EmotionPostView()
                .tabItem {
                    Label("投稿", systemImage: "heart.fill")
                }
            
            EmotionMapView()
                .tabItem {
                    Label("地図", systemImage: "map.fill")
                }
        }
    }
}

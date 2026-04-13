import SwiftUI
import UIKit

struct ProfileShareView: View {
    let userName: String
    let level: Int
    let profileImage: UIImage?
    
    @Environment(\.dismiss) private var dismiss
    @State private var qrCodeImage: UIImage?
    @State private var shareableImage: UIImage?
    @State private var showShareSheet = false
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            ZStack {
                // 背景グラデーション
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.2),
                        Color(red: 0.2, green: 0.1, blue: 0.3)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if isLoading {
                    ProgressView("QRコードを生成中...")
                        .foregroundColor(.white)
                } else {
                    ScrollView {
                        VStack(spacing: 30) {
                            // タイトル
                            VStack(spacing: 8) {
                                Text("プロフィールをシェア")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                Text("友達にQRコードを読み取ってもらおう！")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(.top, 20)
                            
                            // プロフィール情報とQRコード
                            VStack(spacing: 20) {
                                // プロフィール画像
                                if let profileImage = profileImage {
                                    Image(uiImage: profileImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 3)
                                        )
                                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                                } else {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 100, height: 100)
                                        .overlay(
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 40))
                                                .foregroundColor(.white.opacity(0.6))
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 3)
                                        )
                                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                                }
                                
                                // ユーザー名
                                Text(userName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                // レベル
                                Text("Lv.\(level)")
                                    .font(.headline)
                                    .foregroundColor(.white.opacity(0.7))
                                
                                // QRコード
                                if let qrCodeImage = qrCodeImage {
                                    VStack(spacing: 16) {
                                        Image(uiImage: qrCodeImage)
                                            .interpolation(.none)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 250, height: 250)
                                            .padding(20)
                                            .background(Color.white)
                                            .cornerRadius(20)
                                            .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 8)
                                        
                                        Text("このQRコードをスキャンして\nエモナルで友達になろう！")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.8))
                                            .multilineTextAlignment(.center)
                                    }
                                }
                            }
                            .padding(.vertical, 30)
                            
                            // シェアボタン
                            VStack(spacing: 16) {
                                Button(action: {
                                    showShareSheet = true
                                }) {
                                    HStack {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 20))
                                        Text("シェアする")
                                            .font(.headline)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(15)
                                    .shadow(color: .blue.opacity(0.5), radius: 10, x: 0, y: 5)
                                }
                                .padding(.horizontal, 30)
                                
                                Text("Instagram、LINE、Twitterなどで\nシェアできます")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.bottom, 30)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            generateQRCode()
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareableImage = shareableImage {
                ActivityViewController(activityItems: [shareableImage])
            }
        }
    }
    
    private func generateQRCode() {
        Task {
            isLoading = true
            
            // QRコード生成
            let userID = UserService.shared.currentUserID
            if let qrCode = QRCodeService.shared.generateQRCode(for: userID) {
                await MainActor.run {
                    qrCodeImage = qrCode
                }
                
                // シェア用画像生成
                if let shareable = QRCodeService.shared.generateShareableProfileImage(
                    userName: userName,
                    level: level,
                    qrCode: qrCode,
                    profileImage: profileImage
                ) {
                    await MainActor.run {
                        shareableImage = shareable
                    }
                }
            }
            
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// UIActivityViewControllerをSwiftUIで使用するためのラッパー
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

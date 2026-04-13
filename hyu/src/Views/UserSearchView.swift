
import SwiftUI
import FirebaseFirestore
import FirebaseStorage
import PhotosUI

struct UserSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery: String = ""
    @State private var searchResults: [(userID: String, userName: String, level: Int, profileImageURL: String?)] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var profileImages: [String: UIImage] = [:]
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var scannedUserID: String?
    @State private var showUserProfile = false
    
    private let firestoreService = FirestoreService()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // QRコード画像読み取りボタン
                Button(action: {
                    showImagePicker = true
                }) {
                    HStack {
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                        Text("QRコード画像から友達を追加")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.green, Color.teal]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(15)
                    .shadow(color: .green.opacity(0.3), radius: 5, x: 0, y: 3)
                }
                .padding()
                
                // 検索バー
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("ユーザー名を検索", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit {
                            performSearch()
                        }
                    
                    if !searchQuery.isEmpty {
                        Button(action: {
                            searchQuery = ""
                            searchResults = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                // 検索結果
                if isSearching {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Spacer()
                } else if let errorMessage = errorMessage {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else if searchQuery.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("ユーザー名を入力して検索")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else if searchResults.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "person.fill.questionmark")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("ユーザーが見つかりませんでした")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(searchResults, id: \.userID) { result in
                            NavigationLink(destination: UserProfileView(userID: result.userID)) {
                                HStack(spacing: 12) {
                                    // プロフィール画像
                                    if let image = profileImages[result.userID] {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 50, height: 50)
                                            .clipShape(Circle())
                                    } else {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 50, height: 50)
                                            .overlay(
                                                Text("😊")
                                                    .font(.system(size: 24))
                                            )
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(result.userName)
                                            .font(.headline)
                                        Text("レベル \(result.level)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .onAppear {
                                loadProfileImage(for: result.userID, url: result.profileImageURL)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("ユーザー検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage {
                detectQRCodeFromImage(image)
            }
        }
        .sheet(isPresented: $showUserProfile) {
            if let userID = scannedUserID {
                NavigationView {
                    UserProfileView(userID: userID)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("閉じる") {
                                    showUserProfile = false
                                }
                            }
                        }
                }
            }
        }
    }
    
    private func performSearch() {
        Task {
            await MainActor.run {
                isSearching = true
                errorMessage = nil
            }
            
            do {
                let results = try await firestoreService.searchUsers(query: searchQuery)
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "検索に失敗しました"
                    isSearching = false
                }
                print("❌ 検索エラー: \(error.localizedDescription)")
            }
        }
    }
    
    private func loadProfileImage(for userID: String, url: String?) {
        // 既に読み込み済みの場合はスキップ
        if profileImages[userID] != nil {
            return
        }
        
        guard let urlString = url, !urlString.isEmpty else {
            return
        }
        
        Task {
            do {
                let storageRef = Storage.storage().reference(forURL: urlString)
                let data = try await storageRef.data(maxSize: 5 * 1024 * 1024)
                
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        profileImages[userID] = image
                    }
                }
            } catch {
                print("⚠️ プロフィール画像の読み込みに失敗: \(error.localizedDescription)")
            }
        }
    }
    
    private func detectQRCodeFromImage(_ image: UIImage) {
        // バックグラウンドスレッドで画像処理を実行
        Task.detached(priority: .userInitiated) {
            do {
                // 画像をリサイズ（メモリ節約）
                let resizedImage = await self.resizeImage(image: image, maxSize: 1024)
                
                guard let ciImage = CIImage(image: resizedImage) else {
                    await MainActor.run {
                        self.errorMessage = "画像を読み込めませんでした"
                    }
                    return
                }
                
                let context = CIContext()
                let options = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
                
                guard let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: context, options: options) else {
                    await MainActor.run {
                        self.errorMessage = "QRコード検出機能の初期化に失敗しました"
                    }
                    return
                }
                
                let features = detector.features(in: ciImage, options: nil)
                
                if let qrFeature = features.first(where: { $0 is CIQRCodeFeature }) as? CIQRCodeFeature,
                   let messageString = qrFeature.messageString {
                    print("📷 画像からQRコード検出: \(messageString)")
                    await MainActor.run {
                        self.handleScannedCode(messageString)
                    }
                } else {
                    await MainActor.run {
                        self.errorMessage = "QRコードが見つかりませんでした"
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            await MainActor.run {
                                self.errorMessage = nil
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "画像処理中にエラーが発生しました"
                    print("❌ QRコード検出エラー: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func resizeImage(image: UIImage, maxSize: CGFloat) async -> UIImage {
        let size = image.size
        let ratio = min(maxSize / size.width, maxSize / size.height)
        
        // 既に小さい場合はそのまま返す
        if ratio >= 1 {
            return image
        }
        
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        
        return await Task.detached(priority: .userInitiated) {
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return resizedImage ?? image
        }.value
    }
    
    private func handleScannedCode(_ code: String) {
        // QRコードからユーザーIDを抽出
        // 形式: "emotionapp://user/{userID}"
        if code.hasPrefix("emotionapp://user/") {
            let userID = code.replacingOccurrences(of: "emotionapp://user/", with: "")
            print("✅ QRコードスキャン成功: \(userID)")
            
            // 自分自身のQRコードの場合
            if userID == UserService.shared.currentUserID {
                errorMessage = "自分自身のQRコードです"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    errorMessage = nil
                }
                return
            }
            
            // プロフィール画面を表示
            scannedUserID = userID
            showUserProfile = true
        } else {
            errorMessage = "無効なQRコードです"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                errorMessage = nil
            }
        }
    }
}

// 画像選択用のUIViewControllerRepresentable
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

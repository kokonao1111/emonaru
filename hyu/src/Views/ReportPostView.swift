import SwiftUI

struct ReportPostView: View {
    let postID: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: String = ""
    @State private var customReason: String = ""
    @State private var isReporting = false
    @State private var showSuccessAlert = false
    @State private var errorMessage: String?
    
    private let firestoreService = FirestoreService()
    
    private let reportReasons = [
        "不適切なコンテンツ",
        "スパムや宣伝",
        "嫌がらせやハラスメント",
        "違法な内容",
        "その他"
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("報告理由を選択してください")) {
                    ForEach(reportReasons, id: \.self) { reason in
                        Button(action: {
                            selectedReason = reason
                        }) {
                            HStack {
                                Text(reason)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedReason == reason {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                if selectedReason == "その他" {
                    Section(header: Text("詳細を入力してください")) {
                        TextField("報告理由を入力", text: $customReason, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("投稿を報告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("報告する") {
                        Task {
                            await reportPost()
                        }
                    }
                    .disabled(selectedReason.isEmpty || isReporting)
                    .fontWeight(.semibold)
                }
            }
            .alert("報告しました", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("報告を受け付けました。24時間以内に確認し、必要に応じて対応いたします。")
            }
        }
    }
    
    private func reportPost() async {
        guard !selectedReason.isEmpty else { return }
        
        isReporting = true
        errorMessage = nil
        
        let reason = selectedReason == "その他" ? customReason : selectedReason
        
        do {
            try await firestoreService.reportPost(postID: postID, reason: reason)
            await MainActor.run {
                showSuccessAlert = true
            }
        } catch {
            await MainActor.run {
                errorMessage = "報告に失敗しました: \(error.localizedDescription)"
            }
        }
        
        isReporting = false
    }
}

#Preview {
    ReportPostView(postID: "test-post-id")
}

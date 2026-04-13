import SwiftUI

public struct CommentInputModal: View {
    @Binding var comment: String
    let onPost: () -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    @State private var errorMessage: String?
    
    private let maxLength = 20 // 最大文字数
    
    // 不適切な言葉のリスト（誤魔化し入力も考慮）
    private let inappropriateWords = [
        "死ね", "しね", "氏ね", "殺す", "ころす", "殺害", "自殺",
        "消えろ", "消え失せろ", "ぶっころ", "ぶっ殺",
        "バカ", "ばか", "馬鹿", "アホ", "あほ", "間抜け", "クズ", "くず", "ゴミ",
        "うざい", "キモ", "きも", "気持ち悪",
        "クソ", "くそ", "糞", "ちんかす", "まんこ", "ちんこ",
        "fuck", "fxxk", "shit", "bitch", "die", "kill"
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("コメントを入力してください")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.top, 20)
                
                VStack(alignment: .trailing, spacing: 8) {
                    TextField("一言コメントを入力...", text: $comment, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(16)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .lineLimit(3...6)
                    .focused($isTextFieldFocused)
                    .onChange(of: comment) { oldValue, newValue in
                        // 20文字を超える場合は自動的に20文字に戻す
                        if newValue.count > maxLength {
                            comment = String(newValue.prefix(maxLength))
                        }
                        // 入力中はエラーメッセージをクリア
                        errorMessage = nil
                    }
                    .onAppear {
                        // モーダルが表示されたら自動的にキーボードを表示
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isTextFieldFocused = true
                        }
                    }
                    
                    // 文字数カウンター
                    Text("\(comment.count)/\(maxLength)")
                        .font(.caption)
                        .foregroundColor(comment.count >= maxLength ? .red : .secondary)
                        .padding(.trailing, 4)
                }
                
                // エラーメッセージ
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button(action: {
                        onCancel()
                        dismiss()
                    }) {
                        Text("キャンセル")
                            .font(.headline)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                    }
                    
                    Button(action: {
                        if validateComment() {
                            onPost()
                            dismiss()
                        }
                    }) {
                        Text("投稿する")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func validateComment() -> Bool {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 空白のみの場合はOK（コメントなしで投稿できる）
        if trimmed.isEmpty {
            return true
        }
        
        // 不適切な言葉をチェック（記号/空白混ぜも検知）
        let normalized = normalizeForModeration(comment)
        for word in inappropriateWords {
            let normalizedWord = normalizeForModeration(word)
            if normalized.contains(normalizedWord) {
                errorMessage = "不適切な言葉が含まれています"
                return false
            }
        }
        
        return true
    }

    private func normalizeForModeration(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        let katakanaUnified = folded.applyingTransform(.hiraganaToKatakana, reverse: false) ?? folded
        let noSeparators = katakanaUnified.replacingOccurrences(
            of: "[\\s\\p{P}\\p{S}ーｰ＿_]+",
            with: "",
            options: .regularExpression
        )
        return noSeparators.lowercased()
    }
}

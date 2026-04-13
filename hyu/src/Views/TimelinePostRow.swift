import SwiftUI

struct TimelinePostRow: View {
    let post: EmotionPost
    
    var body: some View {
        HStack(spacing: 12) {
            // 感情レベルの絵文字
            Text(emoji)
                .font(.title)
                .frame(width: 50, height: 50)
                .background(Circle().fill(emotionColor.opacity(0.3)))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(levelText)
                    .font(.headline)
                    .foregroundColor(.white)
                
                if let createdAt = formatDate(post.createdAt) {
                    Text(createdAt)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                // コメント表示（友達のみの投稿でコメントがある場合）
                if let comment = post.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.top, 4)
                        .lineLimit(2)
                }
                
                // 応援/共感の表示
                if post.supportCount > 0 {
                    HStack(spacing: 4) {
                        Text(post.isSadEmotion ? "💪" : "🤗")
                            .font(.caption)
                        Text("\(post.supportCount)")
                            .font(.caption)
                    }
                    .foregroundColor(.white.opacity(0.8))
                }
            }
            
            Spacer()
            
            // 数値表示
            Text("\(post.level.rawValue)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(emotionColor))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .cornerRadius(12)
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
    
    private var emotionColor: Color {
        let t = Double(post.level.rawValue + 5) / 10
        let hue = 0.62 - 0.62 * t
        return Color(hue: hue, saturation: 0.7, brightness: 0.9)
    }
    
    private func formatDate(_ date: Date) -> String? {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

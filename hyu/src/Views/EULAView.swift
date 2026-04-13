import SwiftUI

struct EULAView: View {
    @Binding var isPresented: Bool
    @State private var hasAgreed = false
    let onAgree: () -> Void
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("利用規約")
                        .font(.title)
                        .fontWeight(.bold)
                        .padding(.bottom, 8)
                    
                    Text("最終更新日: 2026年2月5日")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 16)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        SectionView(title: "1. 利用規約への同意", content: """
                        本アプリ「エモナル」をご利用いただくことで、本利用規約に同意したものとみなされます。
                        """)
                        
                        SectionView(title: "2. 不適切なコンテンツの禁止", content: """
                        以下のような不適切なコンテンツの投稿は禁止されています：
                        • 違法な内容
                        • 他者を誹謗中傷する内容
                        • 差別的な内容
                        • 性的に露骨な内容
                        • 暴力的な内容
                        • スパムや宣伝目的の内容
                        
                        不適切なコンテンツを発見した場合、報告機能をご利用ください。
                        """)
                        
                        SectionView(title: "3. ユーザーの行動", content: """
                        以下の行為は禁止されています：
                        • 他のユーザーへの嫌がらせやハラスメント
                        • 虚偽の情報の投稿
                        • アカウントの不正利用
                        • システムの妨害行為
                        
                        これらの行為が発見された場合、アカウントが凍結または削除される場合があります。
                        """)
                        
                        SectionView(title: "4. コンテンツの報告", content: """
                        不適切なコンテンツやユーザーを発見した場合、報告機能をご利用ください。
                        報告されたコンテンツは24時間以内に確認し、必要に応じて削除します。
                        """)
                        
                        SectionView(title: "5. ユーザーのブロック", content: """
                        他のユーザーをブロックすることができます。
                        ブロックしたユーザーの投稿は、あなたのフィードから即座に非表示になります。
                        """)
                        
                        SectionView(title: "6. アカウントの削除", content: """
                        アカウントを削除すると、すべてのデータ（投稿、友達関係、プロフィール情報など）が永久に削除され、復元できません。
                        設定画面からアカウントを削除できます。
                        """)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("利用規約")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("同意する") {
                        hasAgreed = true
                        UserDefaults.standard.set(true, forKey: "hasAgreedToEULA")
                        onAgree()
                        isPresented = false
                    }
                    .disabled(!hasAgreed)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                // スクロールして最後まで読んだら同意可能にする
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    hasAgreed = true
                }
            }
        }
    }
}

private struct SectionView: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(content)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    EULAView(isPresented: .constant(true)) {
        print("Agreed")
    }
}

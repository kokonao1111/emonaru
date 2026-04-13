import SwiftUI
import WebKit

struct HTMLTimelineView: UIViewRepresentable {
    let posts: [EmotionPost]
    @Binding var contentHeight: CGFloat
    let onPostTapped: (EmotionPost) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        
        let configuration = WKWebViewConfiguration()
        // JavaScriptからSwiftにメッセージを送るためのハンドラーを追加
        configuration.userContentController.add(context.coordinator, name: "postTapped")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        
        // スクロールを完全に無効化
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentOffset = .zero
        webView.scrollView.scrollsToTop = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.isDirectionalLockEnabled = true
        
        // スクロールバーを完全に非表示にする
        webView.scrollView.indicatorStyle = .default
        
        // コンテナビューに追加
        containerView.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: containerView.topAnchor),
            webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        // HTMLファイルを読み込む
        loadHTMLFile(into: webView)
        
        // コンテキストにwebViewとparentを保存
        context.coordinator.webView = webView
        context.coordinator.parent = self
        
        return containerView
    }
    
    func updateUIView(_ containerView: UIView, context: Context) {
        guard let webView = context.coordinator.webView else { return }
        
        // parentを更新
        context.coordinator.parent = self
        
        // WKWebViewのスクロールを常に無効化（毎回確実に設定）
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentOffset = .zero
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.isDirectionalLockEnabled = true
        
        // スクロールバーを強制的に非表示にする
        DispatchQueue.main.async {
            // スクロールバーのサブビューを非表示にする
            for subview in webView.scrollView.subviews {
                if String(describing: type(of: subview)).contains("ScrollIndicator") {
                    subview.isHidden = true
                    subview.alpha = 0
                }
                if let scrollBar = subview as? UIImageView {
                    scrollBar.isHidden = true
                    scrollBar.alpha = 0
                }
            }
        }
        
        // JavaScriptでデータを更新（データ更新後に自動的に高さも更新される）
        updateTimelineData(in: webView)
    }
    
    private func loadHTMLFile(into webView: WKWebView) {
        // HTMLファイルのパスを取得
        guard let htmlPath = Bundle.main.path(forResource: "timeline", ofType: "html", inDirectory: nil) else {
            // フォールバック: インラインHTMLを使用
            let html = generateHTML(posts: posts)
            webView.loadHTMLString(html, baseURL: nil)
            // フォールバック時も高さを取得
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.updateTimelineData(in: webView)
            }
            return
        }
        
        // HTMLファイルを読み込む
        if let htmlString = try? String(contentsOfFile: htmlPath, encoding: .utf8) {
            // baseURLを設定してCSSファイルを読み込めるようにする
            let baseURL = URL(fileURLWithPath: htmlPath).deletingLastPathComponent()
            webView.loadHTMLString(htmlString, baseURL: baseURL)
            
            // 初期データを設定（少し遅延させて確実にDOMが構築されるようにする）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.updateTimelineData(in: webView)
            }
        }
    }
    
    private func updateTimelineData(in webView: WKWebView) {
        // JavaScriptでデータを更新（新着順にソート）
        let sortedPosts = posts.sorted { $0.createdAt > $1.createdAt }
        let postsData = sortedPosts.enumerated().map { index, post in
            [
                "index": index,
                "id": post.id.uuidString,
                "level": post.level.rawValue,
                "createdAt": ISO8601DateFormatter().string(from: post.createdAt),
                "likeCount": post.likeCount,
                "supportCount": post.supportCount,
                "isSadEmotion": post.isSadEmotion,
                "hasLocation": post.latitude != nil && post.longitude != nil
            ]
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: postsData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            // JSONをJavaScriptに安全に渡す
            let script = """
                (function() {
                    try {
                        var postsData = \(jsonString);
                        if (typeof updateTimeline === 'function') {
                            updateTimeline(postsData);
                        }
                    } catch(e) {
                        console.error('Timeline update error:', e);
                    }
                })();
            """
            webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    print("JavaScript実行エラー: \(error)")
                } else {
                    // データ更新後に少し待ってから高さを再取得（DOMの更新を待つ）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.updateContentHeight(in: webView)
                    }
                }
            }
        }
    }
    
    private func updateContentHeight(in webView: WKWebView) {
        // JavaScriptでコンテンツの実際の高さを取得
        let script = """
            (function() {
                var container = document.getElementById('timeline-container');
                if (container) {
                    // パディングを含めた高さを取得
                    var height = container.scrollHeight;
                    // bodyのパディングも考慮
                    var bodyPadding = parseInt(window.getComputedStyle(document.body).paddingTop) + 
                                     parseInt(window.getComputedStyle(document.body).paddingBottom);
                    return height + bodyPadding;
                }
                return document.body.scrollHeight || 100;
            })();
        """
        
        let oldHeight = contentHeight
        let defaultHeight = UIScreen.main.bounds.height
        
        webView.evaluateJavaScript(script) { result, error in
            if let error = error {
                print("高さ取得エラー: \(error)")
                // エラー時はデフォルト値を設定（大きな変化の時のみ）
                let newHeight = max(CGFloat(self.posts.count) * 100, 500)
                if abs(newHeight - oldHeight) > 50 {
                    DispatchQueue.main.async {
                        self.contentHeight = newHeight
                    }
                }
            } else if let height = result as? CGFloat {
                let newHeight = max(height + 32, 100)
                // 高さが大きく変わった時だけ更新（スクロール位置のリセットを防ぐ）
                // または、初期値の場合（oldHeightがデフォルト値の場合）
                if abs(newHeight - oldHeight) > 30 || oldHeight == defaultHeight {
                    DispatchQueue.main.async {
                        self.contentHeight = newHeight
                    }
                }
            } else if let height = result as? Double {
                let newHeight = max(CGFloat(height) + 32, 100)
                // 高さが大きく変わった時だけ更新
                if abs(newHeight - oldHeight) > 30 || oldHeight == defaultHeight {
                    DispatchQueue.main.async {
                        self.contentHeight = newHeight
                    }
                }
            } else {
                // 結果が取得できない場合のフォールバック
                let newHeight = max(CGFloat(self.posts.count) * 100, 500)
                if abs(newHeight - oldHeight) > 50 {
                    DispatchQueue.main.async {
                        self.contentHeight = newHeight
                    }
                }
            }
        }
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var webView: WKWebView?
        var parent: HTMLTimelineView?
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "postTapped" {
                if let index = message.body as? Int {
                    // 新着順にソートされたリストから取得
                    let sortedPosts = (parent?.posts ?? []).sorted { $0.createdAt > $1.createdAt }
                    if index < sortedPosts.count {
                        let post = sortedPosts[index]
                        parent?.onPostTapped(post)
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // ページ読み込み完了後にスクロールを無効化
            webView.scrollView.isScrollEnabled = false
            webView.scrollView.bounces = false
            webView.scrollView.showsVerticalScrollIndicator = false
            webView.scrollView.showsHorizontalScrollIndicator = false
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            webView.scrollView.contentOffset = .zero
            webView.scrollView.scrollsToTop = false
            webView.scrollView.alwaysBounceVertical = false
            webView.scrollView.alwaysBounceHorizontal = false
            webView.scrollView.isDirectionalLockEnabled = true
            
            // スクロールバーを完全に非表示にする
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // スクロールバーのサブビューを非表示にする
                for subview in webView.scrollView.subviews {
                    if String(describing: type(of: subview)).contains("ScrollIndicator") {
                        subview.isHidden = true
                        subview.alpha = 0
                    }
                    if let scrollBar = subview as? UIImageView {
                        scrollBar.isHidden = true
                        scrollBar.alpha = 0
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.parent = self
        return coordinator
    }
    
    // 以下は使用されなくなりましたが、互換性のために残しています
    private func generateHTML(posts: [EmotionPost]) -> String {
        let sortedPosts = posts.sorted { $0.createdAt > $1.createdAt }
        let postsHTML = sortedPosts.map { post in
            let emoji = getEmoji(for: post.level)
            let levelText = getLevelText(for: post.level)
            let timeAgo = formatDate(post.createdAt)
            let color = getColorHex(for: post.level)
            
            return """
            <div class="post-card">
                <div class="post-emoji">\(emoji)</div>
                <div class="post-content">
                    <div class="post-level">\(levelText)</div>
                    <div class="post-meta">
                        <span class="post-time">\(timeAgo)</span>
                        \(post.supportCount > 0 ? "<span class='post-stat'>\(post.isSadEmotion ? "💪" : "🤗") \(post.supportCount)</span>" : "")
                    </div>
                </div>
                <div class="post-value" style="background-color: \(color);">\(post.level.rawValue)</div>
            </div>
            """
        }.joined(separator: "\n")
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
            <style>
                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                }
                
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    background: transparent;
                    padding: 16px;
                    color: white;
                }
                
                .post-card {
                    display: flex;
                    align-items: center;
                    background: rgba(255, 255, 255, 0.15);
                    backdrop-filter: blur(10px);
                    border-radius: 16px;
                    padding: 16px;
                    margin-bottom: 12px;
                    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
                    transition: transform 0.2s, background 0.2s;
                }
                
                .post-card:active {
                    transform: scale(0.98);
                    background: rgba(255, 255, 255, 0.2);
                }
                
                .post-emoji {
                    font-size: 40px;
                    width: 60px;
                    height: 60px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    background: rgba(255, 255, 255, 0.2);
                    border-radius: 50%;
                    margin-right: 12px;
                    flex-shrink: 0;
                }
                
                .post-content {
                    flex: 1;
                    min-width: 0;
                }
                
                .post-level {
                    font-size: 18px;
                    font-weight: 600;
                    margin-bottom: 6px;
                    color: white;
                }
                
                .post-meta {
                    display: flex;
                    align-items: center;
                    gap: 12px;
                    flex-wrap: wrap;
                }
                
                .post-time {
                    font-size: 14px;
                    color: rgba(255, 255, 255, 0.7);
                }
                
                .post-stat {
                    font-size: 14px;
                    color: rgba(255, 255, 255, 0.8);
                    display: inline-flex;
                    align-items: center;
                    gap: 4px;
                }
                
                .post-value {
                    width: 48px;
                    height: 48px;
                    border-radius: 50%;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    font-size: 20px;
                    font-weight: bold;
                    color: white;
                    flex-shrink: 0;
                    margin-left: 12px;
                    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
                }
                
                @media (max-width: 375px) {
                    .post-emoji {
                        width: 50px;
                        height: 50px;
                        font-size: 32px;
                    }
                    
                    .post-level {
                        font-size: 16px;
                    }
                    
                    .post-value {
                        width: 40px;
                        height: 40px;
                        font-size: 18px;
                    }
                }
            </style>
        </head>
        <body>
            \(postsHTML.isEmpty ? "<div style='text-align: center; padding: 40px; color: rgba(255,255,255,0.6);'>まだ投稿がありません</div>" : postsHTML)
        </body>
        </html>
        """
    }
    
    private func getEmoji(for level: EmotionLevel) -> String {
        switch level {
        case .minusFive, .minusFour: return "😢"
        case .minusThree, .minusTwo: return "😔"
        case .minusOne: return "😐"
        case .zero: return "😊"
        case .plusOne: return "😄"
        case .plusTwo, .plusThree: return "😃"
        case .plusFour, .plusFive: return "🤩"
        }
    }
    
    private func getLevelText(for level: EmotionLevel) -> String {
        switch level {
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func getColorHex(for level: EmotionLevel) -> String {
        let t = Double(level.rawValue + 5) / 10
        let hue = 0.62 - 0.62 * t
        let color = UIColor(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 1.0)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}

import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

final class QRCodeService {
    static let shared = QRCodeService()
    
    private init() {}
    
    // ユーザーIDからQRコードを生成
    func generateQRCode(for userID: String) -> UIImage? {
        // アプリ内のカスタムURLスキームを作成
        let urlString = "emotionapp://user/\(userID)"
        
        guard let data = urlString.data(using: .utf8) else {
            print("❌ QRコード生成エラー: データ変換失敗")
            return nil
        }
        
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel") // 高い誤り訂正レベル
        
        guard let ciImage = filter.outputImage else {
            print("❌ QRコード生成エラー: CIImage生成失敗")
            return nil
        }
        
        // 高解像度にスケールアップ
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = ciImage.transformed(by: transform)
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            print("❌ QRコード生成エラー: CGImage生成失敗")
            return nil
        }
        
        print("✅ QRコード生成成功: \(urlString)")
        return UIImage(cgImage: cgImage)
    }
    
    // プロフィール共有用の画像を生成（QRコード + ユーザー情報）
    func generateShareableProfileImage(
        userName: String,
        level: Int,
        qrCode: UIImage,
        profileImage: UIImage?
    ) -> UIImage? {
        // キャンバスサイズ
        let canvasSize = CGSize(width: 600, height: 800)
        let qrSize: CGFloat = 300
        let profileImageSize: CGFloat = 100
        
        UIGraphicsBeginImageContextWithOptions(canvasSize, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // 背景グラデーション
        let colors = [
            UIColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1.0).cgColor,
            UIColor(red: 0.2, green: 0.1, blue: 0.3, alpha: 1.0).cgColor
        ]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                   colors: colors as CFArray,
                                   locations: [0.0, 1.0])!
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: 0),
                                   end: CGPoint(x: 0, y: canvasSize.height),
                                   options: [])
        
        // プロフィール画像（円形）
        let profileImageY: CGFloat = 80
        let profileImageX = (canvasSize.width - profileImageSize) / 2
        let profileImageRect = CGRect(x: profileImageX, y: profileImageY,
                                      width: profileImageSize, height: profileImageSize)
        
        if let profileImage = profileImage {
            context.saveGState()
            let circlePath = UIBezierPath(ovalIn: profileImageRect)
            circlePath.addClip()
            profileImage.draw(in: profileImageRect)
            context.restoreGState()
        } else {
            // デフォルトのアバター
            context.setFillColor(UIColor.systemGray.cgColor)
            context.fillEllipse(in: profileImageRect)
        }
        
        // ユーザー名
        let nameY = profileImageY + profileImageSize + 20
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 28),
            .foregroundColor: UIColor.white
        ]
        let nameString = NSAttributedString(string: userName, attributes: nameAttributes)
        let nameSize = nameString.size()
        nameString.draw(at: CGPoint(x: (canvasSize.width - nameSize.width) / 2, y: nameY))
        
        // レベル
        let levelY = nameY + nameSize.height + 10
        let levelAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20),
            .foregroundColor: UIColor.systemGray
        ]
        let levelText = "Lv.\(level)"
        let levelString = NSAttributedString(string: levelText, attributes: levelAttributes)
        let levelSize = levelString.size()
        levelString.draw(at: CGPoint(x: (canvasSize.width - levelSize.width) / 2, y: levelY))
        
        // QRコード（白い背景付き）
        let qrY = levelY + levelSize.height + 40
        let qrX = (canvasSize.width - qrSize) / 2
        let qrBackgroundRect = CGRect(x: qrX - 20, y: qrY - 20,
                                      width: qrSize + 40, height: qrSize + 40)
        
        // 白い背景と影
        context.setShadow(offset: CGSize(width: 0, height: 4), blur: 10,
                         color: UIColor.black.withAlphaComponent(0.3).cgColor)
        context.setFillColor(UIColor.white.cgColor)
        let roundedRect = UIBezierPath(roundedRect: qrBackgroundRect, cornerRadius: 20)
        roundedRect.fill()
        
        // QRコード
        context.setShadow(offset: .zero, blur: 0, color: nil)
        let qrRect = CGRect(x: qrX, y: qrY, width: qrSize, height: qrSize)
        qrCode.draw(in: qrRect)
        
        // 説明文
        let descY = qrY + qrSize + 60
        let descAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.white.withAlphaComponent(0.8)
        ]
        let descText = "このQRコードをスキャンして\nエモナルで友達になろう！"
        let descString = NSAttributedString(string: descText, attributes: descAttributes)
        let descSize = descString.size()
        descString.draw(at: CGPoint(x: (canvasSize.width - descSize.width) / 2, y: descY))
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

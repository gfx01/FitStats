import SwiftUI
import UIKit

/// A screenshot picked to send to the coach: scaled down so text stays readable but the upload
/// and Claude's image tokens stay small (long edge 1,568 px, about 1,500 tokens), plus a small
/// preview the server keeps with the message.
struct CoachImageUpload: Identifiable {
    let id = UUID()
    let preview: UIImage
    /// Base64 JPEG for Claude.
    let data: String
    /// Base64 JPEG, long edge 320 px.
    let thumb: String

    static let maxEdge: CGFloat = 1568
    static let thumbEdge: CGFloat = 320

    init?(imageData: Data) {
        guard let image = UIImage(data: imageData),
              let full = image.fitted(maxEdge: Self.maxEdge).jpegData(compressionQuality: 0.8),
              let small = image.fitted(maxEdge: Self.thumbEdge).jpegData(compressionQuality: 0.6) else { return nil }
        preview = UIImage(data: small) ?? image
        data = full.base64EncodedString()
        thumb = small.base64EncodedString()
    }

    var attachment: CoachAttachment { CoachAttachment(mediaType: "image/jpeg", thumb: thumb) }
}

extension UIImage {
    /// At most `maxEdge` pixels on the long side, at scale 1 (screenshots and photos decode at
    /// scale 1, so their size is in pixels).
    func fitted(maxEdge: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxEdge else { return self }
        let scale = maxEdge / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// The previews of a message's screenshots, in a row.
struct AttachmentThumbs: View {
    let attachments: [CoachAttachment]
    var height: CGFloat = 120

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(attachments.enumerated()), id: \.offset) { item in
                if let thumb = item.element.thumb, let data = Data(base64Encoded: thumb), let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: height * min(1, image.size.width / max(image.size.height, 1)) , height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: height * 0.5, height: height)
                        .overlay(Image(systemName: "photo").foregroundStyle(Theme.tertiary))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(attachments.count == 1 ? "A screenshot" : "\(attachments.count) screenshots")
        .accessibilityIdentifier("coach-attachments")
    }
}

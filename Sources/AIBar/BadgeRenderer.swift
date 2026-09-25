import AIBarCore
import AppKit

/// Draws the menu bar badge as an image rather than a button title, because a title cannot carry a
/// coloured rounded background.
@MainActor
enum BadgeRenderer {
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    private static let height: CGFloat = 18
    private static let horizontalPadding: CGFloat = 5
    private static let cornerRadius: CGFloat = 4

    static func image(text: String, tint: BadgeTint) -> NSImage {
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let size = NSSize(width: ceil(textSize.width) + 2 * horizontalPadding, height: height)

        // The handler runs at draw time, so `labelColor` resolves against the menu bar's current
        // light/dark appearance instead of the one active when the image was created.
        let image = NSImage(size: size, flipped: false) { bounds in
            if let fill = tint.backgroundColor {
                fill.setFill()
                NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: tint.textColor]
            let origin = NSPoint(x: (bounds.width - textSize.width) / 2, y: (bounds.height - textSize.height) / 2)
            (text as NSString).draw(at: origin, withAttributes: attributes)
            return true
        }
        // Template images are recoloured monochrome by the menu bar, which would erase the tint.
        image.isTemplate = false
        return image
    }
}

// A coloured pill makes the forecast readable at a glance; neutral stays plain text like other menu bar items.
extension BadgeTint {
    fileprivate var backgroundColor: NSColor? {
        switch self {
        case .neutral: nil
        case .ok: .systemGreen
        case .danger: .systemRed
        }
    }

    fileprivate var textColor: NSColor {
        switch self {
        case .neutral: .labelColor
        case .ok, .danger: .white
        }
    }
}

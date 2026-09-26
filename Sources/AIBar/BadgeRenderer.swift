import AIBarCore
import AppKit

/// Draws the menu bar badge as an image rather than a button title, because a title cannot carry a
/// coloured capsule background. The capsule copies the system camera indicator beside it (see `BadgeSize`).
@MainActor
enum BadgeRenderer {
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    /// The camera pill's glyph sits about 11 pt in from either end of its 24 pt height; the text keeps that inset,
    /// scaled with the badge on a menu bar too short for the full height.
    private static let paddingPerPointOfHeight: CGFloat = 11 / 24

    static func image(text: String, tint: BadgeTint, height: CGFloat) -> NSImage {
        let horizontalPadding = height * paddingPerPointOfHeight
        let cornerRadius = height / 2
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        // Whole points, so the capsule's ends land on pixel boundaries instead of blurring.
        let size = NSSize(width: ceil(textSize.width + 2 * horizontalPadding), height: height)

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

// A coloured capsule makes the forecast readable at a glance; neutral stays plain text like other menu bar items.
extension BadgeTint {
    fileprivate var backgroundColor: NSColor? {
        switch self {
        case .neutral: nil
        case .ok: .systemGreen
        case .danger: .systemRed
        }
    }

    /// Also the colour of the light that runs round the badge during a refresh, so it shows on every tint.
    var textColor: NSColor {
        switch self {
        case .neutral: .labelColor
        case .ok, .danger: .white
        }
    }
}

import AppKit

/// Draws the menu bar badge as an image rather than a button title, so its height can follow the system camera
/// indicator beside it (see `BadgeSize`) and the refresh light has a fixed capsule to run round.
@MainActor
enum BadgeRenderer {
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

    /// As narrow as the text: the button already adds the menu bar's standard spacing on either side.
    static func image(text: String, height: CGFloat) -> NSImage {
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        // Whole points, so the image lands on pixel boundaries instead of blurring.
        let size = NSSize(width: ceil(textSize.width), height: height)
        let image = NSImage(size: size, flipped: false) { bounds in
            let origin = NSPoint(x: (bounds.width - textSize.width) / 2, y: (bounds.height - textSize.height) / 2)
            (text as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: NSColor.black])
            return true
        }
        // The menu bar recolours a template like its own items: white or black to suit the bar, dimmed on an inactive
        // display, inverted while selected.
        image.isTemplate = true
        return image
    }
}

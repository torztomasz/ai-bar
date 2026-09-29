import AIBarCore
import AppKit

/// Draws the menu bar badge as an image rather than a button title, so its height can follow the system camera
/// indicator beside it (see `BadgeSize`) and the refresh light has a fixed capsule to run round.
@MainActor
enum BadgeRenderer {
    /// One provider's reading. `mark` is only drawn when readings are stacked (see `BadgeLayout`).
    struct Row {
        let mark: NSImage?
        let text: String
    }

    /// As narrow as its widest row: the button already adds the menu bar's standard spacing on either side.
    static func image(rows: [Row], height: CGFloat) -> NSImage {
        let layout = BadgeLayout(rowCount: rows.count, height: height)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: layout.fontSize, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        let textSizes = rows.map { ($0.text as NSString).size(withAttributes: attributes) }
        let markColumnWidth = layout.markSize.map { $0 + BadgeLayout.markSpacing } ?? 0
        let textColumnWidth = textSizes.map(\.width).max() ?? 0
        // Whole points, so the image lands on pixel boundaries instead of blurring.
        let size = NSSize(width: ceil(markColumnWidth + textColumnWidth), height: height)
        let image = NSImage(size: size, flipped: false) { bounds in
            for (row, (textSize, midline)) in zip(rows, zip(textSizes, layout.rowMidlines)) {
                // Right-aligned, so the digits of stacked readings line up like a column of figures.
                let origin = NSPoint(x: bounds.maxX - textSize.width, y: midline - textSize.height / 2)
                (row.text as NSString).draw(at: origin, withAttributes: attributes)
                if let markSize = layout.markSize {
                    row.mark?.draw(in: NSRect(x: bounds.minX, y: midline - markSize / 2, width: markSize,
                                              height: markSize))
                }
            }
            return true
        }
        // The menu bar recolours a template like its own items: white or black to suit the bar, dimmed on an inactive
        // display, inverted while selected.
        image.isTemplate = true
        return image
    }
}

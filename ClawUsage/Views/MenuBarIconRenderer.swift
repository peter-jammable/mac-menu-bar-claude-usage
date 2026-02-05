import AppKit
import Foundation

enum MenuBarIconRenderer {
    /// Renders two stacked progress bars for the menu bar.
    /// Top bar: 5-hour session, Bottom bar: 7-day weekly
    /// `fiveHour` and `sevenDay` should be 0.0–1.0.
    static func render(fiveHour: Double, sevenDay: Double) -> NSImage {
        let width: CGFloat = 24
        let height: CGFloat = 22
        let barHeight: CGFloat = 6
        let gap: CGFloat = 4
        let cornerRadius: CGFloat = 2
        let inset: CGFloat = 0.5

        // Two bars stacked vertically, centered
        let totalHeight = barHeight * 2 + gap
        let topBarY = (height + totalHeight) / 2 - barHeight  // top bar
        let bottomBarY = (height - totalHeight) / 2           // bottom bar

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            // Draw top bar (5-hour session)
            drawBar(
                x: 0, y: topBarY,
                width: width, height: barHeight,
                percentage: fiveHour,
                cornerRadius: cornerRadius, inset: inset
            )

            // Draw bottom bar (7-day weekly)
            drawBar(
                x: 0, y: bottomBarY,
                width: width, height: barHeight,
                percentage: sevenDay,
                cornerRadius: cornerRadius, inset: inset
            )

            return true
        }

        image.isTemplate = false
        return image
    }

    private static var borderColor: NSColor {
        // Use label color which automatically adapts to dark/light mode
        // Dark mode: white, Light mode: black
        NSColor.labelColor.withAlphaComponent(0.7)
    }

    private static func drawBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, percentage: Double, cornerRadius: CGFloat, inset: CGFloat) {
        // Background outline
        let bgRect = NSRect(x: x, y: y, width: width, height: height)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)

        borderColor.setStroke()
        bgPath.lineWidth = 1
        bgPath.stroke()

        // Fill
        let clamped = min(max(percentage, 0), 1)
        let fillWidth = max(0, (width - inset * 2) * CGFloat(clamped))

        if fillWidth > 0 {
            let fillRect = NSRect(x: x + inset, y: y + inset, width: fillWidth, height: height - inset * 2)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: max(0, cornerRadius - inset), yRadius: max(0, cornerRadius - inset))

            fillColor(for: percentage).setFill()
            fillPath.fill()
        }
    }

    /// Returns a placeholder icon for unauthenticated state —
    /// half-filled purple bar with an exclamation badge (like broken wifi)
    static func placeholder() -> NSImage {
        let width: CGFloat = 28
        let height: CGFloat = 22
        let barWidth: CGFloat = 22
        let barHeight: CGFloat = 12
        let barY: CGFloat = (height - barHeight) / 2
        let cornerRadius: CGFloat = 3
        let inset: CGFloat = 1

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            // Bar outline
            let bgRect = NSRect(x: 0, y: barY, width: barWidth, height: barHeight)
            let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)

            borderColor.setStroke()
            bgPath.lineWidth = 1.5
            bgPath.stroke()

            // Half-filled purple bar
            let fillWidth = (barWidth - inset * 2) * 0.5
            let fillRect = NSRect(x: inset, y: barY + inset, width: fillWidth, height: barHeight - inset * 2)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: cornerRadius - inset, yRadius: cornerRadius - inset)

            NSColor.systemPurple.withAlphaComponent(0.6).setFill()
            fillPath.fill()

            // Exclamation badge — small circle with "!" centered over bar
            let badgeSize: CGFloat = 10
            let badgeX = (barWidth - badgeSize) / 2
            let badgeY = (height - badgeSize) / 2
            let badgeRect = NSRect(x: badgeX, y: badgeY, width: badgeSize, height: badgeSize)

            // "!" text
            let excl = "!" as NSString
            let font = NSFont.systemFont(ofSize: 7, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ]
            let textSize = excl.size(withAttributes: attrs)
            let textX = badgeX + (badgeSize - textSize.width) / 2
            let textY = badgeY + (badgeSize - textSize.height) / 2
            excl.draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)

            return true
        }
        image.isTemplate = false
        return image
    }

    private static func fillColor(for percentage: Double) -> NSColor {
        if percentage < 0.5 {
            return NSColor.systemGreen
        } else if percentage < 0.8 {
            return NSColor.systemYellow
        } else {
            return NSColor.systemRed
        }
    }
}

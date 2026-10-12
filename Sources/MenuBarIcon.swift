import AppKit

/// The app icon's shield and dot as a menu bar template image, drawn taller than an SF Symbol there so it's
/// easy to spot. While blocking, the shield is filled with the dot cut out; otherwise it's an outline around a solid dot.
@MainActor
enum MenuBarIcon {
    static let active = image(filled: true)
    static let inactive = image(filled: false)

    /// In points. The menu bar is 24 tall, and the SF Symbol shield there is about 15.
    private static let height: CGFloat = 16
    private static let lineWidth: CGFloat = 1.5

    private static func image(filled: Bool) -> NSImage {
        let shield = shieldPath()
        // dot.svg
        let dot = CGPath(ellipseIn: CGRect(x: 512 - 77.7, y: 505.7 - 77.7, width: 155.4, height: 155.4), transform: nil)
        let bounds = shield.boundingBoxOfPath
        let size = CGSize(width: (bounds.width * height / bounds.height).rounded(.up), height: height)
        // Keep the outline's stroke inside the image.
        let inset = filled ? 0 : lineWidth / 2
        let scale = (height - 2 * inset) / bounds.height
        var transform = CGAffineTransform(translationX: size.width / 2, y: inset)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.midX, y: -bounds.minY)
        let scaledShield = shield.copy(using: &transform)!
        let scaledDot = dot.copy(using: &transform)!

        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            if filled {
                context.addPath(scaledShield)
                context.addPath(scaledDot)
                context.fillPath(using: .evenOdd)
            } else {
                context.setLineWidth(lineWidth)
                context.setLineJoin(.round)
                context.addPath(scaledShield)
                context.strokePath()
                context.addPath(scaledDot)
                context.fillPath()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Disciplined"
        return image
    }

    /// shield.svg, in the icon's 1024-point canvas with y pointing down.
    private static func shieldPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 493.1, y: 196.3))
        path.addQuadCurve(to: CGPoint(x: 530.9, y: 196.3), control: CGPoint(x: 512.0, y: 186.8))
        path.addCurve(to: CGPoint(x: 789.2, y: 257.2), control1: CGPoint(x: 610.7, y: 233.1), control2: CGPoint(x: 698.9, y: 250.9))
        path.addQuadCurve(to: CGPoint(x: 814.4, y: 286.6), control: CGPoint(x: 814.4, y: 259.3))
        path.addLine(to: CGPoint(x: 814.4, y: 507.1))
        path.addCurve(to: CGPoint(x: 524.6, y: 859.9), control1: CGPoint(x: 814.4, y: 679.3), control2: CGPoint(x: 698.9, y: 790.6))
        path.addQuadCurve(to: CGPoint(x: 499.4, y: 859.9), control: CGPoint(x: 512.0, y: 865.2))
        path.addCurve(to: CGPoint(x: 209.6, y: 507.1), control1: CGPoint(x: 325.1, y: 790.6), control2: CGPoint(x: 209.6, y: 679.3))
        path.addLine(to: CGPoint(x: 209.6, y: 286.6))
        path.addQuadCurve(to: CGPoint(x: 234.8, y: 257.2), control: CGPoint(x: 209.6, y: 259.3))
        path.addCurve(to: CGPoint(x: 493.1, y: 196.3), control1: CGPoint(x: 325.1, y: 250.9), control2: CGPoint(x: 413.3, y: 233.1))
        path.closeSubpath()
        return path
    }
}

import AppKit

/// 把菜单栏图标画成一张**位图** `NSImage`。
///
/// 两个关键决定：
/// 1. 用 `button.image` 而不是自定义视图。`NSStatusItem` 会持续对按钮里的自定义视图做
///    「replicant」快照（`_updateReplicant:` → `cacheDisplay` → `CALayer.renderInContext:`），
///    实测无论有没有动画都常驻 30% 以上 CPU。
/// 2. 一次性画进位图，而不是用 `NSImage(size:flipped:drawingHandler:)`。
///    后者的绘制闭包会在每次绘制时重新执行，菜单栏刷新时会被反复调用，实测能烧到 90% CPU。
///
/// 图形本身复用矢量路径（`DeepSeekWhale`）和运动参数（`WhaleScene`），
/// 所以和弹窗水族箱里那只鲸鱼长得一模一样，并且在任何缩放比例下都锐利。
enum MenuBarIcon {

    /// 菜单栏画布尺寸。
    static let size = CGSize(width: 46, height: 22)

    /// 位图缩放倍数（菜单栏是 Retina 的）。
    private static let scale: CGFloat = 2

    /// 生成静态图标。结果做了缓存，同一种配色只会画一次。
    ///
    /// - Parameters:
    ///   - period: 高峰（游动 + 气泡）/ 空闲（侧躺 + z）。
    ///   - dark: 菜单栏是否为深色。深色菜单栏用亮色，浅色菜单栏用深色，保证对比度。
    /// - Parameter overrideColor: 仅供调色时预览用，正常调用传 `nil`。
    static func image(period: PricePeriod, dark: Bool, overrideColor: NSColor? = nil) -> NSImage {
        let key = "\(period.rawValue)-\(dark)-\(overrideColor.map { "\($0)" } ?? "auto")"
        if let cached = cache[key] { return cached }

        let image = render(period: period, dark: dark, overrideColor: overrideColor)
        cache[key] = image
        return image
    }

    private static var cache: [String: NSImage] = [:]

    // MARK: - 绘制

    private static func render(period: PricePeriod, dark: Bool, overrideColor: NSColor?) -> NSImage {
        let pixelWidth = Int(size.width * scale)
        let pixelHeight = Int(size.height * scale)

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pixelWidth,
                                         pixelsHigh: pixelHeight,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else {
            return NSImage(size: size)
        }
        // 让这份位图以点为单位对应 46×22。
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            let cgContext = context.cgContext
            // 位图上下文原点在左下角，这里翻转成左上角、y 向下，和绘制代码保持一致。
            cgContext.translateBy(x: 0, y: size.height)
            cgContext.scaleBy(x: 1, y: -1)
            draw(in: cgContext, period: period, dark: dark, overrideColor: overrideColor)
            context.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }

    /// 实际的绘制。坐标系：左上角原点，y 向下，尺寸为 `size`。
    private static func draw(in context: CGContext, period: PricePeriod, dark: Bool,
                             overrideColor: NSColor?) {
        let palette = WhalePalette.menuBar(for: period, dark: dark)
        let whaleColor = overrideColor ?? NSColor(palette.fillColors[palette.fillColors.count / 2])
        let bubbleColor = NSColor(palette.bubble)
        let markColor = NSColor(palette.sleepMark)

        let bodyWidth = WhaleScene.menuBarWhaleWidth(forStageHeight: size.height)
        let bodyHeight = DeepSeekWhale.height(forWidth: bodyWidth)
        let margin = WhaleScene.menuBarMargin
        let travel = max(0, size.width - bodyWidth - margin * 2)
        let bodyRect = CGRect(origin: .zero, size: CGSize(width: bodyWidth, height: bodyHeight))
        let whalePath = DeepSeekWhale.cachedPath(fitting: bodyRect).cgPath

        switch period {
        case .peak:
            // 停在画布中间，轻微抬头，气泡排在尾后。
            let origin = CGPoint(x: margin + travel / 2, y: (size.height - bodyHeight) / 2)
            inWhaleSpace(context, origin: origin, bodySize: bodyRect.size,
                         tiltDegrees: -WhaleScene.tiltDegrees) {
                context.setFillColor(whaleColor.cgColor)
                context.addPath(whalePath)
                context.fillPath()

                let unit = bodyWidth / 20
                let riseDistance = bodyHeight + 7 * unit
                for index in 0..<3 {
                    let radius = (0.75 + Double(index) * 0.4) * unit
                    let center = CGPoint(
                        x: bodyWidth * 0.95 + (2.5 + Double(index) * 4) * unit,
                        y: bodyHeight * 0.72 - (0.35 + Double(index) * 0.28) * riseDistance
                    )
                    context.setFillColor(bubbleColor.withAlphaComponent(0.45 - Double(index) * 0.1).cgColor)
                    context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                                   width: radius * 2, height: radius * 2))
                }
            }

        case .offPeak:
            // 侧躺睡觉，头顶三个「z」。
            let origin = CGPoint(x: (size.width - bodyWidth) / 2 - size.width * 0.04,
                                 y: (size.height - bodyHeight) / 2)
            inWhaleSpace(context, origin: origin, bodySize: bodyRect.size,
                         tiltDegrees: WhaleScene.sleepTiltDegrees) {
                context.setFillColor(whaleColor.cgColor)
                context.addPath(whalePath)
                context.fillPath()

                let baseSize = max(3.5, bodyWidth * 0.15)
                let start = CGPoint(x: bodyWidth * 1.06, y: bodyHeight * 0.30)
                context.setStrokeColor(markColor.cgColor)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                for index in 0..<3 {
                    let markSize = baseSize * (1 + 0.15 * CGFloat(index))
                    let center = CGPoint(x: start.x + bodyWidth * 0.24 * CGFloat(index) / 3,
                                         y: start.y - bodyHeight * 0.60 * CGFloat(index) / 3)
                    context.setLineWidth(markSize * 0.20)
                    context.addPath(WhaleScene.zMarkPath(at: center, size: markSize).cgPath)
                    context.strokePath()
                }
            }
        }
    }

    /// 把坐标系搬到鲸鱼所在的矩形（左上角原点、y 向下），并应用侧倾角度。
    private static func inWhaleSpace(_ context: CGContext,
                                     origin: CGPoint,
                                     bodySize: CGSize,
                                     tiltDegrees: Double,
                                     draw: () -> Void) {
        context.saveGState()
        context.translateBy(x: origin.x + bodySize.width / 2, y: origin.y + bodySize.height / 2)
        context.rotate(by: CGFloat(tiltDegrees * .pi / 180))
        context.translateBy(x: -bodySize.width / 2, y: -bodySize.height / 2)
        draw()
        context.restoreGState()
    }
}

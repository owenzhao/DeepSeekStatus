import CoreGraphics
import SwiftUI

/// DeepSeek 官方鲸鱼标志的矢量数据与几何工具。
///
/// 路径来自 DeepSeek 官方标志（Simple Icons 收录的 24×24 版本，CC0）。
/// 内嵌矢量路径而不是位图，意味着菜单栏图标在任何缩放比例下都保持锐利，
/// 并且可以直接用 SwiftUI 上色、旋转、镜像来做动画。
enum DeepSeekWhale {

    /// 官方标志的 24×24 viewBox 路径数据。
    static let svgPathData = """
    M23.748 4.651c-.254-.124-.364.113-.512.233-.051.04-.094.09-.137.137-.372.397-.806.657-1.373.626-.829-.046-1.537.214-2.163.848-.133-.782-.575-1.248-1.247-1.548-.352-.155-.708-.311-.955-.65-.172-.24-.219-.509-.305-.774-.055-.16-.11-.323-.293-.35-.2-.031-.278.136-.356.276-.313.572-.434 1.202-.422 1.84.027 1.436.633 2.58 1.838 3.393.137.094.172.187.129.323-.082.28-.18.553-.266.833-.055.179-.137.218-.328.14a5.5 5.5 0 0 1-1.737-1.179c-.857-.828-1.631-1.743-2.597-2.46a12 12 0 0 0-.689-.47c-.985-.957.13-1.743.387-1.836.27-.098.094-.433-.778-.428-.872.003-1.67.295-2.687.685a3 3 0 0 1-.465.136 9.6 9.6 0 0 0-2.883-.101c-1.885.21-3.39 1.1-4.497 2.622C.082 8.776-.231 10.854.152 13.02c.403 2.284 1.568 4.175 3.36 5.653 1.857 1.533 3.997 2.284 6.438 2.14 1.482-.085 3.132-.284 4.994-1.86.47.234.962.328 1.78.398.629.058 1.235-.031 1.705-.129.735-.155.684-.836.418-.961-2.155-1.004-1.682-.595-2.112-.926 1.095-1.295 2.768-3.598 3.284-6.733.05-.346.115-.834.108-1.114-.004-.171.035-.238.23-.257a4.2 4.2 0 0 0 1.545-.475c1.397-.763 1.96-2.016 2.093-3.517.02-.23-.004-.467-.247-.588M11.58 18.168c-2.088-1.642-3.101-2.183-3.52-2.16-.39.024-.32.472-.234.763.09.288.207.487.371.74.114.167.192.416-.113.603-.673.416-1.842-.14-1.897-.168-1.361-.801-2.5-1.86-3.301-3.306-.775-1.393-1.225-2.888-1.299-4.482-.02-.385.094-.522.477-.592a4.7 4.7 0 0 1 1.53-.038c2.131.311 3.946 1.264 5.467 2.774.868.86 1.525 1.887 2.202 2.89.72 1.066 1.494 2.082 2.48 2.915.348.291.626.513.892.677-.802.09-2.14.109-3.055-.615zm1.001-6.44a.306.306 0 0 1 .415-.287.3.3 0 0 1 .113.074.3.3 0 0 1 .086.214c0 .17-.136.307-.308.307a.303.303 0 0 1-.306-.307m3.11 1.596c-.2.081-.4.151-.591.16a1.25 1.25 0 0 1-.798-.254c-.274-.23-.47-.358-.551-.758a1.7 1.7 0 0 1 .015-.588c.07-.327-.007-.537-.238-.727-.188-.156-.426-.199-.689-.199a.6.6 0 0 1-.254-.078.253.253 0 0 1-.114-.358 1 1 0 0 1 .192-.21c.356-.202.767-.136 1.146.016.352.144.618.408 1.001.782.392.451.462.576.685.915.176.264.336.536.446.848.066.194-.02.353-.25.45
    """

    /// 解析后的原始路径（24×24 坐标系），只在首次访问时解析一次。
    static let unitPath: Path = SVGPathParser.path(from: svgPathData)

    /// 路径的真实包围盒：官方图标在 24×24 视窗里并非满幅，按包围盒对齐视觉更统一。
    static let boundingBox: CGRect = unitPath.cgPath.boundingBoxOfPath

    /// 宽高比（宽 / 高）。
    static var aspectRatio: CGFloat {
        guard boundingBox.height > 0 else { return 1 }
        return boundingBox.width / boundingBox.height
    }

    /// 按给定宽度换算出等比高度。
    static func height(forWidth width: CGFloat) -> CGFloat {
        guard boundingBox.width > 0 else { return width }
        return width * boundingBox.height / boundingBox.width
    }

    /// 把鲸鱼等比缩放到目标矩形内（居中，保持比例）。
    static func path(fitting rect: CGRect) -> Path {
        guard boundingBox.width > 0, boundingBox.height > 0 else { return unitPath }
        let scale = min(rect.width / boundingBox.width, rect.height / boundingBox.height)
        guard scale.isFinite, scale > 0 else { return unitPath }
        let dx = rect.midX - boundingBox.midX * scale
        let dy = rect.midY - boundingBox.midY * scale
        let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: dx, ty: dy)
        return unitPath.applying(transform)
    }

    // MARK: - 缓存

    /// 缩放后的路径缓存。
    ///
    /// 鲸鱼路径有 150 多段贝塞尔曲线，而动画每帧都要重新取一次路径。
    /// 每帧重新做一次变换纯属浪费，把结果按尺寸缓存下来可以明显降低 CPU 占用。
    /// 只在主线程（`Canvas` 绘制）访问。
    private static var scaledPathCache: [ScaledPathKey: Path] = [:]

    /// 与 `path(fitting:)` 等价，但会缓存结果。
    static func cachedPath(fitting rect: CGRect) -> Path {
        let key = ScaledPathKey(rect)
        if let cached = scaledPathCache[key] { return cached }
        let path = path(fitting: rect)
        if scaledPathCache.count >= 32 { scaledPathCache.removeAll(keepingCapacity: true) }
        scaledPathCache[key] = path
        return path
    }

    private struct ScaledPathKey: Hashable {
        let x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat

        init(_ rect: CGRect) {
            // 量化到 0.01pt，避免浮点误差导致缓存失效。
            x = (rect.origin.x * 100).rounded() / 100
            y = (rect.origin.y * 100).rounded() / 100
            width = (rect.width * 100).rounded() / 100
            height = (rect.height * 100).rounded() / 100
        }
    }
}

/// 直接可用的鲸鱼形状，会自动填满给定的矩形。
struct WhaleShape: Shape {
    func path(in rect: CGRect) -> Path {
        DeepSeekWhale.path(fitting: rect)
    }
}

#Preview("DeepSeek 鲸鱼") {
    VStack(spacing: 24) {
        WhaleShape()
            .fill(Color(red: 0.302, green: 0.420, blue: 0.996))
            .frame(width: 180, height: 140)
        WhaleShape()
            .stroke(Color.primary, lineWidth: 1)
            .frame(width: 48, height: 40)
    }
    .padding(40)
}

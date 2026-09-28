import AppKit
import SwiftUI

/// 菜单栏面板的窗口。
///
/// 这里刻意**不用** `NSPopover`：`NSPopover` 的位置完全由 AppKit 自己决定，
/// 一旦可用空间判断出问题（多屏、缩放、菜单栏异常），它会自己改弹出方向，
/// 结果就是窗口上半部分跑到屏幕外，用户只能看到下半截内容。
///
/// 换成自己定位的 `NSPanel` 之后：
/// - 位置由 `AppDelegate.panelOrigin(for:button:screen:)` 明确算出来，并夹在屏幕可见区域内；
/// - 高度超过可用空间时退化成可滚动，永远不会「藏内容」；
/// - 面板用 `.nonactivatingPanel`，点菜单栏图标不会再抢走其它应用的焦点。
final class StatusPanel: NSPanel {

    /// 和 SwiftUI 里的圆角保持一致。
    static let cornerRadius: CGFloat = 12

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 320),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        // 浮在普通窗口之上，但不至于盖住系统弹窗/菜单。
        level = .statusBar
        // 圆角由 SwiftUI 负责裁切，窗口本身必须透明，否则四角会是黑的。
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = false
        isMovableByWindowBackground = false
        // 面板是复用的，收起时只 orderOut，不能被释放掉。
        isReleasedWhenClosed = false
        // 关闭交给外面的事件监听处理（见 AppDelegate.installPanelDismissMonitors）。
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    // borderless 窗口默认不能成为 key；放开后按钮和开关才有正常的点击反馈。
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 面板的可见性状态。
///
/// 单独做成一个可观察对象而不是一个 `Bool` 参数：收起面板走的是 `orderOut`，
/// 视图树并不会重建，只有可观察属性变化才能在那一刻把动画摘掉。
/// 详见 `AquariumView.isVisible`。
@MainActor
final class PanelVisibility: ObservableObject {
    @Published var isVisible = false
}

/// 面板里承载的 SwiftUI 内容。
///
/// `maxHeight` 为 nil 时按内容的自然高度显示；屏幕放不下时传入可用高度，
/// 内容会退化成可滚动，而不是被裁掉。
struct StatusPanelContent: View {
    @ObservedObject var store: PricingStore
    var onQuit: () -> Void
    @ObservedObject var balance: BalanceStore
    var maxHeight: CGFloat?
    /// 面板当前是否真的显示在屏幕上。
    ///
    /// 收起面板用的是 `orderOut`，窗口和整棵 SwiftUI 视图树都还在；`TimelineView` 一旦跑起来，
    /// 窗口离屏并不会让它停下来 —— 实测收起后水族箱仍在 30fps 重绘，CPU 11% 左右，
    /// 比面板打开时还显眼。所以这里必须显式把可见性传进视图，由它决定是否挂上动画。
    @ObservedObject var visibility: PanelVisibility
    /// 固定水族箱的绘制时刻（离屏快照用；`nil` 表示播放动画）。
    var fixedAquariumTime: TimeInterval?
    /// 自动检查更新开关与手动检查回调。界面层只用 `Binding`，不直接依赖 Sparkle。
    var automaticallyChecksForUpdates: Binding<Bool> = .constant(false)
    var onCheckForUpdates: () -> Void = {}

    private var content: some View {
        PopoverView(store: store,
                    onQuit: onQuit,
                    balance: balance,
                    isVisible: visibility.isVisible,
                    fixedAquariumTime: fixedAquariumTime,
                    automaticallyChecksForUpdates: automaticallyChecksForUpdates,
                    onCheckForUpdates: onCheckForUpdates)
    }

    var body: some View {
        Group {
            if let maxHeight {
                ScrollView(.vertical, showsIndicators: true) {
                    content
                }
                .frame(width: PopoverView.width, height: maxHeight)
            } else {
                content
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: StatusPanel.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StatusPanel.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}

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

/// 面板里承载的 SwiftUI 内容。
///
/// `maxHeight` 为 nil 时按内容的自然高度显示；屏幕放不下时传入可用高度，
/// 内容会退化成可滚动，而不是被裁掉。
struct StatusPanelContent: View {
    @ObservedObject var store: PricingStore
    var onQuit: () -> Void
    @ObservedObject var balance: BalanceStore
    var maxHeight: CGFloat?
    /// 自动检查更新开关与手动检查回调。界面层只用 `Binding`，不直接依赖 Sparkle。
    var automaticallyChecksForUpdates: Binding<Bool> = .constant(false)
    var onCheckForUpdates: () -> Void = {}

    private var content: some View {
        PopoverView(store: store,
                    onQuit: onQuit,
                    balance: balance,
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

import Foundation
import Sparkle

/// Sparkle 自动更新的薄封装。
///
/// 应用是「只有菜单栏图标」的 agent（`LSUIElement`），没有 MainMenu.xib，
/// 所以按 Sparkle 文档的 programmatic setup 自己建 `SPUStandardUpdaterController`。
/// `SUFeedURL` / `SUPublicEDKey` / `SUEnableAutomaticChecks` 见 `Config/Info.plist`。
///
/// 注意：界面层刻意只暴露 `Binding<Bool>` 和回调（见 `PopoverView`），
/// 不直接依赖 Sparkle —— 离屏渲染工具用 `swiftc` 编译时不会链接 Sparkle。
@MainActor
final class Updater {

    /// 是否在后台自动检查更新。默认值来自 Info.plist 的 `SUEnableAutomaticChecks`。
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// 更新器是否可用（Info.plist 没配好或启动失败时为 false）。
    /// 检查进行中也会变成 false，正好可以用来禁用菜单项。
    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }

    /// 手动检查更新（右键菜单里那一项）。
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

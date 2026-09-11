import Foundation
import ServiceManagement

/// 开机自动启动（登录项）的封装。
enum LaunchAtLogin {

    /// 当前是否已注册为登录项。
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 已注册但等待用户在系统设置中批准。
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// 注册或取消注册登录项。
    static func set(enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status != .notRegistered else { return }
            try SMAppService.mainApp.unregister()
        }
    }
}

import AppKit

/// 给这个「只有菜单栏图标」的 App 装一个看不见的主菜单。
///
/// 为什么必须有它：macOS 上的 **⌘C / ⌘V / ⌘X / ⌘A / ⌘Z 并不是文本控件的快捷键**，
/// 而是主菜单 Edit 菜单项的 key equivalent —— 按下后由菜单把 `copy:` / `paste:` 等
/// action 沿响应链发给第一响应者。`NSTextView` 只实现了这些 action，自己**不**处理 ⌘V
/// （实测 `performKeyEquivalent(⌘V)` 返回 false，`interpretKeyEvents` 也无反应）。
///
/// 本工程是手写 `NSApplication` 生命周期、没有 MainMenu.xib，`NSApp.mainMenu` 一直是 nil，
/// 于是 ⌘V 匹配不到任何 key equivalent，输入框里就只能靠右键菜单粘贴。
/// 这里补上（隐形的）Edit 菜单，快捷键即恢复。
///
/// `LSUIElement` 的 agent 应用不会显示菜单栏，所以装上去也看不见，只是让快捷键重新生效。
enum MainMenu {

    static func install() {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(editMenuItem())
        NSApp.mainMenu = mainMenu
    }

    /// 第一项约定是 App 菜单。agent 应用看不到它，但 ⌘Q 这类约定仍然生效。
    private static func appMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu()
        let quit = menu.addItem(withTitle: String(localized: "menu.quit",
                                                 defaultValue: "Quit DeepSeek Status"),
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q")
        // 明确指定 target：没有窗口时也能用 ⌘Q 退出。
        quit.target = NSApp
        item.submenu = menu
        return item
    }

    /// 标准的 Edit 菜单。action 的 target 留空 = 沿响应链找第一响应者（正在编辑的输入框）。
    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "menu.edit", defaultValue: "Edit"))

        // Undo / Redo 的 action 由 `NSUndoManager` 经窗口的响应链处理，只能用字符串选择器。
        menu.addItem(withTitle: String(localized: "menu.edit.undo", defaultValue: "Undo"),
                     action: NSSelectorFromString("undo:"), keyEquivalent: "z")

        let redo = menu.addItem(withTitle: String(localized: "menu.edit.redo", defaultValue: "Redo"),
                                action: NSSelectorFromString("redo:"), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(.separator())

        menu.addItem(withTitle: String(localized: "menu.edit.cut", defaultValue: "Cut"),
                     action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: String(localized: "menu.edit.copy", defaultValue: "Copy"),
                     action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: String(localized: "menu.edit.paste", defaultValue: "Paste"),
                     action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: String(localized: "menu.edit.selectAll", defaultValue: "Select All"),
                     action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        item.submenu = menu
        return item
    }
}

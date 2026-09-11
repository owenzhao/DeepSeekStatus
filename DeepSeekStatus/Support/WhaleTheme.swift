import SwiftUI

/// 应用配色。鲸鱼使用 DeepSeek 品牌蓝，空闲（睡觉）时切换到安静的灰蓝色。
enum WhaleTheme {
    /// DeepSeek 品牌蓝 #4D6BFE。
    static let brandBlue = Color(red: 77 / 255, green: 107 / 255, blue: 254 / 255)
    static let brandBlueBright = Color(red: 122 / 255, green: 158 / 255, blue: 1.0)
    static let brandBlueDeep = Color(red: 46 / 255, green: 76 / 255, blue: 214 / 255)

    /// 空闲 / 睡眠用的柔和灰蓝。
    static let sleepBlue = Color(red: 130 / 255, green: 145 / 255, blue: 185 / 255)
    static let sleepBlueLight = Color(red: 176 / 255, green: 189 / 255, blue: 219 / 255)
    static let sleepBlueDeep = Color(red: 96 / 255, green: 108 / 255, blue: 145 / 255)

    /// 高峰（贵）用暖色提示，空闲（便宜）用绿色提示。
    static let peakAccent = Color(red: 1.0, green: 138 / 255, blue: 61 / 255)
    static let offPeakAccent = Color(red: 48 / 255, green: 196 / 255, blue: 141 / 255)

    /// 水族箱背景。
    static let tankTop = Color(red: 18 / 255, green: 30 / 255, blue: 74 / 255)
    static let tankBottom = Color(red: 8 / 255, green: 14 / 255, blue: 38 / 255)
    static let tankTopSleep = Color(red: 20 / 255, green: 26 / 255, blue: 48 / 255)
    static let tankBottomSleep = Color(red: 9 / 255, green: 12 / 255, blue: 24 / 255)

    static func accent(for period: PricePeriod) -> Color {
        period == .peak ? peakAccent : offPeakAccent
    }
}

/// 鲸鱼在不同场景下的配色。
struct WhalePalette {
    /// 鲸鱼身体的渐变颜色。
    var body: [Color]
    /// 气泡颜色。
    var bubble: Color
    /// 睡觉时飘出的「z」颜色。
    var sleepMark: Color
    /// 是否使用纯色填充。菜单栏里的鲸鱼只有 20pt 宽，渐变看不出来，
    /// 但每帧的渐变着色明显更贵，所以菜单栏用纯色。
    var isFlat: Bool = false

    /// 实际用于填充的颜色。
    var fillColors: [Color] {
        isFlat ? [body[body.count / 2]] : body
    }

    /// 菜单栏配色。
    ///
    /// 菜单栏是半透明的，底色取决于壁纸，深浅两种模式下同一个图标基本不可兼得，
    /// 所以这里按菜单栏实际的明暗两套颜色：
    /// 深色菜单栏（图标是白色的那种）用亮色，浅色菜单栏用深色，保证对比度。
    static func menuBar(for period: PricePeriod, dark: Bool) -> WhalePalette {
        switch period {
        case .peak:
            return dark
                // 深色菜单栏：用很亮的天空蓝 #A8D4FF。
                // 半透明菜单栏的底色往往就是灰蓝色，中等饱和度的蓝会直接「融」进背景，
                // 必须靠明度拉开差距（候选色对比见 Preview/menubar-color-candidates.png）。
                ? WhalePalette(body: [Color(red: 0.79, green: 0.89, blue: 1.0),
                                      Color(red: 0.66, green: 0.83, blue: 1.0),
                                      Color(red: 0.53, green: 0.75, blue: 1.0)],
                               bubble: Color(red: 0.66, green: 0.83, blue: 1.0),
                               sleepMark: Color(red: 0.66, green: 0.83, blue: 1.0),
                               isFlat: true)
                // 浅色菜单栏：品牌蓝本身就够醒目。
                : WhalePalette(body: [WhaleTheme.brandBlueBright, WhaleTheme.brandBlue, WhaleTheme.brandBlueDeep],
                               bubble: WhaleTheme.brandBlue,
                               sleepMark: WhaleTheme.brandBlue,
                               isFlat: true)
        case .offPeak:
            return dark
                // 深色菜单栏：接近白色的淡蓝紫，和系统图标一样亮，一眼就能看到。
                ? WhalePalette(body: [Color(red: 0.90, green: 0.93, blue: 1.0),
                                      Color(red: 0.80, green: 0.85, blue: 0.97),
                                      Color(red: 0.70, green: 0.77, blue: 0.93)],
                               bubble: Color(red: 0.80, green: 0.85, blue: 0.97),
                               sleepMark: Color(red: 0.90, green: 0.93, blue: 1.0),
                               isFlat: true)
                // 浅色菜单栏：深灰蓝。
                : WhalePalette(body: [Color(red: 0.48, green: 0.53, blue: 0.66),
                                      Color(red: 0.37, green: 0.42, blue: 0.56),
                                      Color(red: 0.28, green: 0.33, blue: 0.46)],
                               bubble: Color(red: 0.37, green: 0.42, blue: 0.56),
                               sleepMark: Color(red: 0.37, green: 0.42, blue: 0.56),
                               isFlat: true)
        }
    }

    /// 弹窗水族箱：背景是深蓝，使用更亮的颜色。
    static func aquarium(for period: PricePeriod) -> WhalePalette {
        switch period {
        case .peak:
            return WhalePalette(body: [Color(red: 0.62, green: 0.75, blue: 1.0), WhaleTheme.brandBlue, WhaleTheme.brandBlueDeep],
                                bubble: Color.white.opacity(0.65),
                                sleepMark: WhaleTheme.brandBlueBright)
        case .offPeak:
            return WhalePalette(body: [WhaleTheme.sleepBlueLight, WhaleTheme.sleepBlue, WhaleTheme.sleepBlueDeep],
                                bubble: Color.white.opacity(0.35),
                                sleepMark: WhaleTheme.sleepBlueLight)
        }
    }
}

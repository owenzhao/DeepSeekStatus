import Foundation

/// DeepSeek 的分时计价时段。
///
/// 规则（来自官方说明）：
/// 空闲时段价格为高峰时段价格的一半。
/// 高峰时段为**北京时间**周一至周五 9:00 - 12:00、14:00 - 18:00，其余为空闲时段。
enum PricePeriod: String, CaseIterable, Identifiable, Sendable {
    /// 高峰时段：价格全额。
    case peak
    /// 空闲时段：价格为高峰时段的一半。
    case offPeak

    var id: String { rawValue }

    /// 显示名称，例如 "Peak hours" / 「高峰时段」。
    var title: String {
        switch self {
        case .peak: return String(localized: "period.peak.title", defaultValue: "Peak hours")
        case .offPeak: return String(localized: "period.offPeak.title", defaultValue: "Off-peak hours")
        }
    }

    /// 简短名称，用于空间较小的位置。
    var shortTitle: String {
        switch self {
        case .peak: return String(localized: "period.peak.shortTitle", defaultValue: "Peak")
        case .offPeak: return String(localized: "period.offPeak.shortTitle", defaultValue: "Off-peak")
        }
    }

    /// 相对高峰价格的倍数：高峰 1.0，空闲 0.5。
    var priceMultiplier: Double {
        switch self {
        case .peak: return 1.0
        case .offPeak: return 0.5
        }
    }

    /// 价格文案。
    var priceText: String {
        switch self {
        case .peak: return String(localized: "period.peak.priceText", defaultValue: "Full price (100%)")
        case .offPeak: return String(localized: "period.offPeak.priceText", defaultValue: "Half the peak price (50%)")
        }
    }

    /// 对应时段的说明。
    var summary: String {
        switch self {
        case .peak: return String(localized: "period.peak.summary", defaultValue: "Peak hours now — billed at the full rate.")
        case .offPeak: return String(localized: "period.offPeak.summary", defaultValue: "Off-peak hours now — priced at half the peak rate.")
        }
    }

    var opposite: PricePeriod {
        self == .peak ? .offPeak : .peak
    }
}

/// 计算某个时刻所处的时段，以及与之相关的时间信息。
enum DeepSeekPricing {
    /// 计费规则使用的时区：北京时间（UTC+8，无夏令时）。
    static let timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 3600)!

    /// 高峰时段所在的小时区间（左闭右开，北京时间）。
    static let peakHourRanges: [Range<Int>] = [9..<12, 14..<18]

    /// 高峰时段所在的分钟区间（左闭右开）。
    static let peakMinuteRanges: [Range<Int>] = peakHourRanges.map { ($0.lowerBound * 60)..<($0.upperBound * 60) }

    /// 固定使用北京时间的日历。
    ///
    /// `locale` 用 `en_US_POSIX` 只是为了得到一个与用户语言无关的确定性日历
    /// （星期/数字等的展示交给 `PricingFormatter`，它才会跟随界面语言）。
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2 // 周一
        return calendar
    }()

    /// 判断某一时刻是否处于高峰时段。
    static func period(at date: Date) -> PricePeriod {
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = components.weekday,
              let hour = components.hour,
              let minute = components.minute else {
            return .offPeak
        }
        // Calendar 中 1 = 周日，2 = 周一，…，7 = 周六。
        guard (2...6).contains(weekday) else { return .offPeak }
        let minutes = hour * 60 + minute
        return peakMinuteRanges.contains { $0.contains(minutes) } ? .peak : .offPeak
    }

    /// 某个时刻所在自然日内的所有高峰时段边界（北京时间）。
    private static func boundaries(onDayStartingAt startOfDay: Date) -> [Date] {
        peakMinuteRanges.flatMap { range -> [Date] in
            let start = calendar.date(byAdding: .minute, value: range.lowerBound, to: startOfDay)
            let end = calendar.date(byAdding: .minute, value: range.upperBound, to: startOfDay)
            return [start, end].compactMap { $0 }
        }
    }

    /// 往后若干天内的全部时段切换时刻，按时间升序排列（含今天）。
    private static func upcomingBoundaries(from date: Date, days: Int = 8) -> [Date] {
        guard let today = calendar.dateInterval(of: .day, for: date)?.start else { return [] }
        return (0..<days)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .flatMap { boundaries(onDayStartingAt: $0) }
            .sorted()
    }

    /// 下一次时段切换的时刻；若当前处于高峰时段，则返回本次高峰结束的时刻。
    static func nextTransition(after date: Date) -> Date {
        let current = period(at: date)
        let candidates = upcomingBoundaries(from: date)
        let next = candidates.first { $0 > date && period(at: $0) != current }
        // 兜底：理论上 8 天内一定会出现切换（周末之后的周一 9:00），这里再保险一点。
        return next ?? calendar.date(byAdding: .day, value: 7, to: date) ?? date
    }

    /// 当前这一段「时段区间」的起点：最近一次时段边界。
    static func currentIntervalStart(before date: Date) -> Date {
        let candidates = upcomingBoundaries(from: date)
        let past = candidates.filter { $0 <= date }
        if let last = past.last { return last }
        // 极端兜底：往回找一天。
        let yesterday = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        return boundaries(onDayStartingAt: calendar.startOfDay(for: yesterday)).last ?? calendar.startOfDay(for: date)
    }
}

/// 某一时刻的完整时段快照，供界面直接展示。
struct PricingSnapshot: Equatable {
    let now: Date
    let period: PricePeriod
    /// 当前时段区间的起点。
    let intervalStart: Date
    /// 下一次时段切换的时刻。
    let nextTransition: Date
    /// 切换之后会进入的时段。
    let nextPeriod: PricePeriod

    /// 距离下一次切换还有多少秒。
    var secondsUntilTransition: TimeInterval {
        max(0, nextTransition.timeIntervalSince(now))
    }

    /// 当前时段区间已经过去的比例（0...1）。
    var intervalProgress: Double {
        let total = nextTransition.timeIntervalSince(intervalStart)
        guard total > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(intervalStart)
        return min(max(elapsed / total, 0), 1)
    }

    init(now: Date) {
        self.now = now
        let period = DeepSeekPricing.period(at: now)
        self.period = period
        self.intervalStart = DeepSeekPricing.currentIntervalStart(before: now)
        let transition = DeepSeekPricing.nextTransition(after: now)
        self.nextTransition = transition
        self.nextPeriod = DeepSeekPricing.period(at: transition.addingTimeInterval(1))
    }
}

// MARK: - 文案格式化

enum PricingFormatter {

    /// 界面语言对应的 Locale。
    ///
    /// 跟随 App 实际选中的本地化（而不是 `Locale.current`），这样单独给 App 指定语言时，
    /// 日期、星期的写法也会跟着界面语言走。
    static var displayLocale: Locale {
        guard let identifier = Bundle.main.preferredLocalizations.first else {
            return Locale.current
        }
        return Locale(identifier: identifier)
    }

    /// 以北京时间渲染、格式固定的文本。
    private static func string(from date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.calendar = DeepSeekPricing.calendar
        formatter.timeZone = DeepSeekPricing.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// 以北京时间渲染、但日期顺序跟随界面语言的文本（例如 "Sep 14" / 「9月14日」）。
    private static func string(from date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.calendar = DeepSeekPricing.calendar
        formatter.timeZone = DeepSeekPricing.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    /// 北京时间「HH:mm」。
    ///
    /// 刻意固定为 24 小时制：界面里所有时段（09:00、14:00 …）都按 24 小时表达，
    /// 不受系统「使用 24 小时制」开关影响。
    static func time(_ date: Date) -> String {
        string(from: date, format: "HH:mm")
    }

    /// 北京时间「HH:mm:ss」。
    static func preciseTime(_ date: Date) -> String {
        string(from: date, format: "HH:mm:ss")
    }

    /// 北京时间的日期，例如 "Monday, September 14" / 「9月14日星期一」。
    static func day(_ date: Date) -> String {
        string(from: date, template: "EEEEMMMMd")
    }

    /// 把切换时刻描述成「today 14:00」「tomorrow 09:00」「Mon 09:00」。
    static func transitionDescription(_ date: Date, relativeTo now: Date) -> String {
        let calendar = DeepSeekPricing.calendar
        let dayDelta = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        let timeText = time(date)
        switch dayDelta {
        case ..<0:
            return timeText
        case 0:
            return String(format: String(localized: "transition.today", defaultValue: "today %@"), timeText)
        case 1:
            return String(format: String(localized: "transition.tomorrow", defaultValue: "tomorrow %@"), timeText)
        case 2:
            return String(format: String(localized: "transition.dayAfterTomorrow",
                                        defaultValue: "the day after tomorrow at %@"), timeText)
        default:
            if dayDelta < 7 {
                return String(format: String(localized: "transition.weekday", defaultValue: "%1$@ %2$@"),
                              weekdayName(of: date), timeText)
            }
            return string(from: date, template: "MMMdHHmm")
        }
    }

    /// 界面语言下的星期简称，例如 "Mon" / 「周一」。
    static func weekdayName(of date: Date) -> String {
        string(from: date, template: "EEE")
    }

    /// 周一到周日的星期简称，供一周时段表当作行标题（顺序固定为周一 → 周日）。
    static let weekdaySymbolsMondayFirst: [String] = {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.calendar = DeepSeekPricing.calendar
        formatter.timeZone = DeepSeekPricing.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        let symbols = formatter.shortWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        // `shortWeekdaySymbols` 的第 0 项是周日，这里重排成周一开头。
        return (1...7).map { symbols[$0 % 7] }
    }()

    /// 把秒数格式化成「1 hour 23 min」「23 min 05 sec」这类可读文案。
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60

        if days > 0 {
            return hours > 0 ? "\(dayUnit(days)) \(hourUnit(hours))" : dayUnit(days)
        }
        if hours > 0 {
            return minutes > 0 ? "\(hourUnit(hours)) \(minuteUnit(minutes))" : hourUnit(hours)
        }
        if minutes > 0 {
            return "\(minuteUnit(minutes)) \(secondUnit(secs))"
        }
        return secondUnit(secs)
    }

    /// 英文有单复数变化、中文没有，所以单数单独给一条文案（里面直接写死 "1"）。
    private static func counted(_ value: Int, one: String, other: String) -> String {
        value == 1 ? one : String(format: other, value)
    }

    private static func dayUnit(_ value: Int) -> String {
        counted(value,
                one: String(localized: "duration.day.one", defaultValue: "1 day"),
                other: String(localized: "duration.day.other", defaultValue: "%lld days"))
    }

    private static func hourUnit(_ value: Int) -> String {
        counted(value,
                one: String(localized: "duration.hour.one", defaultValue: "1 hour"),
                other: String(localized: "duration.hour.other", defaultValue: "%lld hours"))
    }

    private static func minuteUnit(_ value: Int) -> String {
        counted(value,
                one: String(localized: "duration.minute.one", defaultValue: "1 min"),
                other: String(localized: "duration.minute.other", defaultValue: "%lld min"))
    }

    private static func secondUnit(_ value: Int) -> String {
        counted(value,
                one: String(localized: "duration.second.one", defaultValue: "1 sec"),
                other: String(localized: "duration.second.other", defaultValue: "%lld sec"))
    }

    /// 菜单栏倒计时文案，固定为 `HH:MM:SS`（最长的一段空闲时段也只有 63 小时），
    /// 配合等宽数字，菜单栏宽度不会因数字跳动而来回抖动。
    static func compactCountdown(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let hours = min(total / 3_600, 99)
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}

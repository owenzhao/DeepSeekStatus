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

/// 北京时间某个自然日采用的计费规则及其原因。
struct PricingDayInfo: Equatable {
    enum Kind: Equatable {
        case publicHoliday(String)
        case alternateWorkdayWeekend(String)
        case weekend
        case regularWeekday
    }

    let kind: Kind
    let scheduleIsCovered: Bool

    var isAllDayOffPeak: Bool {
        switch kind {
        case .regularWeekday: false
        case .publicHoliday, .alternateWorkdayWeekend, .weekend: true
        }
    }

    var localizedDetail: String {
        switch kind {
        case .publicHoliday(let name):
            return String(format: String(localized: "calendar.detail.holiday",
                                         defaultValue: "%@ holiday · Off-peak all day"),
                          HolidaySchedule.localizedHolidayName(name))
        case .alternateWorkdayWeekend(let name):
            return String(format: String(localized: "calendar.detail.alternateWorkday",
                                         defaultValue: "%@ make-up workday, but it is a weekend · Off-peak all day"),
                          HolidaySchedule.localizedHolidayName(name))
        case .weekend:
            return String(localized: "calendar.detail.weekend",
                          defaultValue: "Weekend · Off-peak all day")
        case .regularWeekday:
            return String(localized: "calendar.detail.weekday",
                          defaultValue: "Regular weekday · Peak 09:00–12:00 and 14:00–18:00")
        }
    }
}

extension HolidaySchedule {
    /// Apple 的中文订阅只提供中文标题；已知节日映射成本地化名称，未知名称保守显示“公众假期”。
    static func localizedHolidayName(_ name: String) -> String {
        switch name {
        case "元旦": return String(localized: "holiday.newYear", defaultValue: "New Year’s Day")
        case "春节": return String(localized: "holiday.springFestival", defaultValue: "Chinese New Year")
        case "清明": return String(localized: "holiday.qingming", defaultValue: "Qingming Festival")
        case "劳动节": return String(localized: "holiday.labourDay", defaultValue: "Labor Day")
        case "端午节": return String(localized: "holiday.dragonBoat", defaultValue: "Dragon Boat Festival")
        case "中秋节": return String(localized: "holiday.midAutumn", defaultValue: "Mid-Autumn Festival")
        case "国庆节": return String(localized: "holiday.nationalDay", defaultValue: "National Day")
        default: return String(localized: "holiday.public", defaultValue: "Public holiday")
        }
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

    /// 返回某一天的计费类型。节假日名称只影响说明，不参与规则匹配。
    static func dayInfo(for date: Date, schedule: HolidaySchedule) -> PricingDayInfo {
        let components = calendar.dateComponents([.year, .weekday], from: date)
        let year = components.year ?? 0
        let weekday = components.weekday ?? 1
        let isWeekend = weekday == 1 || weekday == 7

        if isWeekend, let entry = schedule.alternateWorkday(on: date) {
            return PricingDayInfo(kind: .alternateWorkdayWeekend(entry.name),
                                  scheduleIsCovered: schedule.isCovered(year: year))
        }
        if let entry = schedule.holiday(on: date) {
            return PricingDayInfo(kind: .publicHoliday(entry.name),
                                  scheduleIsCovered: schedule.isCovered(year: year))
        }
        if isWeekend {
            return PricingDayInfo(kind: .weekend,
                                  scheduleIsCovered: schedule.isCovered(year: year))
        }
        return PricingDayInfo(kind: .regularWeekday,
                              scheduleIsCovered: schedule.isCovered(year: year))
    }

    /// 判断某一时刻是否处于高峰时段。
    static func period(at date: Date, schedule: HolidaySchedule) -> PricePeriod {
        if dayInfo(for: date, schedule: schedule).isAllDayOffPeak {
            return .offPeak
        }
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

    /// 某个日期前后若干天的名义边界；只有边界两侧价格真的不同时才算切换。
    private static func boundaries(around date: Date, dayOffsets: ClosedRange<Int>) -> [Date] {
        guard let today = calendar.dateInterval(of: .day, for: date)?.start else { return [] }
        return dayOffsets
            .compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .flatMap { boundaries(onDayStartingAt: $0) }
            .sorted()
    }

    private static func isRealTransition(_ boundary: Date, schedule: HolidaySchedule) -> Bool {
        period(at: boundary.addingTimeInterval(-1), schedule: schedule)
            != period(at: boundary, schedule: schedule)
    }

    /// 下一次时段切换的时刻；若当前处于高峰时段，则返回本次高峰结束的时刻。
    static func nextTransition(after date: Date, schedule: HolidaySchedule) -> Date {
        // 中国法定连续假期远短于 32 天；这个范围覆盖长假，同时避免每秒刷新时做无谓计算。
        let next = boundaries(around: date, dayOffsets: 0...32)
            .first { $0 > date && isRealTransition($0, schedule: schedule) }
        return next ?? calendar.date(byAdding: .day, value: 32, to: date) ?? date
    }

    /// 当前这一段「时段区间」的起点：最近一次时段边界。
    static func currentIntervalStart(before date: Date, schedule: HolidaySchedule) -> Date {
        let last = boundaries(around: date, dayOffsets: -32...0)
            .last { $0 <= date && isRealTransition($0, schedule: schedule) }
        return last ?? calendar.startOfDay(for: date)
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
    /// 当天为何采用这套计费规则。
    let dayInfo: PricingDayInfo

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

    init(now: Date, schedule: HolidaySchedule = .bundled) {
        self.now = now
        let period = DeepSeekPricing.period(at: now, schedule: schedule)
        self.period = period
        self.dayInfo = DeepSeekPricing.dayInfo(for: now, schedule: schedule)
        self.intervalStart = DeepSeekPricing.currentIntervalStart(before: now, schedule: schedule)
        let transition = DeepSeekPricing.nextTransition(after: now, schedule: schedule)
        self.nextTransition = transition
        self.nextPeriod = DeepSeekPricing.period(at: transition, schedule: schedule)
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

    /// 月历标题，例如 “September 2026” / “2026年9月”。
    static func monthYear(_ date: Date) -> String {
        string(from: date, template: "yMMMM")
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

    /// 月历表头使用的最短星期名称，顺序固定为周一 → 周日。
    static let veryShortWeekdaySymbolsMondayFirst: [String] = {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.calendar = DeepSeekPricing.calendar
        formatter.timeZone = DeepSeekPricing.timeZone
        let symbols = formatter.veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
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

    /// 菜单栏倒计时文案使用总小时数 `HH:MM:SS`。连续长假可能超过 99 小时，
    /// 所以小时位不截断；菜单栏会按实际文本重新量宽。
    static func compactCountdown(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}

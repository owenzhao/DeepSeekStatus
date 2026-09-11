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

    /// 中文名称，例如「高峰时段」。
    var title: String {
        switch self {
        case .peak: return "高峰时段"
        case .offPeak: return "空闲时段"
        }
    }

    /// 简短名称，用于空间较小的位置。
    var shortTitle: String {
        switch self {
        case .peak: return "高峰"
        case .offPeak: return "空闲"
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
        case .peak: return "高峰价（100%）"
        case .offPeak: return "高峰价的一半（50%）"
        }
    }

    /// 对应时段的说明。
    var summary: String {
        switch self {
        case .peak: return "当前为高峰时段，按全额价格计费。"
        case .offPeak: return "当前为空闲时段，价格是高峰时段的一半。"
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
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "zh_CN")
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
    /// 北京时间「HH:mm」。
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = DeepSeekPricing.calendar
        formatter.timeZone = DeepSeekPricing.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// 北京时间「HH:mm:ss」。
    static func preciseTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = DeepSeekPricing.calendar
        formatter.timeZone = DeepSeekPricing.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    /// 北京时间日期「M月d日 EEEE」。
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = DeepSeekPricing.calendar
        formatter.timeZone = DeepSeekPricing.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }

    /// 把切换时刻描述成「今天 14:00」「明天 09:00」「周一 09:00」。
    static func transitionDescription(_ date: Date, relativeTo now: Date) -> String {
        let calendar = DeepSeekPricing.calendar
        let dayDelta = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        let timeText = time(date)
        switch dayDelta {
        case ..<0: return "\(timeText)"
        case 0: return "今天 \(timeText)"
        case 1: return "明天 \(timeText)"
        case 2: return "后天 \(timeText)"
        default:
            let weekday = weekdayName(of: date)
            if dayDelta < 7 { return "\(weekday) \(timeText)" }
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = DeepSeekPricing.timeZone
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M月d日 HH:mm"
            return formatter.string(from: date)
        }
    }

    /// 中文星期简称。
    static func weekdayName(of date: Date) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekday = DeepSeekPricing.calendar.component(.weekday, from: date)
        let index = min(max(weekday - 1, 0), 6)
        return names[index]
    }

    /// 把秒数格式化成「1 小时 23 分」「23 分 05 秒」这类可读文案。
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60

        if days > 0 {
            return hours > 0 ? "\(days) 天 \(hours) 小时" : "\(days) 天"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours) 小时 \(minutes) 分" : "\(hours) 小时"
        }
        if minutes > 0 {
            return String(format: "%d 分 %02d 秒", minutes, secs)
        }
        return "\(secs) 秒"
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

import Foundation

/// DeepSeek 峰谷计费需要的中国大陆放假安排。
///
/// 日期都是北京时间的自然日。这里只保留 Apple 日历中明确标记为放假或调休补班的事件，
/// 不把节气、纪念日或普通节日名称当作放假依据。
struct HolidaySchedule: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable {
            case holiday
            case alternateWorkday
        }

        let kind: Kind
        /// `yyyy-MM-dd`，包含当天。
        let startDay: String
        /// `yyyy-MM-dd`，不包含当天。
        let endDayExclusive: String
        /// Apple 日历中的中文节日名称，已去掉“（休）/（班）”。只用于显示。
        let name: String

        func contains(_ day: String) -> Bool {
            startDay <= day && day < endDayExclusive
        }
    }

    let entries: [Entry]
    let fetchedAt: Date?

    var coveredYears: Set<Int> {
        Set(entries.compactMap { entry in
            guard entry.kind == .holiday else { return nil }
            return Int(entry.startDay.prefix(4))
        })
    }

    var newestCoveredYear: Int? { coveredYears.max() }

    func isCovered(year: Int) -> Bool {
        coveredYears.contains(year)
    }

    func holiday(on date: Date) -> Entry? {
        let day = Self.dayKey(for: date)
        return entries.first { $0.kind == .holiday && $0.contains(day) }
    }

    func alternateWorkday(on date: Date) -> Entry? {
        let day = Self.dayKey(for: date)
        return entries.first { $0.kind == .alternateWorkday && $0.contains(day) }
    }

    static func dayKey(for date: Date) -> String {
        let components = DeepSeekPricing.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DeepSeekPricing.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func date(fromICSDate value: String) -> Date? {
        guard value.count == 8,
              let year = Int(value.prefix(4)),
              let month = Int(value.dropFirst(4).prefix(2)),
              let day = Int(value.suffix(2)) else { return nil }
        return DeepSeekPricing.calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// 解析 Apple 中国大陆节假日日历。ICS 中的 `DTEND` 是左闭右开的结束日期。
    static func parseICS(_ data: Data, fetchedAt: Date = Date()) throws -> HolidaySchedule {
        guard let raw = String(data: data, encoding: .utf8) else {
            throw ParseError.invalidEncoding
        }

        // RFC 5545：以空格或 Tab 开头的物理行要接到上一行。
        let physicalLines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var lines: [String] = []
        for line in physicalLines {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += String(line.dropFirst())
            } else {
                lines.append(line)
            }
        }

        var events: [[String: String]] = []
        var event: [String: String]?
        for line in lines {
            if line == "BEGIN:VEVENT" {
                event = [:]
                continue
            }
            if line == "END:VEVENT" {
                if let event { events.append(event) }
                event = nil
                continue
            }
            guard event != nil, let colon = line.firstIndex(of: ":") else { continue }
            let propertyPart = line[..<colon]
            let name = propertyPart.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
            let value = String(line[line.index(after: colon)...])
            event?[name] = value
        }

        var entries: [Entry] = []
        for event in events {
            let kind: Entry.Kind
            switch event["X-APPLE-SPECIAL-DAY"] {
            case "WORK-HOLIDAY": kind = .holiday
            case "ALTERNATE-WORKDAY": kind = .alternateWorkday
            default: continue
            }

            guard let sourceStart = event["DTSTART"],
                  let start = date(fromICSDate: sourceStart) else { continue }
            let end: Date
            if let sourceEnd = event["DTEND"], let parsedEnd = date(fromICSDate: sourceEnd) {
                end = parsedEnd
            } else {
                end = DeepSeekPricing.calendar.date(byAdding: .day, value: 1, to: start) ?? start
            }
            guard end > start else { continue }

            entries.append(Entry(kind: kind,
                                 startDay: dayKey(for: start),
                                 endDayExclusive: dayKey(for: end),
                                 name: normalizedName(event["SUMMARY"] ?? "")))
        }

        guard entries.contains(where: { $0.kind == .holiday }) else {
            throw ParseError.noHolidayEntries
        }
        return HolidaySchedule(entries: entries.sorted { lhs, rhs in
            lhs.startDay == rhs.startDay ? lhs.kind.rawValue < rhs.kind.rawValue : lhs.startDay < rhs.startDay
        }, fetchedAt: fetchedAt)
    }

    private static func normalizedName(_ raw: String) -> String {
        var name = raw
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
        for suffix in ["（休）", "（班）", "(休)", "(班)"] where name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
        }
        return name.isEmpty ? "Public holiday" : name
    }

    enum ParseError: Error {
        case invalidEncoding
        case noHolidayEntries
    }

    /// 随 App 发布的 2026 年兜底。在线日历不可用时仍能正确判断当年的计费规则。
    static let bundled = HolidaySchedule(entries: [
        Entry(kind: .holiday, startDay: "2026-01-01", endDayExclusive: "2026-01-04", name: "元旦"),
        Entry(kind: .alternateWorkday, startDay: "2026-01-04", endDayExclusive: "2026-01-05", name: "元旦"),
        Entry(kind: .alternateWorkday, startDay: "2026-02-14", endDayExclusive: "2026-02-15", name: "春节"),
        Entry(kind: .holiday, startDay: "2026-02-15", endDayExclusive: "2026-02-24", name: "春节"),
        Entry(kind: .alternateWorkday, startDay: "2026-02-28", endDayExclusive: "2026-03-01", name: "春节"),
        Entry(kind: .holiday, startDay: "2026-04-04", endDayExclusive: "2026-04-07", name: "清明"),
        Entry(kind: .holiday, startDay: "2026-05-01", endDayExclusive: "2026-05-06", name: "劳动节"),
        Entry(kind: .alternateWorkday, startDay: "2026-05-09", endDayExclusive: "2026-05-10", name: "劳动节"),
        Entry(kind: .holiday, startDay: "2026-06-19", endDayExclusive: "2026-06-22", name: "端午节"),
        Entry(kind: .alternateWorkday, startDay: "2026-09-20", endDayExclusive: "2026-09-21", name: "国庆节"),
        Entry(kind: .holiday, startDay: "2026-09-25", endDayExclusive: "2026-09-28", name: "中秋节"),
        Entry(kind: .holiday, startDay: "2026-10-01", endDayExclusive: "2026-10-08", name: "国庆节"),
        Entry(kind: .alternateWorkday, startDay: "2026-10-10", endDayExclusive: "2026-10-11", name: "国庆节"),
    ], fetchedAt: nil)
}

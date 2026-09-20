import SwiftUI

/// “时段规则”里的两种查看方式。默认月历，周时段图保留为可切换页。
struct PricingScheduleView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case calendar
        case week

        var id: String { rawValue }

        var title: String {
            switch self {
            case .calendar:
                String(localized: "schedule.mode.calendar", defaultValue: "Monthly calendar")
            case .week:
                String(localized: "schedule.mode.week", defaultValue: "Weekly hours")
            }
        }
    }

    let now: Date
    let schedule: HolidaySchedule

    @State private var mode: Mode = .calendar
    @State private var selectedDate: Date
    @State private var displayedMonth: Date

    init(now: Date, schedule: HolidaySchedule) {
        self.now = now
        self.schedule = schedule
        let month = DeepSeekPricing.calendar.dateInterval(of: .month, for: now)?.start ?? now
        _selectedDate = State(initialValue: now)
        _displayedMonth = State(initialValue: month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)

            switch mode {
            case .calendar:
                PricingCalendarView(now: now,
                                    schedule: schedule,
                                    selectedDate: $selectedDate,
                                    displayedMonth: $displayedMonth)
            case .week:
                WeekScheduleGrid(now: now, referenceDate: selectedDate, schedule: schedule)
            }
        }
        .onChange(of: HolidaySchedule.dayKey(for: now)) { oldDay, _ in
            // 如果用户还停留在昨天默认选中的“今天”，跨日时一起推进；主动选过别的日期则不打扰。
            guard HolidaySchedule.dayKey(for: selectedDate) == oldDay else { return }
            selectedDate = now
            displayedMonth = DeepSeekPricing.calendar.dateInterval(of: .month, for: now)?.start ?? now
        }
    }
}

private struct PricingCalendarView: View {
    let now: Date
    let schedule: HolidaySchedule
    @Binding var selectedDate: Date
    @Binding var displayedMonth: Date

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            monthHeader
            weekdayHeader
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 27)
                    }
                }
            }
            legend
            selectedDayDetail
            if !displayedYearIsCovered {
                Label {
                    Text(String(localized: "calendar.coverage.warning",
                                defaultValue: "Official holiday data is not available for this year. Weekday results use the base schedule."))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 6) {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .help(String(localized: "calendar.previousMonth", defaultValue: "Previous month"))

            Text(PricingFormatter.monthYear(displayedMonth))
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .help(String(localized: "calendar.nextMonth", defaultValue: "Next month"))

            Button(String(localized: "calendar.today", defaultValue: "Today")) {
                selectedDate = now
                displayedMonth = DeepSeekPricing.calendar.dateInterval(of: .month, for: now)?.start ?? now
            }
            .buttonStyle(.link)
            .font(.system(size: 10.5, weight: .medium))
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(PricingFormatter.veryShortWeekdaySymbolsMondayFirst.enumerated()), id: \.offset) { _, symbol in
                Text(verbatim: symbol)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let calendar = DeepSeekPricing.calendar
        let info = DeepSeekPricing.dayInfo(for: date, schedule: schedule)
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let today = calendar.isDate(date, inSameDayAs: now)

        return Button {
            selectedDate = date
        } label: {
            Text(verbatim: "\(calendar.component(.day, from: date))")
                .font(.system(size: 10.5, weight: selected || today ? .bold : .regular))
                .foregroundStyle(info.isAllDayOffPeak ? WhaleTheme.offPeakAccent : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 27)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(info.isAllDayOffPeak
                              ? WhaleTheme.offPeakAccent.opacity(0.15)
                              : Color.secondary.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(selected ? WhaleTheme.brandBlue
                                : (today ? Color.primary.opacity(0.55) : .clear),
                                lineWidth: selected ? 1.6 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: WhaleTheme.offPeakAccent.opacity(0.25),
                       title: String(localized: "calendar.legend.allDayOffPeak",
                                     defaultValue: "Off-peak all day"))
            legendItem(color: Color.secondary.opacity(0.12),
                       title: String(localized: "calendar.legend.timed",
                                     defaultValue: "Time-based pricing"))
            Spacer(minLength: 0)
        }
        .font(.system(size: 9.5))
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(title)
        }
    }

    private var selectedDayDetail: some View {
        let info = DeepSeekPricing.dayInfo(for: selectedDate, schedule: schedule)
        return VStack(alignment: .leading, spacing: 2) {
            Text(PricingFormatter.day(selectedDate))
                .font(.system(size: 10.5, weight: .semibold))
            Text(info.localizedDetail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var monthCells: [Date?] {
        let calendar = DeepSeekPricing.calendar
        guard let month = calendar.dateInterval(of: .month, for: displayedMonth),
              let days = calendar.range(of: .day, in: .month, for: month.start) else { return [] }
        let weekday = calendar.component(.weekday, from: month.start)
        let leadingEmpty = (weekday + 5) % 7
        var result = Array<Date?>(repeating: nil, count: leadingEmpty)
        result += days.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: month.start)
        }.map(Optional.some)
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    private var displayedYearIsCovered: Bool {
        let year = DeepSeekPricing.calendar.component(.year, from: displayedMonth)
        return schedule.isCovered(year: year)
    }

    private func moveMonth(by value: Int) {
        guard let month = DeepSeekPricing.calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = month
        selectedDate = month
    }
}

#Preview("价格日历") {
    PricingScheduleView(now: Date(), schedule: .bundled)
        .frame(width: 288)
        .padding()
}

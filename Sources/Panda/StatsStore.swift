import Combine
import Foundation

struct DayStats: Codable, Equatable {
    var instagram: Int = 0
    var shorts: Int = 0
    var youtube: Int = 0
    var custom: Int = 0
    var protectedSeconds: Double = 0

    var total: Int { instagram + shorts + youtube + custom }

    init() {}

    enum CodingKeys: String, CodingKey { case instagram, shorts, youtube, custom, protectedSeconds }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        instagram = try c.decodeIfPresent(Int.self, forKey: .instagram) ?? 0
        shorts = try c.decodeIfPresent(Int.self, forKey: .shorts) ?? 0
        youtube = try c.decodeIfPresent(Int.self, forKey: .youtube) ?? 0
        custom = try c.decodeIfPresent(Int.self, forKey: .custom) ?? 0
        protectedSeconds = try c.decodeIfPresent(Double.self, forKey: .protectedSeconds) ?? 0
    }
}

struct DayEntry: Identifiable, Equatable {
    let date: Date
    let key: String
    let label: String
    let stats: DayStats
    let isToday: Bool
    var id: String { key }
}

/// Local-only statistics. One small JSON file in ~/Library/Application Support/Panda.
/// Counts are per calendar day. Nothing about what was blocked is stored beyond the category.
final class StatsStore: ObservableObject {
    static let shared = StatsStore()

    @Published private(set) var days: [String: DayStats] = [:]

    private var fileURL: URL
    private var protectionStart: Date?
    private var checkpointTimer: Timer?
    private var persists = true

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f
    }()

    private init() {
        fileURL = PandaPaths.statsFile
        load()
    }

    /// A store filled with made-up numbers, used only to render preview images.
    static func sample() -> StatsStore {
        let store = StatsStore(sampleDays: [
            (6, 4, 6, 3.1), (5, 7, 9, 5.4), (4, 2, 3, 6.0), (3, 5, 4, 4.2),
            (2, 1, 2, 7.5), (1, 3, 5, 5.0), (0, 2, 3, 2.6),
        ])
        return store
    }

    private init(sampleDays: [(Int, Int, Int, Double)]) {
        fileURL = URL(fileURLWithPath: "/dev/null")
        persists = false
        let cal = Calendar.current
        for (daysAgo, insta, shorts, hours) in sampleDays {
            guard let date = cal.date(byAdding: .day, value: -daysAgo, to: Date()) else { continue }
            var stats = DayStats()
            stats.instagram = insta
            stats.shorts = shorts
            stats.custom = (daysAgo * 3 + 1) % 4
            stats.protectedSeconds = hours * 3600
            days[StatsStore.key(for: date)] = stats
        }
    }

    static func key(for date: Date) -> String {
        keyFormatter.string(from: date)
    }

    // MARK: Reading

    var today: DayStats {
        days[StatsStore.key(for: Date())] ?? DayStats()
    }

    /// The last seven days, oldest first, ending with today.
    var lastSevenDays: [DayEntry] {
        let cal = Calendar.current
        let now = Date()
        return (0..<7).reversed().compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let key = StatsStore.key(for: date)
            return DayEntry(
                date: date,
                key: key,
                label: StatsStore.weekdayFormatter.string(from: date),
                stats: days[key] ?? DayStats(),
                isToday: offset == 0
            )
        }
    }

    var weekTotal: Int { lastSevenDays.reduce(0) { $0 + $1.stats.total } }
    var weekInstagram: Int { lastSevenDays.reduce(0) { $0 + $1.stats.instagram } }
    var weekShorts: Int { lastSevenDays.reduce(0) { $0 + $1.stats.shorts + $1.stats.youtube } }
    var weekCustom: Int { lastSevenDays.reduce(0) { $0 + $1.stats.custom } }
    var allTimeTotal: Int { days.values.reduce(0) { $0 + $1.total } }

    /// Seconds of protection today, including the stretch that is still running.
    func protectedSecondsToday(now: Date = Date()) -> Double {
        var seconds = today.protectedSeconds
        if let start = protectionStart {
            let dayStart = Calendar.current.startOfDay(for: now)
            seconds += max(0, now.timeIntervalSince(max(start, dayStart)))
        }
        return seconds
    }

    func protectedSecondsThisWeek(now: Date = Date()) -> Double {
        var seconds = lastSevenDays.reduce(0.0) { $0 + $1.stats.protectedSeconds }
        if let start = protectionStart {
            seconds += max(0, now.timeIntervalSince(start))
        }
        return seconds
    }

    func protectedSecondsAllTime(now: Date = Date()) -> Double {
        var seconds = days.values.reduce(0.0) { $0 + $1.protectedSeconds }
        if let start = protectionStart {
            seconds += max(0, now.timeIntervalSince(start))
        }
        return seconds
    }

    // MARK: Writing

    func record(_ kind: BlockKind) {
        let key = StatsStore.key(for: Date())
        var stats = days[key] ?? DayStats()
        switch kind {
        case .instagram: stats.instagram += 1
        case .shorts: stats.shorts += 1
        case .youtube: stats.youtube += 1
        case .custom: stats.custom += 1
        }
        days[key] = stats
        save()
    }

    /// Start or stop the "time spent protected" clock.
    func setProtectionActive(_ active: Bool) {
        if active {
            guard protectionStart == nil else { return }
            protectionStart = Date()
            startCheckpointTimer()
        } else {
            flush()
            protectionStart = nil
            checkpointTimer?.invalidate()
            checkpointTimer = nil
        }
    }

    /// Bank the running stretch of protected time. Safe to call at any moment.
    func flush() {
        guard let start = protectionStart else { return }
        let now = Date()
        protectionStart = now
        accumulate(from: start, to: now)
        save()
    }

    func reset() {
        days = [:]
        if protectionStart != nil { protectionStart = Date() }
        save()
    }

    private func accumulate(from start: Date, to end: Date) {
        // Ignore nonsense spans (clock changes, a week asleep with the lid closed).
        guard end > start, end.timeIntervalSince(start) < 60 * 60 * 48 else { return }
        let cal = Calendar.current
        var cursor = start
        var updated = days
        while cursor < end {
            let dayStart = cal.startOfDay(for: cursor)
            let nextDay = cal.date(byAdding: .day, value: 1, to: dayStart) ?? end
            let sliceEnd = min(end, nextDay)
            let key = StatsStore.key(for: cursor)
            var stats = updated[key] ?? DayStats()
            stats.protectedSeconds += sliceEnd.timeIntervalSince(cursor)
            updated[key] = stats
            if sliceEnd <= cursor { break }
            cursor = sliceEnd
        }
        days = updated
    }

    private func startCheckpointTimer() {
        checkpointTimer?.invalidate()
        // A sleepy five-minute checkpoint so a crash or power cut loses very little.
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            self?.flush()
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        checkpointTimer = timer
    }

    // MARK: Disk

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: DayStats].self, from: data) else { return }
        days = decoded
    }

    private func save() {
        guard persists else { return }
        PandaPaths.ensureSupportDir()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(days) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

enum DurationText {
    /// "3h 12m", "45m", "under a minute".
    static func short(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "0m" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return "\(hours)h \(rest)m"
    }
}

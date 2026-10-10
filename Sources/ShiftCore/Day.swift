import Foundation

/// A calendar day in the driver's time zone, written as `YYYY-MM-DD`.
public struct Day: Hashable, Comparable, Sendable, Codable, LosslessStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD` and rejects impossible dates such as `2026-02-30`.
    public init?(_ description: String) {
        let parts = description.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: calendar) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The day on which `date` falls in `timeZone`.
    public init(containing date: Date, in timeZone: TimeZone) {
        let parts = Day.calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public func adding(days: Int) -> Day {
        let calendar = Day.calendar(TimeZone(secondsFromGMT: 0)!)
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        let shifted = calendar.date(byAdding: .day, value: days, to: date)!
        return Day(containing: shifted, in: calendar.timeZone)
    }

    public static func < (lhs: Day, rhs: Day) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let day = Day(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected YYYY-MM-DD, got \(raw)")
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

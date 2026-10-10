import Foundation
import Testing
@testable import ShiftCore

let almaty = TimeZone(secondsFromGMT: 5 * 3600)!

func date(_ iso: String) -> Date {
    try! Date(iso, strategy: .iso8601)
}

func trip(
    _ id: String,
    _ start: String,
    _ end: String,
    amount: Int,
    _ payment: PaymentMethod,
    commission: Int
) -> Trip {
    Trip(id: id, start: date(start), end: date(end), amount: amount, payment: payment, commission: commission)
}

/// The example from the task description.
let sampleTrips = [
    trip("t1", "2026-10-01T08:10:00+05:00", "2026-10-01T08:32:00+05:00", amount: 2400, .card, commission: 360),
    trip("t2", "2026-10-01T09:05:00+05:00", "2026-10-01T09:20:00+05:00", amount: 1500, .cash, commission: 225),
]

@Suite("Day summary")
struct DaySummaryTests {
    @Test func matchesTheCardFromTheTask() {
        let summary = DaySummary(trips: sampleTrips)
        #expect(summary.tripCount == 2)
        #expect(summary.revenue == 3900)
        #expect(summary.commission == 585)
        #expect(summary.net == 3315)
        #expect(summary.cash == 1500)
        #expect(summary.card == 2400)
    }

    @Test func emptyDayIsAllZeros() {
        let summary = DaySummary(trips: [])
        let values: [Int] = [summary.tripCount, summary.revenue, summary.commission, summary.net, summary.cash, summary.card]
        #expect(values.allSatisfy { $0 == 0 })
    }
}

@Suite("Day boundaries")
struct DayTests {
    @Test func parsesOnlyRealDates() {
        #expect(Day("2026-10-01") == Day(year: 2026, month: 10, day: 1))
        #expect(Day("2026-02-30") == nil)
        #expect(Day("2026-1-01") == nil)
        #expect(Day("yesterday") == nil)
    }

    @Test func usesDriversTimeZoneNotUTC() {
        // 19:30 UTC on Oct 1 is 00:30 on Oct 2 in Almaty.
        #expect(Day(containing: date("2026-10-01T19:30:00Z"), in: almaty) == Day("2026-10-02"))
    }

    @Test func navigatesAcrossMonthEnd() {
        #expect(Day("2026-09-30")!.adding(days: 1) == Day("2026-10-01"))
        #expect(Day("2026-10-01")!.adding(days: -1) == Day("2026-09-30"))
    }

    @Test func tripCrossingMidnightBelongsToItsStartDay() async {
        let late = trip("late", "2026-10-02T23:40:00+05:00", "2026-10-03T00:05:00+05:00", amount: 2800, .card, commission: 420)
        let store = TripStore(trips: [late], timeZone: almaty)
        #expect(await store.trips(on: Day("2026-10-02")!) == [late])
        #expect(await store.trips(on: Day("2026-10-03")!).isEmpty)
    }
}

@Suite("Validation")
struct ValidationTests {
    let start = "2026-10-01T08:10:00+05:00"
    let end = "2026-10-01T08:32:00+05:00"

    @Test func validTripHasNoErrors() {
        #expect(sampleTrips[0].validationErrors.isEmpty)
    }

    @Test(arguments: [0, -100])
    func amountMustBePositive(amount: Int) {
        let bad = trip("x", start, end, amount: amount, .card, commission: 0)
        #expect(bad.validationErrors.contains(.nonPositiveAmount))
    }

    @Test func endMustBeAfterStart() {
        #expect(trip("x", start, start, amount: 100, .cash, commission: 0).validationErrors == [.endNotAfterStart])
        #expect(trip("x", end, start, amount: 100, .cash, commission: 0).validationErrors == [.endNotAfterStart])
    }

    @Test func commissionMustBeWithinAmount() {
        #expect(trip("x", start, end, amount: 100, .cash, commission: -1).validationErrors == [.negativeCommission])
        #expect(trip("x", start, end, amount: 100, .cash, commission: 101).validationErrors == [.commissionExceedsAmount])
    }

    @Test func reportsEveryProblemAtOnce() {
        let bad = trip(" ", end, start, amount: 0, .cash, commission: -5)
        #expect(Set(bad.validationErrors.map(\.description)).count == 4)
    }
}

@Suite("Duplicate protection")
struct DuplicateTests {
    @Test func sameTripTwiceIsStoredOnce() async throws {
        let store = TripStore(timeZone: almaty)
        #expect(try await store.add(sampleTrips[0]) == .created(sampleTrips[0]))
        #expect(try await store.add(sampleTrips[0]) == .duplicate(sampleTrips[0]))
        #expect(await store.trips(on: Day("2026-10-01")!).count == 1)
    }

    @Test func sameIDWithDifferentDataIsAConflict() async throws {
        let store = TripStore(trips: [sampleTrips[0]], timeZone: almaty)
        let changed = trip("t1", "2026-10-01T08:10:00+05:00", "2026-10-01T08:32:00+05:00", amount: 9999, .card, commission: 360)
        await #expect(throws: AddTripError.conflict(existing: sampleTrips[0])) {
            try await store.add(changed)
        }
        #expect(await store.trips(on: Day("2026-10-01")!) == [sampleTrips[0]])
    }

    @Test func concurrentRetriesCreateExactlyOneTrip() async throws {
        let store = TripStore(timeZone: almaty)
        let outcomes = try await withThrowingTaskGroup(of: AddTripOutcome.self) { group in
            for _ in 0..<50 {
                group.addTask { try await store.add(sampleTrips[1]) }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(outcomes.filter { $0 == .created(sampleTrips[1]) }.count == 1)
        #expect(await store.trips(on: Day("2026-10-01")!).count == 1)
    }

    @Test func invalidTripIsRejectedAndNotStored() async {
        let store = TripStore(timeZone: almaty)
        let bad = trip("bad", "2026-10-01T08:10:00+05:00", "2026-10-01T08:00:00+05:00", amount: 100, .cash, commission: 0)
        await #expect(throws: AddTripError.invalid([.endNotAfterStart])) {
            try await store.add(bad)
        }
        #expect(await store.days().isEmpty)
    }
}

@Suite("Persistence")
struct PersistenceTests {
    @Test func addedTripSurvivesReload() async throws {
        let file = FileManager.default.temporaryDirectory
            .appending(path: "shift-diary-\(UUID().uuidString)")
            .appending(path: "trips.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let store = try TripStore.load(from: file, timeZone: almaty)
        _ = try await store.add(sampleTrips[0])

        let reloaded = try TripStore.load(from: file, timeZone: almaty)
        #expect(await reloaded.trips(on: Day("2026-10-01")!) == [sampleTrips[0]])

        // Dates are written in the driver's time zone, like the source data.
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("2026-10-01T08:10:00+05:00"))
    }
}

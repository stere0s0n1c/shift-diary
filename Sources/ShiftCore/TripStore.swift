import Foundation

public enum AddTripOutcome: Sendable, Equatable {
    /// The trip was new and is now stored.
    case created(Trip)
    /// A trip with the same id and the same data was already stored; nothing changed.
    case duplicate(Trip)
}

public enum AddTripError: Error, Sendable, Equatable {
    case invalid([TripValidationError])
    /// Same id, different data. Overwriting silently could hide a client bug, so we refuse.
    case conflict(existing: Trip)
}

/// Trips keyed by id. The trip id is the idempotency key: a retried POST with the same
/// trip is answered as a duplicate instead of creating a second record.
///
/// An actor, so two simultaneous requests with the same trip cannot both insert it.
public actor TripStore {
    public nonisolated let timeZone: TimeZone
    private let fileURL: URL?
    private var tripsByID: [String: Trip]

    public init(trips: [Trip] = [], timeZone: TimeZone, fileURL: URL? = nil) {
        self.timeZone = timeZone
        self.fileURL = fileURL
        // If the seed file repeats an id, the last entry wins.
        self.tripsByID = Dictionary(trips.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    /// Loads trips from a JSON array. A missing file means an empty diary.
    /// New trips are written back to the same file.
    public static func load(from fileURL: URL, timeZone: TimeZone) throws -> TripStore {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return TripStore(timeZone: timeZone, fileURL: fileURL)
        }
        let data = try Data(contentsOf: fileURL)
        let trips = try TripCoding.decoder().decode([Trip].self, from: data)
        return TripStore(trips: trips, timeZone: timeZone, fileURL: fileURL)
    }

    public func add(_ trip: Trip) throws -> AddTripOutcome {
        let errors = trip.validationErrors
        guard errors.isEmpty else { throw AddTripError.invalid(errors) }

        if let existing = tripsByID[trip.id] {
            guard existing == trip else { throw AddTripError.conflict(existing: existing) }
            return .duplicate(existing)
        }

        tripsByID[trip.id] = trip
        do {
            try persist()
        } catch {
            // Keep memory and file in sync: if the write failed, the trip is not stored.
            tripsByID[trip.id] = nil
            throw error
        }
        return .created(trip)
    }

    /// Trips that started on `day` in the driver's time zone, oldest first.
    /// A trip that crosses midnight belongs to the day it started.
    public func trips(on day: Day) -> [Trip] {
        tripsByID.values
            .filter { Day(containing: $0.start, in: timeZone) == day }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    public func report(for day: Day) -> DayReport {
        DayReport(date: day, utcOffsetSeconds: timeZone.secondsFromGMT(), trips: trips(on: day))
    }

    /// Days that have at least one trip, oldest first.
    public func days() -> [Day] {
        Set(tripsByID.values.map { Day(containing: $0.start, in: timeZone) }).sorted()
    }

    private func persist() throws {
        guard let fileURL else { return }
        let trips = tripsByID.values.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        let data = try TripCoding.encoder(timeZone: timeZone, pretty: true).encode(trips)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}

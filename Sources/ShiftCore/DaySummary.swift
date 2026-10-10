import Foundation

/// The numbers from the "Дневник смен" card for one day.
public struct DaySummary: Codable, Sendable, Equatable {
    public let tripCount: Int
    /// Sum of all trip amounts.
    public let revenue: Int
    public let commission: Int
    /// What the driver keeps: revenue minus commission.
    public let net: Int
    /// Revenue split by payment method.
    public let cash: Int
    public let card: Int

    public init(trips: [Trip]) {
        tripCount = trips.count
        revenue = trips.reduce(0) { $0 + $1.amount }
        commission = trips.reduce(0) { $0 + $1.commission }
        net = revenue - commission
        cash = trips.filter { $0.payment == .cash }.reduce(0) { $0 + $1.amount }
        card = trips.filter { $0.payment == .card }.reduce(0) { $0 + $1.amount }
    }
}

/// Response for one day: summary plus the trips it was computed from.
public struct DayReport: Codable, Sendable, Equatable {
    public let date: Day
    /// Offset of the driver's time zone, so a client can show local times without guessing.
    public let utcOffsetSeconds: Int
    public let summary: DaySummary
    public let trips: [Trip]

    public init(date: Day, utcOffsetSeconds: Int, trips: [Trip]) {
        self.date = date
        self.utcOffsetSeconds = utcOffsetSeconds
        self.summary = DaySummary(trips: trips)
        self.trips = trips
    }
}

public struct DaysList: Codable, Sendable, Equatable {
    public let days: [Day]

    public init(days: [Day]) {
        self.days = days
    }
}

/// Answer to POST /api/trips. `created == false` means the same trip was already stored.
public struct AddTripResult: Codable, Sendable, Equatable {
    public let created: Bool
    public let trip: Trip

    public init(created: Bool, trip: Trip) {
        self.created = created
        self.trip = trip
    }
}

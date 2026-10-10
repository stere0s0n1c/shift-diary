import Foundation
import ShiftCore
import Vapor

/// Wires the HTTP API to a store.
///
/// GET  /api/days               days that have trips
/// GET  /api/days/:date         summary + trips for one day (YYYY-MM-DD)
/// POST /api/trips              add a trip; repeating the same trip does not create a duplicate
public func configure(_ app: Application, store: TripStore) throws {
    ContentConfiguration.global.use(encoder: TripCoding.encoder(timeZone: store.timeZone), for: .json)
    ContentConfiguration.global.use(decoder: TripCoding.decoder(), for: .json)

    let api = app.grouped("api")

    api.get("days") { _ async throws -> Response in
        try json(DaysList(days: await store.days()))
    }

    api.get("days", ":date") { req async throws -> Response in
        guard let raw = req.parameters.get("date"), let day = Day(raw) else {
            throw Abort(.badRequest, reason: "date must be YYYY-MM-DD")
        }
        return try json(await store.report(for: day))
    }

    api.post("trips") { req async throws -> Response in
        let trip: Trip
        do {
            trip = try req.content.decode(Trip.self)
        } catch {
            throw Abort(.badRequest, reason: "invalid trip JSON: \(error)")
        }

        do {
            switch try await store.add(trip) {
            case .created(let stored):
                return try json(AddTripResult(created: true, trip: stored), status: .created)
            case .duplicate(let stored):
                return try json(AddTripResult(created: false, trip: stored), status: .ok)
            }
        } catch AddTripError.invalid(let errors) {
            throw Abort(.unprocessableEntity, reason: errors.map(\.description).joined(separator: "; "))
        } catch AddTripError.conflict {
            throw Abort(.conflict, reason: "trip \(trip.id) already exists with different data")
        }
    }
}

private func json<T: Encodable>(_ value: T, status: HTTPStatus = .ok) throws -> Response {
    let response = Response(status: status)
    try response.content.encode(value, as: .json)
    return response
}

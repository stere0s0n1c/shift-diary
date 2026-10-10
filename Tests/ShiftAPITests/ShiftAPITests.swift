import Foundation
import ShiftAPI
import ShiftCore
import XCTVapor

final class ShiftAPITests: XCTestCase {
    private var app: Application!
    private var store: TripStore!

    private let seed = """
    [
      {"id": "t1", "start": "2026-10-01T08:10:00+05:00", "end": "2026-10-01T08:32:00+05:00", "amount": 2400, "payment": "card", "commission": 360},
      {"id": "t2", "start": "2026-10-01T09:05:00+05:00", "end": "2026-10-01T09:20:00+05:00", "amount": 1500, "payment": "cash", "commission": 225}
    ]
    """

    override func setUp() async throws {
        let trips = try TripCoding.decoder().decode([Trip].self, from: Data(seed.utf8))
        store = TripStore(trips: trips, timeZone: TimeZone(secondsFromGMT: 5 * 3600)!)
        app = try await Application.make(.testing)
        try configure(app, store: store)
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
    }

    private func postTrip(_ body: String, afterResponse: @escaping (XCTHTTPResponse) async throws -> Void) async throws {
        try await app.test(.POST, "api/trips", beforeRequest: { req in
            req.headers.contentType = .json
            req.body = ByteBuffer(string: body)
        }, afterResponse: afterResponse)
    }

    private func report(_ day: String) async throws -> DayReport {
        var result: DayReport?
        try await app.test(.GET, "api/days/\(day)", afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            result = try TripCoding.decoder().decode(DayReport.self, from: Data(buffer: res.body))
        })
        return try XCTUnwrap(result)
    }

    func testDayReportHasSummaryAndTrips() async throws {
        let report = try await report("2026-10-01")
        XCTAssertEqual(report.trips.map(\.id), ["t1", "t2"])
        XCTAssertEqual(report.summary.revenue, 3900)
        XCTAssertEqual(report.summary.commission, 585)
        XCTAssertEqual(report.summary.net, 3315)
        XCTAssertEqual(report.summary.cash, 1500)
        XCTAssertEqual(report.summary.card, 2400)
        XCTAssertEqual(report.utcOffsetSeconds, 5 * 3600)
    }

    func testEmptyDayIsNotAnError() async throws {
        let report = try await report("2026-10-05")
        XCTAssertTrue(report.trips.isEmpty)
        XCTAssertEqual(report.summary.tripCount, 0)
    }

    func testBadDateIsRejected() async throws {
        try await app.test(.GET, "api/days/2026-13-01", afterResponse: { res async in
            XCTAssertEqual(res.status, .badRequest)
        })
    }

    func testDaysListsOnlyDaysWithTrips() async throws {
        try await app.test(.GET, "api/days", afterResponse: { res async throws in
            let list = try TripCoding.decoder().decode(DaysList.self, from: Data(buffer: res.body))
            XCTAssertEqual(list.days, [Day("2026-10-01")!])
        })
    }

    func testAddTripThenRetryDoesNotDuplicate() async throws {
        let body = """
        {"id": "t3", "start": "2026-10-01T10:00:00+05:00", "end": "2026-10-01T10:20:00+05:00", "amount": 1800, "payment": "cash", "commission": 270}
        """
        try await postTrip(body) { res in
            XCTAssertEqual(res.status, .created)
            let result = try TripCoding.decoder().decode(AddTripResult.self, from: Data(buffer: res.body))
            XCTAssertTrue(result.created)
        }
        // The client did not get the answer and sends the same trip again.
        try await postTrip(body) { res in
            XCTAssertEqual(res.status, .ok)
            let result = try TripCoding.decoder().decode(AddTripResult.self, from: Data(buffer: res.body))
            XCTAssertFalse(result.created)
        }

        let report = try await report("2026-10-01")
        XCTAssertEqual(report.trips.map(\.id), ["t1", "t2", "t3"])
        XCTAssertEqual(report.summary.revenue, 5700)
    }

    func testSameIDWithDifferentDataIsConflict() async throws {
        let body = """
        {"id": "t1", "start": "2026-10-01T08:10:00+05:00", "end": "2026-10-01T08:32:00+05:00", "amount": 9999, "payment": "card", "commission": 360}
        """
        try await postTrip(body) { res in
            XCTAssertEqual(res.status, .conflict)
        }
        let report = try await report("2026-10-01")
        XCTAssertEqual(report.summary.revenue, 3900)
    }

    func testValidationErrors() async throws {
        let zeroAmount = """
        {"id": "z", "start": "2026-10-01T10:00:00+05:00", "end": "2026-10-01T10:20:00+05:00", "amount": 0, "payment": "cash", "commission": 0}
        """
        let endBeforeStart = """
        {"id": "e", "start": "2026-10-01T10:20:00+05:00", "end": "2026-10-01T10:00:00+05:00", "amount": 500, "payment": "cash", "commission": 0}
        """
        for body in [zeroAmount, endBeforeStart] {
            try await postTrip(body) { res in
                XCTAssertEqual(res.status, .unprocessableEntity)
            }
        }
        let report = try await report("2026-10-01")
        XCTAssertEqual(report.trips.count, 2)
    }

    func testMalformedJSONIsBadRequest() async throws {
        let unknownPayment = """
        {"id": "p", "start": "2026-10-01T10:00:00+05:00", "end": "2026-10-01T10:20:00+05:00", "amount": 500, "payment": "crypto", "commission": 0}
        """
        try await postTrip(unknownPayment) { res in
            XCTAssertEqual(res.status, .badRequest)
        }
        try await postTrip("{not json") { res in
            XCTAssertEqual(res.status, .badRequest)
        }
    }
}

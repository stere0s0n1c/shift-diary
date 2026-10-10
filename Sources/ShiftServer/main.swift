import Foundation
import ShiftAPI
import ShiftCore
import Vapor

// Configuration comes from the environment:
//   SHIFT_DATA  path to the trips JSON file (default: data/trips.json)
//   SHIFT_TZ    driver's time zone (default: Asia/Almaty, UTC+5)
var env = try Environment.detect()
try LoggingSystem.bootstrap(from: &env)
let app = try await Application.make(env)

do {
    let timeZone = Environment.get("SHIFT_TZ").flatMap(TimeZone.init(identifier:))
        ?? TimeZone(identifier: "Asia/Almaty")
        ?? TimeZone(secondsFromGMT: 5 * 3600)!
    let dataURL = URL(fileURLWithPath: Environment.get("SHIFT_DATA") ?? "data/trips.json")
    let store = try TripStore.load(from: dataURL, timeZone: timeZone)
    app.logger.info("Loaded trips from \(dataURL.path), time zone \(timeZone.identifier)")

    try configure(app, store: store)
    try await app.execute()
} catch {
    app.logger.report(error: error)
    try? await app.asyncShutdown()
    throw error
}
try await app.asyncShutdown()

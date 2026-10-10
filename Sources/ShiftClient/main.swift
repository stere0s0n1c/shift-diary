import Foundation
import ShiftCore

// Console client for the shift diary.
//
//   swift run shift-diary [--server http://127.0.0.1:8080] [--date 2026-10-01]
//
// Commands: n — next day, p — previous day, YYYY-MM-DD — jump to a day, q — quit.

struct Options {
    var server = URL(string: "http://127.0.0.1:8080")!
    var date: Day?

    init(arguments: [String]) {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--server":
                if let value = iterator.next(), let url = URL(string: value) { server = url }
            case "--date":
                if let value = iterator.next() { date = Day(value) }
            default:
                break
            }
        }
    }
}

struct APIClient {
    let baseURL: URL
    let decoder = TripCoding.decoder()

    func days() async throws -> [Day] {
        try await get(DaysList.self, path: "api/days").days
    }

    func report(for day: Day) async throws -> DayReport {
        try await get(DayReport.self, path: "api/days/\(day)")
    }

    private func get<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: baseURL.appending(path: path))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(decoding: data, as: UTF8.self)
            throw ClientError.badResponse(body)
        }
        return try decoder.decode(T.self, from: data)
    }
}

enum ClientError: Error, CustomStringConvertible {
    case badResponse(String)

    var description: String {
        switch self {
        case .badResponse(let body): "server error: \(body)"
        }
    }
}

/// `3315` → `3 315 ₸`
func tenge(_ value: Int) -> String {
    let digits = String(abs(value))
    var groups: [Substring] = []
    var end = digits.endIndex
    while end > digits.startIndex {
        let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
        groups.insert(digits[start..<end], at: 0)
        end = start
    }
    return (value < 0 ? "−" : "") + groups.joined(separator: " ") + " ₸"
}

func render(_ report: DayReport) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: report.utcOffsetSeconds) ?? .current
    func hhmm(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour!, parts.minute!)
    }

    let d = report.date
    var lines = ["Дневник смен · \(String(format: "%02d.%02d.%04d", d.day, d.month, d.year))", ""]

    if report.trips.isEmpty {
        lines.append("Поездок нет")
    } else {
        for trip in report.trips {
            let payment = trip.payment == .cash ? "нал." : "карта"
            lines.append("\(hhmm(trip.start))–\(hhmm(trip.end))  \(payment.rightPadded(5))  \(tenge(trip.amount).leftPadded(14))")
        }
    }

    let s = report.summary
    let rows: [(String, String)] = [
        ("Поездок", "\(s.tripCount)"),
        ("Выручка", tenge(s.revenue)),
        ("Комиссия", tenge(-s.commission)),
        ("Наличные / карта", "\(tenge(s.cash)) / \(tenge(s.card))"),
        ("На руки", tenge(s.net)),
    ]
    lines.append("")
    lines += rows.map { label, value in label.rightPadded(18) + value.leftPadded(16) }
    return lines.joined(separator: "\n")
}

extension String {
    func leftPadded(_ width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }

    func rightPadded(_ width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}

let options = Options(arguments: CommandLine.arguments)
let client = APIClient(baseURL: options.server)

do {
    var day: Day
    if let requested = options.date {
        day = requested
    } else if let latest = try await client.days().last {
        day = latest
    } else {
        day = Day(containing: Date(), in: .current)
    }

    while true {
        print(render(try await client.report(for: day)))
        print("\n[n] след. день  [p] пред. день  [YYYY-MM-DD] перейти  [q] выход")
        guard let input = readLine()?.trimmingCharacters(in: .whitespaces) else { break }
        switch input {
        case "q": exit(0)
        case "n": day = day.adding(days: 1)
        case "p": day = day.adding(days: -1)
        default:
            if let jump = Day(input) { day = jump } else { print("Не понял команду: \(input)") }
        }
        print("")
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

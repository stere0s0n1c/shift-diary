import Foundation

/// JSON settings shared by the server, the client and the data file.
public enum TripCoding {
    /// Accepts ISO 8601 with any offset: `2026-10-01T08:10:00+05:00` or `...Z`.
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Writes dates in the driver's time zone, so the output looks like the input data.
    public static func encoder(timeZone: TimeZone, pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = timeZone
            formatter.formatOptions = [.withInternetDateTime]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }
}

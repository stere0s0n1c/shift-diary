import Foundation

public enum PaymentMethod: String, Codable, Sendable, CaseIterable {
    case cash
    case card
}

/// One ride. Money is stored in whole tenge, as in the source data.
public struct Trip: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let start: Date
    public let end: Date
    public let amount: Int
    public let payment: PaymentMethod
    public let commission: Int

    public init(id: String, start: Date, end: Date, amount: Int, payment: PaymentMethod, commission: Int) {
        self.id = id
        self.start = start
        self.end = end
        self.amount = amount
        self.payment = payment
        self.commission = commission
    }
}

public enum TripValidationError: Error, Sendable, Equatable, CustomStringConvertible {
    case emptyID
    case nonPositiveAmount
    case negativeCommission
    case commissionExceedsAmount
    case endNotAfterStart

    public var description: String {
        switch self {
        case .emptyID: "id must not be empty"
        case .nonPositiveAmount: "amount must be greater than 0"
        case .negativeCommission: "commission must not be negative"
        case .commissionExceedsAmount: "commission must not exceed amount"
        case .endNotAfterStart: "end must be later than start"
        }
    }
}

extension Trip {
    /// All problems at once, so a client can show every error in one response.
    public var validationErrors: [TripValidationError] {
        var errors: [TripValidationError] = []
        if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append(.emptyID) }
        if amount <= 0 { errors.append(.nonPositiveAmount) }
        if commission < 0 { errors.append(.negativeCommission) }
        if amount > 0, commission > amount { errors.append(.commissionExceedsAmount) }
        if end <= start { errors.append(.endNotAfterStart) }
        return errors
    }
}

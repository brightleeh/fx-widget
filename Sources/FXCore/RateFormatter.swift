import Foundation

public struct FormattedRate: Equatable, Sendable {
    public let text: String
    public let fractionDigits: Int
    public let usesScientificNotation: Bool

    public init(text: String, fractionDigits: Int, usesScientificNotation: Bool) {
        self.text = text
        self.fractionDigits = fractionDigits
        self.usesScientificNotation = usesScientificNotation
    }
}

public struct RateFormatter: Sendable {
    private let localeIdentifier: String

    public init(locale: Locale = .current) {
        localeIdentifier = locale.identifier
    }

    public func rate(_ value: Decimal) -> FormattedRate {
        let absolute = abs(value)
        let band: (minimum: Int, maximum: Int)
        switch absolute {
        case 100...:
            band = (2, 2)
        case 1..<100:
            band = (2, 2)
        case Decimal(string: "0.01")!..<1:
            band = (2, 4)
        case Decimal(string: "0.0001")!..<Decimal(string: "0.01")!:
            band = (2, 6)
        default:
            band = (2, 8)
        }

        let guardedMaximum = precisionThatDoesNotRenderNonzeroAsZero(
            value,
            startingAt: band.maximum,
            limit: 12
        )
        guard rounded(value, scale: guardedMaximum) != 0 || value == 0 else {
            return FormattedRate(
                text: scientific(value),
                fractionDigits: 12,
                usesScientificNotation: true
            )
        }

        let digits: Int
        if band.minimum == band.maximum {
            digits = band.minimum
        } else {
            digits = effectivePrecision(
                value,
                minimum: band.minimum,
                maximum: guardedMaximum
            )
        }

        return FormattedRate(
            text: decimal(value, minimumFractionDigits: digits, maximumFractionDigits: digits),
            fractionDigits: digits,
            usesScientificNotation: false
        )
    }

    public func absoluteChange(_ value: Decimal, rateFractionDigits: Int) -> String {
        let magnitude = abs(value)
        let digits = precisionThatDoesNotRenderNonzeroAsZero(
            magnitude,
            startingAt: min(max(rateFractionDigits, 0), 12),
            limit: 12
        )

        guard rounded(magnitude, scale: digits) != 0 || magnitude == 0 else {
            return scientific(magnitude)
        }
        return decimal(magnitude, minimumFractionDigits: digits, maximumFractionDigits: digits)
    }

    public func percentage(_ value: Decimal) -> String {
        let digits = percentagePrecision(value)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        formatter.positivePrefix = value > 0 ? "+" : ""

        let ratio = value / 100
        return formatter.string(from: NSDecimalNumber(decimal: ratio))
            ?? "\(NSDecimalNumber(decimal: value).stringValue)%"
    }

    private func percentagePrecision(_ value: Decimal) -> Int {
        guard value != 0, rounded(value, scale: 2) == 0 else { return 2 }
        for digits in 3...4 where rounded(value, scale: digits) != 0 {
            return digits
        }
        return 4
    }

    private func effectivePrecision(
        _ value: Decimal,
        minimum: Int,
        maximum: Int
    ) -> Int {
        let target = rounded(value, scale: maximum)
        for digits in minimum...maximum where rounded(value, scale: digits) == target {
            return digits
        }
        return maximum
    }

    private func precisionThatDoesNotRenderNonzeroAsZero(
        _ value: Decimal,
        startingAt: Int,
        limit: Int
    ) -> Int {
        guard value != 0 else { return startingAt }
        for digits in startingAt...limit where rounded(value, scale: digits) != 0 {
            return digits
        }
        return limit
    }

    private func decimal(
        _ value: Decimal,
        minimumFractionDigits: Int,
        maximumFractionDigits: Int
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.roundingMode = .halfUp
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }

    private func scientific(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.numberStyle = .scientific
        formatter.usesSignificantDigits = true
        formatter.minimumSignificantDigits = 1
        formatter.maximumSignificantDigits = 12
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }

    private func rounded(_ value: Decimal, scale: Int) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return result
    }

    private func abs(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }
}

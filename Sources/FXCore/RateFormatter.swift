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

    /// Maximum fraction digits the board will ever render in fixed notation.
    /// Below this magnitude a value switches to scientific notation instead of
    /// growing more digits: this is a glanceable board, not a trading terminal,
    /// and six or more fraction digits cost column width without informing the
    /// reader (D-020).
    public static let maximumFractionDigits = 4
    static let scientificThreshold = Decimal(string: "0.0001")!

    public func rate(_ value: Decimal) -> FormattedRate {
        let absolute = abs(value)

        // Anything smaller than the fixed-notation floor becomes scientific
        // rather than a row of leading zeros.
        guard absolute >= Self.scientificThreshold || value == 0 else {
            return FormattedRate(
                text: scientific(value),
                fractionDigits: Self.maximumFractionDigits,
                usesScientificNotation: true
            )
        }

        let band: (minimum: Int, maximum: Int)
        switch absolute {
        case 1...:
            band = (2, 2)
        case Decimal(string: "0.01")!..<1:
            band = (2, 4)
        default:
            // 0.0001 ..< 0.01 — fixed 4 digits, e.g. 0.006275 -> 0.0063.
            band = (4, 4)
        }

        let digits: Int
        if band.minimum == band.maximum {
            digits = band.minimum
        } else {
            digits = effectivePrecision(
                value,
                minimum: band.minimum,
                maximum: band.maximum
            )
        }

        return FormattedRate(
            text: decimal(value, minimumFractionDigits: digits, maximumFractionDigits: digits),
            fractionDigits: digits,
            usesScientificNotation: false
        )
    }

    /// Absolute change shares its row's precision. When a nonzero change would
    /// round away at that precision it switches to scientific notation rather
    /// than widening the column, which previously produced values that the
    /// layout had to truncate to `0.0000…`.
    public func absoluteChange(_ value: Decimal, rateFractionDigits: Int) -> String {
        let magnitude = abs(value)
        let start = min(max(rateFractionDigits, 0), Self.maximumFractionDigits)

        // Start at the row's precision and widen only as far as the board's
        // fixed-notation floor. A 1.15 row whose change is 0.0004 still shows
        // 0.0004; only changes below the floor become scientific.
        let digits = precisionThatDoesNotRenderNonzeroAsZero(
            magnitude,
            startingAt: start,
            limit: Self.maximumFractionDigits
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
        // Two significant digits keep the column narrow enough that the layout
        // never has to truncate it. `4.13371916…` is strictly worse than `4.1E-4`.
        formatter.usesSignificantDigits = true
        formatter.minimumSignificantDigits = 1
        formatter.maximumSignificantDigits = 2
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

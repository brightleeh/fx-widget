import Foundation
import Testing
@testable import FXCore

struct RateFormatterTests {
    private let formatter = RateFormatter(locale: Locale(identifier: "en_US"))

    @Test func appliesAdaptiveRateBands() {
        #expect(formatter.rate(Decimal(string: "1418.5")!).text == "1,418.50")
        #expect(formatter.rate(Decimal(string: "8.96")!).text == "8.96")
        #expect(formatter.rate(Decimal(string: "8.905")!).text == "8.91")
        #expect(formatter.rate(Decimal(string: "1.1645")!).text == "1.16")
        #expect(formatter.rate(Decimal(string: "0.7100")!).text == "0.71")
        #expect(formatter.rate(Decimal(string: "0.00634")!).text == "0.00634")
    }

    @Test func nonzeroRateNeverBecomesZero() {
        let expanded = formatter.rate(Decimal(string: "0.000000000123")!)
        #expect(expanded.text == "0.0000000001")
        #expect(expanded.fractionDigits == 10)

        let scientific = formatter.rate(Decimal(string: "0.0000000000000123")!)
        #expect(scientific.usesScientificNotation)
        #expect(scientific.text.contains("E"))
        #expect(scientific.text != "0")
    }

    @Test func absoluteChangeStartsWithRowsEffectivePrecision() {
        let rate = formatter.rate(Decimal(string: "8.905")!)
        #expect(rate.fractionDigits == 2)
        #expect(formatter.absoluteChange(Decimal(string: "-0.036")!, rateFractionDigits: rate.fractionDigits) == "0.04")
    }

    @Test func smallNonzeroPercentageExpandsOnlyAsNeeded() {
        #expect(formatter.percentage(Decimal(string: "0.61")!) == "+0.61%")
        #expect(formatter.percentage(Decimal(string: "-0.004")!) == "-0.004%")
        #expect(formatter.percentage(0) == "0.00%")
    }

    @Test func separatorsFollowLocale() {
        let german = RateFormatter(locale: Locale(identifier: "de_DE"))
        #expect(german.rate(Decimal(string: "1418.5")!).text == "1.418,50")
    }
}

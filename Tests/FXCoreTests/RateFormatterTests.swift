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
        // 0.0001 ..< 0.01 renders exactly four digits: a glanceable board does
        // not benefit from 0.006275 over 0.0063.
        #expect(formatter.rate(Decimal(string: "0.00634")!).text == "0.0063")
        #expect(formatter.rate(Decimal(string: "0.006275")!).text == "0.0063")
        #expect(formatter.rate(Decimal(string: "0.1484")!).text == "0.1484")
    }

    @Test func belowTheFixedFloorSwitchesToScientificRatherThanMoreDigits() {
        // Vietnamese dong against USD sits here.
        let vnd = formatter.rate(Decimal(string: "0.000038")!)
        #expect(vnd.usesScientificNotation)
        #expect(vnd.text.contains("E"))
        #expect(vnd.text != "0")

        let tiny = formatter.rate(Decimal(string: "0.000000000123")!)
        #expect(tiny.usesScientificNotation)
        #expect(tiny.text != "0")

        // The floor itself still renders in fixed notation.
        #expect(!formatter.rate(Decimal(string: "0.0001")!).usesScientificNotation)
    }

    @Test func changeWidensToTheBoardFloorBeforeGoingScientific() {
        // A 1.15 row (2 digits) whose change is 0.0004 must still read 0.0004.
        let rate = formatter.rate(Decimal(string: "1.1545")!)
        #expect(rate.fractionDigits == 2)
        #expect(
            formatter.absoluteChange(
                Decimal(string: "0.000413371916")!,
                rateFractionDigits: rate.fractionDigits
            ) == "0.0004"
        )
    }

    @Test func scientificNotationStaysNarrowEnoughToRender() {
        // Long mantissas were being truncated to "4.13371916…" by the layout.
        let text = formatter.absoluteChange(
            Decimal(string: "0.00000393744142")!,
            rateFractionDigits: 4
        )
        #expect(text.contains("E"))
        #expect(text.count <= 8)
    }

    @Test func changeTooSmallForItsRowUsesScientificNotation() {
        let rate = formatter.rate(Decimal(string: "0.006275")!)
        #expect(rate.fractionDigits == 4)

        // Previously this widened the column until the layout truncated it.
        let change = formatter.absoluteChange(
            Decimal(string: "0.0000042")!,
            rateFractionDigits: rate.fractionDigits
        )
        #expect(change.contains("E"))
        #expect(change != "0.0000")
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

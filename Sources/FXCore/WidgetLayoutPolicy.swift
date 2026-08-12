import Foundation

/// Presentation-only family categories. Provider and rate-domain code never depend on them.
public enum WidgetFamilyCategory: String, CaseIterable, Codable, Sendable {
    case medium
    case large
    case extraLarge
}

public struct WidgetLayoutMetrics: Equatable, Sendable {
    public let contentHeight: Double
    public let headerHeight: Double
    public let footerHeight: Double
    public let sectionSpacing: Double
    public let rowHeight: Double
    public let rowSpacing: Double

    public var availableRowsHeight: Double {
        max(
            0,
            contentHeight
                - headerHeight
                - footerHeight
                - (sectionSpacing * 2)
        )
    }

    public var rowsPerColumn: Int {
        guard rowHeight > 0 else { return 0 }
        return max(0, Int((availableRowsHeight + rowSpacing) / (rowHeight + rowSpacing)))
    }

    public var requiredHeight: Double {
        guard rowsPerColumn > 0 else {
            return headerHeight + footerHeight + (sectionSpacing * 2)
        }
        return headerHeight
            + footerHeight
            + (sectionSpacing * 2)
            + (Double(rowsPerColumn) * rowHeight)
            + (Double(rowsPerColumn - 1) * rowSpacing)
    }
}

public struct WidgetLayoutResult: Equatable, Sendable {
    public let columnCount: Int
    public let validatedSelectionCapacity: Int
    public let visibleCurrencies: [CurrencyCode]
    public let overflowCount: Int
    public let metrics: WidgetLayoutMetrics

    /// Currency order is vertical within each column. The second column starts
    /// only after the first column reaches the family's ten-row capacity.
    public var columnMajorColumns: [[CurrencyCode]] {
        visibleCurrencies.chunked(maxCount: metrics.rowsPerColumn)
    }
}

public enum WidgetLayoutPolicy {
    public static func resolve(
        family: WidgetFamilyCategory,
        selectedCurrencies: [CurrencyCode],
        availableContentHeight: Double? = nil
    ) -> WidgetLayoutResult {
        let columnCount = fixedColumnCount(for: family)
        let metrics = metrics(
            family: family,
            availableContentHeight: availableContentHeight
        )
        let capacity = metrics.rowsPerColumn * columnCount
        let visible = Array(selectedCurrencies.prefix(capacity))

        return WidgetLayoutResult(
            columnCount: columnCount,
            validatedSelectionCapacity: capacity,
            visibleCurrencies: visible,
            overflowCount: max(0, selectedCurrencies.count - visible.count),
            metrics: metrics
        )
    }

    public static func capacity(
        family: WidgetFamilyCategory,
        availableContentHeight: Double? = nil
    ) -> Int {
        resolve(
            family: family,
            selectedCurrencies: [],
            availableContentHeight: availableContentHeight
        ).validatedSelectionCapacity
    }

    public static func fixedColumnCount(for family: WidgetFamilyCategory) -> Int {
        switch family {
        case .medium, .large: 1
        case .extraLarge: 2
        }
    }

    private static func metrics(
        family: WidgetFamilyCategory,
        availableContentHeight: Double?
    ) -> WidgetLayoutMetrics {
        let validatedContentHeight: Double = switch family {
        // GeometryReader receives WidgetKit's already-inset content area.
        case .medium: 132
        case .large, .extraLarge: 310
        }
        let contentHeight: Double
        if let availableContentHeight, availableContentHeight > 0 {
            contentHeight = min(availableContentHeight, validatedContentHeight)
        } else {
            contentHeight = validatedContentHeight
        }

        return WidgetLayoutMetrics(
            contentHeight: contentHeight,
            headerHeight: 22,
            footerHeight: 17,
            sectionSpacing: 8,
            rowHeight: 22,
            rowSpacing: 3
        )
    }
}

private extension Array {
    func chunked(maxCount: Int) -> [[Element]] {
        guard maxCount > 0 else { return [] }
        return stride(from: 0, to: count, by: maxCount).map { start in
            Array(self[start..<Swift.min(start + maxCount, count)])
        }
    }
}

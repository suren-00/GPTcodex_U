import Foundation

enum TokenFormatter {
    private struct Unit {
        let divisor: Double
        let suffix: String
    }

    private static let units = [
        Unit(divisor: 10_000, suffix: "万"),
        Unit(divisor: 100_000_000, suffix: "亿")
    ]

    static func format(_ value: Int64?) -> String {
        guard let value else { return "--" }

        let magnitude = abs(Double(value))
        guard magnitude >= units[0].divisor else { return "\(value)" }

        var unitIndex = units.lastIndex { magnitude >= $0.divisor } ?? 0
        var roundedValue = roundedScaledValue(value, unit: units[unitIndex])

        // Promote values that round across the 10,000x Chinese-unit boundary
        // instead of rendering awkward labels such as `10000万`.
        if abs(roundedValue) >= 10_000, unitIndex < units.count - 1 {
            unitIndex += 1
            roundedValue = roundedScaledValue(value, unit: units[unitIndex])
        }

        let number: String
        if roundedValue.rounded() == roundedValue {
            number = String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), roundedValue)
        } else {
            number = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), roundedValue)
        }
        return number + units[unitIndex].suffix
    }

    private static func roundedScaledValue(_ value: Int64, unit: Unit) -> Double {
        let scaled = Double(value) / unit.divisor
        // Four-digit values are already precise enough for a compact status
        // item and remain much easier to scan without a trailing decimal.
        if abs(scaled) >= 1_000 {
            return scaled.rounded()
        }
        return (scaled * 10).rounded() / 10
    }
}

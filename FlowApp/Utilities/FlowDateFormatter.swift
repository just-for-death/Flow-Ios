import Foundation

// MARK: - FlowDateFormatter
enum FlowDateFormatter {

    static func format(date: Date, mode: String? = nil, style: String? = nil) -> String {
        let displayMode = mode ?? PlayerPreferences.shared.dateDisplayMode
        let formatStyle = style ?? PlayerPreferences.shared.dateFormatStyle
        if displayMode == "ABSOLUTE" {
            return absolute(date, style: formatStyle)
        }
        return relative(date)
    }

    static func formatPublished(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "" }
        if PlayerPreferences.shared.dateDisplayMode == "ABSOLUTE" { return text }
        return text
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func absolute(_ date: Date, style: String) -> String {
        let formatter = DateFormatter()
        switch style {
        case "SHORT": formatter.dateStyle = .short
        case "LONG": formatter.dateStyle = .long
        default: formatter.dateStyle = .medium
        }
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

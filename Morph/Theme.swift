import SwiftUI
import UIKit

extension Color {
    /// Astra picks icon colours as hex, so the grid has to read them.
    init(hex: String) {
        var value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        let scanned = UInt64(value, radix: 16) ?? 0x2C2C2E
        self.init(
            .sRGB,
            red: Double((scanned >> 16) & 0xFF) / 255,
            green: Double((scanned >> 8) & 0xFF) / 255,
            blue: Double(scanned & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// A quiet instrument. Warm darks rather than pure black, ivory rather than
/// white, and one accent that only ever means "live right now".
enum Theme {
    static let background = Color(red: 0.082, green: 0.078, blue: 0.071)
    static let surface = Color(red: 0.122, green: 0.116, blue: 0.106)
    static let raised = Color(red: 0.165, green: 0.157, blue: 0.144)
    static let hairline = Color(red: 0.245, green: 0.235, blue: 0.215)

    static let ink = Color(red: 0.953, green: 0.933, blue: 0.894)
    static let dim = Color(red: 0.612, green: 0.592, blue: 0.553)
    static let faint = Color(red: 0.40, green: 0.385, blue: 0.36)

    /// Building, steering, anything happening this second.
    static let accent = Color(red: 1.0, green: 0.478, blue: 0.239)
    static let accentSoft = Color(red: 1.0, green: 0.478, blue: 0.239).opacity(0.14)
    /// Steering is the same moment as building, so it wears the same colour.
    static let steer = accent

    /// Finished work. Muted on purpose; done should feel settled, not loud.
    static let ok = Color(red: 0.64, green: 0.74, blue: 0.58)
    static let warn = Color(red: 0.93, green: 0.70, blue: 0.42)
}

extension Optional where Wrapped == String {
    /// Astra picks the SF Symbol. A name it invented would draw nothing at all,
    /// so anything UIKit cannot resolve falls back to a generic tile.
    var validSymbol: String {
        guard
            let name = self?.trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty,
            UIImage(systemName: name) != nil
        else { return "square.grid.2x2.fill" }
        return name
    }
}

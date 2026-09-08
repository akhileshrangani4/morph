import SwiftUI

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

enum Theme {
    static let background = Color.black
    static let surface = Color(white: 0.09)
    static let hairline = Color(white: 0.22)
    static let dim = Color(white: 0.55)
    static let accent = Color(red: 0.45, green: 0.78, blue: 1.0)
    /// Steering gets its own colour so an interrupt is unmistakable on stage.
    static let steer = Color(red: 1.0, green: 0.72, blue: 0.30)
}

import UIKit

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

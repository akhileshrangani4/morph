import Foundation

/// One tile on Morph's home grid. Mirrors a real Charming app.
struct Tile: Identifiable, Codable, Equatable {
    var id: String              // Charming app uuid
    var name: String
    var emoji: String           // the app's own icon on Charming
    var symbol: String          // SF Symbol drawn on the phone grid
    var bg: String
    var isSettling: Bool        // true while Astra is still working on it

    // Tiles written before the grid moved to SF Symbols have no symbol.
    enum CodingKeys: String, CodingKey { case id, name, emoji, symbol, bg, isSettling }

    init(id: String, name: String, emoji: String, symbol: String, bg: String, isSettling: Bool) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.symbol = symbol
        self.bg = bg
        self.isSettling = isSettling
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji) ?? "✨"
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "square.grid.2x2.fill"
        bg = try container.decode(String.self, forKey: .bg)
        isSettling = try container.decode(Bool.self, forKey: .isSettling)
    }
}

/// A line in the build strip. The strip is a window onto Astra's real work:
/// every entry corresponds to a model event or a tool Morph actually ran.
struct BuildEvent: Identifiable, Equatable {
    enum Kind: Equatable {
        case reasoning, tool, toolDone, steer, done, error
    }
    let id = UUID()
    var kind: Kind
    var text: String
    var detail: String?

    var glyph: String {
        switch kind {
        case .reasoning: return "sparkles"
        case .tool: return "hammer"
        case .toolDone: return "checkmark"
        case .steer: return "arrow.triangle.branch"
        case .done: return "checkmark.seal.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

/// Home-grid persistence. Small enough that UserDefaults is the right call.
final class TileStore: ObservableObject {
    @Published var tiles: [Tile] = [] {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "tiles"),
           let decoded = try? JSONDecoder().decode([Tile].self, from: data) {
            tiles = decoded
        }
    }

    func upsert(_ tile: Tile) {
        if let i = tiles.firstIndex(where: { $0.id == tile.id }) {
            tiles[i] = tile
        } else {
            tiles.append(tile)
        }
    }

    /// Swaps a placeholder tile for the real app once Charming returns an id.
    func settle(placeholderID: String, into tile: Tile) {
        if let i = tiles.firstIndex(where: { $0.id == placeholderID }) {
            tiles[i] = tile
        } else {
            upsert(tile)
        }
    }

    func remove(_ id: String) {
        tiles.removeAll { $0.id == id }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(tiles) {
            UserDefaults.standard.set(data, forKey: "tiles")
        }
    }
}

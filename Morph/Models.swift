import Foundation

/// One tile on Morph's home grid. Mirrors a real Charming app.
struct Tile: Identifiable, Codable, Equatable {
    var id: String              // Charming app uuid
    var name: String
    var emoji: String
    var bg: String
    var isSettling: Bool        // true while Astra is still working on it

    static func placeholder(name: String) -> Tile {
        Tile(id: "pending-" + UUID().uuidString, name: name, emoji: "✨", bg: "#1c1c1e", isSettling: true)
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

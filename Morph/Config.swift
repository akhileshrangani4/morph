import Foundation

enum Config {
    /// Charming's public API. Every call Morph makes goes through this surface;
    /// nothing here depends on Charming's private source.
    static let charmingBaseURL = URL(string: "https://charm.ing")!

    /// GPT-6 Astra over the Responses WebSocket transport. Mid-turn steering
    /// exists only on this transport, so Morph never uses plain HTTP for a turn.
    static let astraWebSocketURL = URL(string: "wss://api.openai.com/v1/responses")!

    static let model = "gpt-6-astra"
}

/// Keys live in UserDefaults so a fresh clone runs without a rebuild and no
/// secret is ever near the repo. A shipping app would use the Keychain.
final class Credentials: ObservableObject {
    static let shared = Credentials()

    @Published var openAIKey: String {
        didSet { UserDefaults.standard.set(openAIKey, forKey: "openAIKey") }
    }
    @Published var charmingToken: String {
        didSet { UserDefaults.standard.set(charmingToken, forKey: "charmingToken") }
    }

    var isConfigured: Bool { !openAIKey.isEmpty && !charmingToken.isEmpty }

    private init() {
        openAIKey = UserDefaults.standard.string(forKey: "openAIKey") ?? ""
        charmingToken = UserDefaults.standard.string(forKey: "charmingToken") ?? ""
    }
}

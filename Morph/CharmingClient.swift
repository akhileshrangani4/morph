import Foundation

struct CharmingError: LocalizedError {
    let status: Int
    let body: String
    var errorDescription: String? { "Charming \(status): \(body)" }
}

/// Thin client over Charming's public HTTP API. Astra's tools are one-to-one
/// with the methods here, so the model drives the platform directly.
struct CharmingClient {
    var token: String

    private func request(
        _ method: String,
        _ path: String,
        body: Any? = nil
    ) async throws -> Any {
        var req = URLRequest(url: Config.charmingBaseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        req.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw CharmingError(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        if data.isEmpty { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    }

    /// Charming publishes its own authoring spec. Morph feeds this to Astra as
    /// the system prompt rather than a hand-written guess at the contract.
    func authoringGuide() async throws -> String {
        let url = Config.charmingBaseURL.appendingPathComponent("api/prompts/charming-app-guide")
        let (data, _) = try await URLSession.shared.data(from: url)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func createApp(module: String, ui: String?, styles: String?, description: String?) async throws -> [String: Any] {
        var body: [String: Any] = ["module": module]
        if let ui { body["ui"] = ui }
        if let styles { body["styles"] = styles }
        if let description { body["description"] = description }
        return try await request("POST", "app", body: body) as? [String: Any] ?? [:]
    }

    func updateApp(id: String, module: String, ui: String?, styles: String?) async throws -> [String: Any] {
        var body: [String: Any] = ["module": module]
        if let ui { body["ui"] = ui }
        if let styles { body["styles"] = styles }
        return try await request("PUT", "app/\(id)", body: body) as? [String: Any] ?? [:]
    }

    /// Exact-string edits against the persisted source. Cheaper and faster than
    /// regenerating a whole app when the user asks for one more feature.
    func patchSource(id: String, edits: [[String: Any]]) async throws -> [String: Any] {
        try await request("PATCH", "app/\(id)/source", body: ["edits": edits]) as? [String: Any] ?? [:]
    }

    func getSource(id: String) async throws -> [String: Any] {
        try await request("GET", "app/\(id)/source") as? [String: Any] ?? [:]
    }

    func setIcon(id: String, emoji: String, bg: String) async throws -> [String: Any] {
        try await request("PUT", "app/\(id)/icon", body: ["emoji": emoji, "bg": bg]) as? [String: Any] ?? [:]
    }

    /// Calls a route the generated app declared. This is how Astra answers
    /// questions about the data inside an app it built earlier.
    func callOperation(id: String, operation: String, payload: [String: Any]) async throws -> Any {
        try await request("POST", "app/\(id)/api/\(operation)", body: payload)
    }

    func listApps() async throws -> Any {
        try await request("GET", "app")
    }

    /// The hosted app URL for a webview. `canonical=uuid` stops a claimed app
    /// from redirecting to its friendly URL, which would drop the auth header.
    func webViewRequest(appID: String) -> URLRequest {
        var req = URLRequest(url: Config.charmingBaseURL
            .appendingPathComponent("app/\(appID)")
            .appending(queryItems: [URLQueryItem(name: "canonical", value: "uuid")]))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }
}

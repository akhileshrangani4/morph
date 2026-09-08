import Foundation

/// The engine. One WebSocket to the Responses API per session.
///
/// Everything runs over the WebSocket transport rather than plain HTTP because
/// mid-turn steering exists only there: the user can talk over a build that is
/// already in flight and GPT-6 Astra keeps the work it has finished.
@MainActor
final class AstraSession: ObservableObject {
    enum Phase: Equatable { case idle, working, done, failed(String) }

    @Published var events: [BuildEvent] = []
    @Published var phase: Phase = .idle
    /// True while a response is open, which is the window where steering works.
    @Published var canSteer = false

    private let store: TileStore
    private var ws: URLSessionWebSocketTask?
    private var instructions: String?
    private var currentResponseID: String?
    private var reasoningLineID: UUID?
    private var reasoningBuffer = ""
    /// Maps the tile_id Astra was handed to the tile sitting on the grid.
    private var tiles: [String: String] = [:]

    init(store: TileStore) {
        self.store = store
    }

    // MARK: - Turns

    func run(prompt: String) async {
        events.removeAll()
        phase = .working
        reasoningLineID = nil
        reasoningBuffer = ""

        do {
            let instr = try await loadInstructions()
            try connectIfNeeded()
            push(.reasoning, "Astra is listening", detail: "effort: \(effort(for: prompt))")
            try await send([
                "type": "response.create",
                "model": Config.model,
                "store": true,
                "reasoning": ["effort": effort(for: prompt)],
                "instructions": instr,
                "tools": AstraTools.all(),
                "input": prompt,
            ])
            canSteer = true
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Mid-turn steering. Does not cancel anything: the server keeps completed
    /// work and folds this into the continuation.
    func steer(_ text: String) {
        guard let id = currentResponseID else { return }
        push(.steer, "\u{201C}\(text)\u{201D}", detail: "steering a build already in flight")
        Task {
            do {
                try await send([
                    "type": "response.steer",
                    "previous_response_id": id,
                    "input": text,
                ])
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    /// Authoring a new app is worth real reasoning. Opening or querying one is
    /// not, and paying for it would show as lag on stage.
    private func effort(for prompt: String) -> String {
        let p = prompt.lowercased()
        if store.tiles.isEmpty { return "high" }
        if p.hasPrefix("open ") || p.contains("how many") || p.contains("what did") { return "low" }
        if p.contains("add ") || p.contains("change ") || p.contains("make it ") { return "medium" }
        return "high"
    }

    // MARK: - Transport

    private func connectIfNeeded() throws {
        if let ws, ws.closeCode == .invalid { return }
        let key = Credentials.shared.openAIKey
        guard !key.isEmpty else { throw CharmingError(status: 0, body: "No OpenAI API key set") }

        var req = URLRequest(url: Config.astraWebSocketURL)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.webSocketTask(with: req)
        task.resume()
        ws = task
        pump()
    }

    private func pump() {
        Task { [weak self] in
            while true {
                guard let self, let ws = self.ws else { return }
                do {
                    let message = try await ws.receive()
                    self.handle(message)
                } catch {
                    if self.phase == .working { self.fail(error.localizedDescription) }
                    self.ws = nil
                    return
                }
            }
        }
    }

    private func send(_ payload: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else { return }
        try await ws?.send(.string(text))
    }

    // MARK: - Events

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
        @unknown default: return
        }
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
            let type = object["type"] as? String
        else { return }

        switch type {
        case "response.created":
            if let response = object["response"] as? [String: Any], let id = response["id"] as? String {
                currentResponseID = id
            }

        case "response.output_item.added":
            if let item = object["item"] as? [String: Any],
               item["type"] as? String == "function_call",
               let name = item["name"] as? String {
                flushReasoning()
                push(.tool, label(for: name))
            }

        case "response.reasoning_summary_text.delta", "response.output_text.delta":
            if let delta = object["delta"] as? String { appendReasoning(delta) }

        case "response.steer.accepted":
            push(.steer, "Astra took the change", detail: "finished work kept")

        case "response.steer.pending":
            push(.steer, "change queued", detail: "waiting on a tool already running")

        case "response.steer.failed":
            push(.error, "steering rejected", detail: describeError(object))

        case "response.completed":
            flushReasoning()
            handleCompleted(object)

        case "response.incomplete":
            flushReasoning()
            handleIncomplete(object)

        case "error":
            fail(describeError(object))

        default:
            break
        }
    }

    private func handleCompleted(_ object: [String: Any]) {
        guard let response = object["response"] as? [String: Any] else { return }
        let id = response["id"] as? String ?? currentResponseID
        currentResponseID = id
        let output = response["output"] as? [[String: Any]] ?? []
        let calls = output.filter { $0["type"] as? String == "function_call" }

        if calls.isEmpty {
            let spoken = output
                .compactMap { $0["content"] as? [[String: Any]] }
                .flatMap { $0 }
                .compactMap { $0["text"] as? String }
                .joined(separator: " ")
            canSteer = false
            phase = .done
            push(.done, spoken.isEmpty ? "Done" : spoken)
            return
        }
        guard let id else { return }
        execute(calls: calls, previousResponseID: id)
    }

    /// A steered response stops early on purpose. Continuing it is what lets
    /// the queued change take effect.
    private func handleIncomplete(_ object: [String: Any]) {
        let response = object["response"] as? [String: Any]
        let reason = (response?["incomplete_details"] as? [String: Any])?["reason"] as? String
        guard let id = response?["id"] as? String ?? currentResponseID else { return }
        currentResponseID = id
        guard reason == "steered" else {
            push(.error, "Astra stopped early", detail: reason ?? "unknown reason")
            phase = .failed(reason ?? "incomplete")
            canSteer = false
            return
        }
        push(.reasoning, "picking up with the change")
        Task {
            do {
                try await send([
                    "type": "response.create",
                    "model": Config.model,
                    "store": true,
                    "previous_response_id": id,
                    "tools": AstraTools.all(),
                    "input": "Continue, applying the change I just sent. Keep what you already finished.",
                ])
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    private func execute(calls: [[String: Any]], previousResponseID: String) {
        Task {
            var outputs: [[String: Any]] = []
            for call in calls {
                let name = call["name"] as? String ?? ""
                let callID = call["call_id"] as? String ?? ""
                let raw = call["arguments"] as? String ?? "{}"
                let args = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]

                let result = await runTool(name: name, args: args)
                markToolDone(name: name, result: result)
                outputs.append([
                    "type": "function_call_output",
                    "call_id": callID,
                    "output": result,
                ])
            }
            do {
                try await send([
                    "type": "response.create",
                    "model": Config.model,
                    "store": true,
                    "previous_response_id": previousResponseID,
                    "tools": AstraTools.all(),
                    "input": outputs,
                ])
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    // MARK: - Tools

    private func runTool(name: String, args: [String: Any]) async -> String {
        let client = CharmingClient(token: Credentials.shared.charmingToken)
        do {
            switch name {
            case "place_icon":
                let tile = Tile(
                    id: "pending-" + UUID().uuidString,
                    name: args["name"] as? String ?? "New app",
                    emoji: args["emoji"] as? String ?? "✨",
                    bg: args["bg"] as? String ?? "#2c2c2e",
                    isSettling: true
                )
                store.upsert(tile)
                tiles[tile.id] = tile.id
                return json(["tile_id": tile.id])

            case "create_app":
                let created = try await client.createApp(
                    module: args["module"] as? String ?? "",
                    ui: args["ui"] as? String,
                    styles: args["styles"] as? String,
                    description: args["description"] as? String
                )
                guard let appID = created["id"] as? String else {
                    return json(["error": "create returned no id"])
                }
                let tileID = args["tile_id"] as? String
                let existing = store.tiles.first { $0.id == tileID }
                let settled = Tile(
                    id: appID,
                    name: existing?.name ?? (created["displayName"] as? String ?? "App"),
                    emoji: existing?.emoji ?? "✨",
                    bg: existing?.bg ?? "#2c2c2e",
                    isSettling: false
                )
                if let tileID {
                    store.settle(placeholderID: tileID, into: settled)
                } else {
                    store.upsert(settled)
                }
                // Give the hosted app the same icon the grid is showing.
                Task { _ = try? await client.setIcon(id: appID, emoji: settled.emoji, bg: settled.bg) }
                return json(["app_id": appID, "url": created["url"] as? String ?? ""])

            case "patch_app_source":
                let edits = args["edits"] as? [[String: Any]] ?? []
                let result = try await client.patchSource(id: args["app_id"] as? String ?? "", edits: edits)
                return json(["ok": true, "revision": result["revision"] ?? 0])

            case "get_app_source":
                let source = try await client.getSource(id: args["app_id"] as? String ?? "")
                return String(json(source).prefix(60_000))

            case "call_app_operation":
                let value = try await client.callOperation(
                    id: args["app_id"] as? String ?? "",
                    operation: args["operation"] as? String ?? "",
                    payload: args["payload"] as? [String: Any] ?? [:]
                )
                return String(json(value).prefix(20_000))

            case "list_my_apps":
                return json(store.tiles.filter { !$0.isSettling }.map {
                    ["app_id": $0.id, "name": $0.name]
                })

            default:
                return json(["error": "unknown tool \(name)"])
            }
        } catch {
            // Handing the platform's own error back is what lets Astra fix its
            // source and retry without a human in the loop.
            return json(["error": error.localizedDescription])
        }
    }

    // MARK: - Strip

    private func label(for tool: String) -> String {
        switch tool {
        case "place_icon": return "putting an icon on your grid"
        case "create_app": return "creating the app on Charming"
        case "patch_app_source": return "editing the app in place"
        case "get_app_source": return "reading the current source"
        case "call_app_operation": return "reading the app's data"
        case "list_my_apps": return "checking what you already have"
        default: return tool
        }
    }

    private func markToolDone(name: String, result: String) {
        let failed = result.contains("\"error\"")
        if let index = events.lastIndex(where: { $0.kind == .tool && $0.text == label(for: name) }) {
            events[index].kind = failed ? .error : .toolDone
            if failed { events[index].detail = "Astra will try to fix this" }
        }
    }

    private func appendReasoning(_ delta: String) {
        reasoningBuffer += delta
        let trimmed = reasoningBuffer
            .split(separator: "\n").last.map(String.init) ?? reasoningBuffer
        if let id = reasoningLineID, let index = events.firstIndex(where: { $0.id == id }) {
            events[index].text = String(trimmed.suffix(120))
        } else {
            var event = BuildEvent(kind: .reasoning, text: String(trimmed.suffix(120)))
            reasoningLineID = event.id
            events.append(event)
            _ = event
        }
    }

    private func flushReasoning() {
        reasoningLineID = nil
        reasoningBuffer = ""
    }

    private func push(_ kind: BuildEvent.Kind, _ text: String, detail: String? = nil) {
        events.append(BuildEvent(kind: kind, text: text, detail: detail))
    }

    private func fail(_ message: String) {
        push(.error, message)
        phase = .failed(message)
        canSteer = false
    }

    private func describeError(_ object: [String: Any]) -> String {
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
        return object["message"] as? String ?? "unknown error"
    }

    private func json(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value) || value is [Any],
              let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    private func loadInstructions() async throws -> String {
        if let instructions { return instructions }
        let client = CharmingClient(token: Credentials.shared.charmingToken)
        let guide = try await client.authoringGuide()
        let combined = AstraTools.preamble + "\n\n---\n\n" + guide
        instructions = combined
        return combined
    }
}

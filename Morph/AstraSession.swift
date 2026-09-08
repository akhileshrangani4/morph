import Foundation
import OSLog

let morphLog = Logger(subsystem: "so.charming.morph", category: "astra")

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
    /// What this turn has actually accomplished, so a steered response can be
    /// resumed with facts instead of assumptions.
    private var placedTileID: String?
    private var createdAppID: String?

    init(store: TileStore) {
        self.store = store
    }

    // MARK: - Turns

    func run(prompt: String) async {
        events.removeAll()
        phase = .working
        reasoningLineID = nil
        reasoningBuffer = ""
        placedTileID = nil
        createdAppID = nil

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

    /// Low across the board. The worked example carries the contract, so the
    /// model does not have to reason its way to it, and the build stays quick
    /// enough to watch.
    private func effort(for prompt: String) -> String { "low" }

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
        morphLog.debug("event \(type, privacy: .public)")
        if type == "error" || type.hasSuffix(".failed") || type == "response.incomplete" {
            morphLog.error("raw \(String(text.prefix(900)), privacy: .public)")
        }

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
            if events.last?.kind == .reasoning { events.removeLast() }
            push(.done, spoken.isEmpty ? "Done" : Self.plainText(spoken))
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
                    "input": progressReport(),
                ])
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    /// Exactly what is and is not done, so the resumed turn does not invent
    /// state. The model reads this immediately after a steer.
    private func progressReport() -> String {
        var lines = ["Apply the change I just sent, keeping the work you already finished. Here is exactly where you are:"]
        if let placedTileID {
            lines.append("- A tile is on the grid with tile_id \(placedTileID). Reuse it; do not call place_icon again.")
        } else {
            lines.append("- No tile on the grid yet. Call place_icon first.")
        }
        if let createdAppID {
            lines.append("- The app EXISTS with app_id \(createdAppID). Change it with get_app_source then patch_app_source. Do NOT call create_app again.")
        } else {
            lines.append("- No app has been created yet: every create_app call so far either failed or never ran. There is no source to read, so do NOT call get_app_source. Author the app with the change folded in and call create_app once.")
        }
        return lines.joined(separator: "\n")
    }

    private func execute(calls: [[String: Any]], previousResponseID: String) {
        Task {
            var outputs: [[String: Any]] = []
            for call in calls {
                let name = call["name"] as? String ?? ""
                let callID = call["call_id"] as? String ?? ""
                let raw = call["arguments"] as? String ?? "{}"
                let args = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]

                morphLog.debug("tool \(name, privacy: .public) args \(String(raw.prefix(400)), privacy: .public)")
                let result = await runTool(name: name, args: args)
                morphLog.debug("tool \(name, privacy: .public) -> \(String(result.prefix(700)), privacy: .public)")
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
                    emoji: args["emoji"] as? String ?? "\u{2728}",
                    symbol: (args["symbol"] as? String).validSymbol,
                    bg: args["bg"] as? String ?? "#2c2c2e",
                    isSettling: true
                )
                store.upsert(tile)
                tiles[tile.id] = tile.id
                placedTileID = tile.id
                return json(["tile_id": tile.id])

            case "create_app":
                let module = Self.withSchema(args["module"] as? String ?? "")
                if let complaint = Self.shapeComplaint(module) {
                    return json(["error": complaint])
                }
                let created = try await client.createApp(
                    module: module,
                    ui: args["ui"] as? String,
                    styles: args["styles"] as? String,
                    description: args["description"] as? String
                )
                guard let appID = created["id"] as? String else {
                    return json(["error": "create returned no id"])
                }
                let tileID = args["tile_id"] as? String
                let existing = store.tiles.first { $0.id == tileID }
                // A steered build can end up as a different app than the tile
                // announced, so Astra may rename and re-icon it here.
                let settled = Tile(
                    id: appID,
                    name: (args["name"] as? String) ?? existing?.name ?? (created["displayName"] as? String ?? "App"),
                    emoji: existing?.emoji ?? "✨",
                    symbol: args["symbol"] == nil
                        ? (existing?.symbol ?? "square.grid.2x2.fill")
                        : (args["symbol"] as? String).validSymbol,
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

                // Charming returns advisories for things that publish fine but
                // behave badly at runtime. Handing them straight back lets
                // Astra fix its own app before the user ever taps the icon.
                createdAppID = appID
                var result: [String: Any] = ["app_id": appID, "url": created["url"] as? String ?? ""]
                if let advisories = created["advisories"] as? [[String: Any]], !advisories.isEmpty {
                    result["advisories"] = advisories.compactMap { $0["summary"] as? String }
                    result["next_step"] = "Fix each advisory now with patch_app_source, then stop."
                }
                return json(result)

            case "patch_app_source":
                let edits = args["edits"] as? [[String: Any]] ?? []
                let result = try await client.patchSource(id: args["app_id"] as? String ?? "", edits: edits)
                return json(["ok": true, "revision": result["revision"] ?? 0])

            case "get_app_source":
                let appID = args["app_id"] as? String ?? ""
                guard !appID.isEmpty, !appID.hasPrefix("pending-") else {
                    return json(["error": "No such app. A tile_id is not an app_id, and no app has been created yet, so there is no source to read."])
                }
                let source = try await client.getSource(id: appID)
                return String(json(source).prefix(60_000))

            case "call_app_operation":
                let value = try await client.callOperation(
                    id: args["app_id"] as? String ?? "",
                    operation: args["operation"] as? String ?? "",
                    payload: args["payload"] as? [String: Any] ?? [:]
                )
                return String(json(value).prefix(20_000))

            case "read_charming_guide":
                let guide = try await client.authoringGuide()
                return String(guide.prefix(60_000))

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

    /// `$schema` is a fixed string the platform requires and the model kept
    /// omitting. It is not a judgement call, so Morph supplies it instead of
    /// spending a retry telling the model to remember it.
    static func withSchema(_ module: String) -> String {
        guard !module.contains("$schema") else { return module }
        guard let range = module.range(of: #"export\s+const\s+manifest\s*=\s*\{"#, options: .regularExpression) else {
            return module
        }
        let schema = "\n  $schema: 'https://charm.ing/schema/app-manifest/2026-07-31.json',"
        return module.replacingCharacters(in: range, with: module[range] + schema)
    }

    /// Catches the shapes Astra reaches for when it writes from its priors
    /// instead of Charming's contract. Rejecting here costs no network round
    /// trip and gives a far more specific message than a 400 would.
    static func shapeComplaint(_ module: String) -> String? {
        guard module.contains("export const manifest") else {
            return "module must declare `export const manifest = { ... }` as a literal. Re-read the NON-NEGOTIABLE MODULE SHAPE section and rewrite it."
        }
        guard module.contains("export const routes") else {
            return "module must declare `export const routes = [ ... ]` as a literal array of routes with op/method/path/inputSchema/outputSchema/handler."
        }
        guard module.contains("$schema") else {
            return "manifest is missing `$schema: 'https://charm.ing/schema/app-manifest/2026-07-31.json'`."
        }
        if module.contains("type: 'collection'") || module.contains("collections:") {
            return "There is no `collections` concept on Charming. Delete it and write explicit routes whose handlers read and write env.storage."
        }
        if module.contains("(ctx)") || module.contains("(ctx,") {
            return "A handler signature is `async (input, { env }) => ...`. There is no `ctx` argument."
        }
        if module.range(of: #"export const routes\s*=\s*\[\s*\]"#, options: .regularExpression) != nil {
            return "`routes` is empty, so this app does nothing. Write the routes the app actually needs, each with a handler. Do not simplify the app to get past an error: fix the error."
        }
        if !module.contains("handler") {
            return "No route declares a `handler`, so nothing can run. Every route needs `handler: async (input, { env }) => ...`."
        }
        if module.contains("localStorage") {
            return "localStorage is empty inside chat hosts and never syncs. Persist through env.storage instead."
        }
        if !module.contains("charming:storage/kv@1.0"), module.contains("env.storage") {
            return "This app uses env.storage but the manifest omits capabilities.imports: ['charming:storage/kv@1.0'], so every read and write will throw."
        }
        return nil
    }

    // MARK: - Strip

    private func label(for tool: String) -> String {
        switch tool {
        case "place_icon": return "putting an icon on your grid"
        case "create_app": return "creating the app on Charming"
        case "patch_app_source": return "editing the app in place"
        case "get_app_source": return "reading the current source"
        case "call_app_operation": return "reading the app's data"
        case "read_charming_guide": return "reading Charming's authoring guide"
        case "list_my_apps": return "checking what you already have"
        default: return tool
        }
    }

    private func markToolDone(name: String, result: String) {
        let failed = result.contains("\"error\"")
        guard let index = events.lastIndex(where: { $0.kind == .tool && $0.text == label(for: name) }) else { return }
        events[index].kind = failed ? .error : .toolDone
        if failed {
            // Show what actually broke. Astra gets the same string back and
            // fixes it, so the strip explains the retry rather than hiding it.
            events[index].detail = String(reason(from: result).prefix(180))
        }
    }

    private func reason(from result: String) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any],
            let message = object["error"] as? String
        else { return "Astra will try to fix this" }
        return message
    }

    private func appendReasoning(_ delta: String) {
        reasoningBuffer += delta
        let line = Self.currentSentence(of: Self.plainText(reasoningBuffer))
        if let id = reasoningLineID, let index = events.firstIndex(where: { $0.id == id }) {
            events[index].text = line
        } else {
            let event = BuildEvent(kind: .reasoning, text: line)
            reasoningLineID = event.id
            events.append(event)
        }
    }

    /// The model writes for a chat window; the strip is not one. Strip the
    /// markdown rather than showing raw asterisks and link syntax on stage.
    static func plainText(_ text: String) -> String {
        var output = text.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
        output = output.replacingOccurrences(of: "**", with: "")
        output = output.replacingOccurrences(of: "`", with: "")
        output = output.replacingOccurrences(
            of: #"\n{2,}"#, with: " ", options: .regularExpression
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The strip is a ticker, so it shows one sentence at a time: the one being
    /// written, or the last finished one between sentences.
    static func currentSentence(of buffer: String) -> String {
        let sentences = buffer
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let last = sentences.last else {
            return buffer.trimmingCharacters(in: .whitespaces)
        }
        return last.count > 150 ? String(last.prefix(150)) + "\u{2026}" : last
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
        // Charming's full guide is ~13k tokens. Carrying it in every turn's
        // instructions measurably hurt adherence to the one thing that matters,
        // the module shape, so the prompt keeps the contract and the worked
        // example and the guide moves behind `read_charming_guide`.
        let combined = AstraTools.preamble + "\n\n" + AstraTools.contract + "\n\n" + AstraExample.block
        instructions = combined
        return combined
    }
}

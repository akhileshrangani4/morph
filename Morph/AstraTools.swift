import Foundation

/// Astra's tool surface. Each entry maps one-to-one onto a Charming public API
/// call, except `place_icon`, which is local and instant so a tile can appear
/// on the grid before the app behind it exists.
///
/// `async: true` marks the slow writes. GPT-6 Astra keeps reasoning and can
/// call other tools while Morph is still waiting on Charming, instead of
/// stalling its own generation behind a network round trip.
enum AstraTools {
    static func all() -> [[String: Any]] {
        [
            [
                "type": "function",
                "name": "place_icon",
                "description": "Put a tile on the user's home grid immediately, before the app is built. Call this FIRST, as soon as you know what you are making, so the user sees it appear. Returns a tile_id to pass to create_app.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string", "description": "Short app name, 1-2 words, as it appears under the icon."],
                        "emoji": ["type": "string", "description": "A single emoji for the icon."],
                        "bg": ["type": "string", "description": "Icon background as a hex colour, e.g. #2c2c2e."],
                    ],
                    "required": ["name", "emoji", "bg"],
                    "additionalProperties": false,
                ],
            ],
            [
                "type": "function",
                "name": "create_app",
                "description": "Create the Charming app. Authors the real hosted app and returns its id and url.",
                "async": true,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "tile_id": ["type": "string", "description": "The tile_id returned by place_icon."],
                        "module": ["type": "string", "description": "The ES module source: literal canonical manifest plus routes array."],
                        "ui": ["type": "string", "description": "Inline classic script that populates #app."],
                        "styles": ["type": "string", "description": "CSS injected alongside ui."],
                        "description": ["type": "string", "description": "One-line description of the app."],
                    ],
                    "required": ["tile_id", "module", "ui", "styles", "description"],
                    "additionalProperties": false,
                ],
            ],
            [
                "type": "function",
                "name": "patch_app_source",
                "description": "Apply exact-string edits to an existing app's source. Prefer this over recreating an app when the user asks for a change, because it keeps the app's stored data.",
                "async": true,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "app_id": ["type": "string"],
                        "edits": [
                            "type": "array",
                            "description": "Each edit replaces old_string with new_string in one bucket.",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "bucket": ["type": "string", "enum": ["module", "ui", "styles"]],
                                    "old_string": ["type": "string"],
                                    "new_string": ["type": "string"],
                                ],
                                "required": ["bucket", "old_string", "new_string"],
                                "additionalProperties": false,
                            ],
                        ],
                    ],
                    "required": ["app_id", "edits"],
                    "additionalProperties": false,
                ],
            ],
            [
                "type": "function",
                "name": "get_app_source",
                "description": "Read an app's exact persisted source. Do this before patching so your old_string matches byte for byte.",
                "async": true,
                "parameters": [
                    "type": "object",
                    "properties": ["app_id": ["type": "string"]],
                    "required": ["app_id"],
                    "additionalProperties": false,
                ],
            ],
            [
                "type": "function",
                "name": "call_app_operation",
                "description": "Call a route the app declared, to read or write its data. Use this to answer questions about what is inside an app.",
                "async": true,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "app_id": ["type": "string"],
                        "operation": ["type": "string", "description": "The route name, without the /api/ prefix."],
                        "payload": ["type": "object", "description": "JSON body for the route.", "additionalProperties": true],
                    ],
                    "required": ["app_id", "operation", "payload"],
                    "additionalProperties": false,
                ],
            ],
            [
                "type": "function",
                "name": "list_my_apps",
                "description": "List the apps on this user's grid, with their ids and names.",
                "parameters": ["type": "object", "properties": [:], "additionalProperties": false],
            ],
        ]
    }

    /// Morph's own operating instructions. Charming's published authoring guide
    /// is appended to this, so the contract comes from the platform itself.
    static let preamble = """
    You are the engine inside Morph, an iOS app that has no fixed screens. The \
    user describes what they need and you build it as a real hosted Charming app \
    that appears as an icon on their phone.

    How to work:
    - The moment you know what you are making, call place_icon. The user is \
    watching an empty grid and the icon appearing is the first sign you heard them.
    - Then author the app and call create_app with the tile_id you got back.
    - Build the smallest thing that genuinely works and stores real data. One \
    clear screen beats five empty ones. Never build a settings screen nobody asked for.
    - When the user asks to change an existing app, call get_app_source, then \
    patch_app_source. Do not recreate the app; that would throw away their data.
    - When the user asks about what is in an app, call call_app_operation.
    - The user may interrupt you mid-build to change what they want. When that \
    happens, keep everything already finished and adapt the rest. Do not start over.
    - If a call fails, read the error, fix your source, and try again yourself.

    Design the app to look at home on a phone: large tap targets, one column, \
    no hover-dependent controls, dark background by default.

    What follows is Charming's own authoring guide. It is the authoritative \
    contract for the module, ui, and styles you write.
    """
}

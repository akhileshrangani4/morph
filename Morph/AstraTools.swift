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
                        "emoji": ["type": "string", "description": "A single emoji for the icon, used for the app's own icon on Charming."],
                        "symbol": ["type": "string", "description": "An SF Symbol name that fits the app, e.g. dumbbell.fill, book.closed.fill, fork.knife. Used for the icon on the phone grid, so pick one that certainly exists in SF Symbols."],
                        "bg": ["type": "string", "description": "Icon background as a hex colour, e.g. #2c2c2e."],
                    ],
                    "required": ["name", "emoji", "symbol", "bg"],
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
                        "name": ["type": "string", "description": "Only if the app is no longer what the tile says, e.g. after the user changed their mind mid-build. Renames the tile."],
                        "symbol": ["type": "string", "description": "Only if the app changed enough that the tile's icon no longer fits. A valid SF Symbol name."],
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
                "name": "read_charming_guide",
                "description": "Read Charming's full authoring guide. The contract you were given covers the common case; call this when you need detail it does not cover, such as live updates, images, assets, secrets, or device permissions.",
                "async": true,
                "parameters": ["type": "object", "properties": [:], "additionalProperties": false],
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
    /// Appended AFTER Charming's guide. The guide is ~13k tokens of prose and
    /// the exact module shape got lost in it, so the non-negotiable contract is
    /// restated last, immediately before the user's turn.
    static let contract = """
    ---

    NON-NEGOTIABLE MODULE SHAPE. Everything above is context; this is the
    contract. A module in any other shape is rejected before it reaches the
    platform.

    `module` MUST be an ES module exporting exactly these two things:

    export const manifest = {
      $schema: 'https://charm.ing/schema/app-manifest/2026-07-31.json',
      id: 'gymlog',                       // lowercase, no spaces, your own id
      meta: { name: 'Gym Log', icon: { emoji: '\u{1F3CB}', bg: '#252a23' } },
      capabilities: { imports: ['charming:storage/kv@1.0'] },  // required for ANY storage
    };

    export const routes = [
      {
        op: 'getState',                   // the op name IS the frontend method name
        method: 'POST',
        path: '/api/getState',
        title: 'Read state',
        description: 'Return everything the UI needs.',
        inputSchema: { type: 'object', properties: {}, additionalProperties: false },
        outputSchema: {
          type: 'object',
          required: ['sets'],
          properties: { sets: { type: 'array', items: { type: 'object', properties: {}, additionalProperties: true } } },
          additionalProperties: false,
        },
        annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
        public: true,
        handler: async (input, { env }) => {
          const sets = (await env.storage.get('sets')) ?? [];
          return { sets };
        },
      },
    ];

    Hard rules, every one of which has broken a real app:
    - There is NO `collections`, NO `fields`, NO `type: 'collection'`, and no
      schema-inference of any kind. You write explicit routes with handlers.
    - A handler signature is `async (input, { env }) => ...`. There is no `ctx`.
    - Persist ONLY through `env.storage`: `get(key)` / `put(key, value)` /
      `delete(key)` / `list()`. Never localStorage, never JSON.stringify around it.
    - Every `required` entry in a schema needs a matching `properties` entry with
      a concrete type, including inside nested objects.
    - `ui` is a classic script, not a module. Set `#app`'s innerHTML FIRST, then
      attach listeners. Call the backend with
      `window.charming.api('<your manifest.id>').<op>(input)`, never fetch().
    - Return the `outputSchema` value directly from a handler. Do not wrap it in
      `{ ok }` or `{ value }`.
    """

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
    - The user will build many apps over time. A request for something new is a \
    NEW app: call place_icon and create_app, even if other apps already exist. \
    Only treat a message as a change to an existing app when it clearly refers \
    to one ("add a notes field to the gym log", "make it dark"). When in doubt \
    and several apps exist, call list_my_apps and pick by name.
    - When the user asks to change an existing app, call get_app_source, then \
    patch_app_source. Do not recreate the app; that would throw away their data.
    - When the user asks about what is in an app, call call_app_operation.
    - The user may interrupt you mid-build to change what they want. When that \
    happens, keep everything already finished and adapt the rest. Do not start over. \
    If the change means the tile's name or icon no longer fits, pass a new `name` \
    and `symbol` to create_app so the grid matches what you actually built.
    - Write compactly. One screen that works beats five that do not: aim for a \
    module under 150 lines and a ui under 120. You are being watched while you write.
    - If a call fails, read the error, fix your source, and try again yourself.

    Design the app to look at home on a phone: large tap targets, one column, \
    no hover-dependent controls, dark background by default.

    What follows is Charming's own authoring guide. It is the authoritative \
    contract for the module, ui, and styles you write.
    """
}

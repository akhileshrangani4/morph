# Morph

An iOS app with no screens of its own. You say what you need, an icon appears on
your grid within seconds, and behind it is a real, hosted, data-backed app. Keep
talking and it changes shape. Interrupt it while it is still building and it
adapts without starting over.

Built at the OpenAI GPT-6 Astra hackathon, San Francisco, 8 September 2026.

## What this actually does

1. You type or say what you need: *"track my gym sets, weight and reps, and
   whether I am going up over time."*
2. Two seconds later a tile lands on the grid, named and iconed. GPT-6 Astra
   placed it before writing a line of the app, so you can see it heard you.
3. The composer becomes a build strip. Every line in it is a real model event or
   a tool Morph actually ran. Nothing is faked for the demo.
4. **While it is still building, you interrupt: *"actually make it for climbing,
   grades not weight."*** The build does not restart. Astra keeps the finished
   work, folds in the change, renames the tile, and ships Climb Log instead.
5. Tap the tile and the app opens full screen. Log a route, close it, reopen it.
   The data is still there, because it is stored server-side, not in the app.

## What we built today, and what we did not

This matters for judging, so it is stated plainly.

**The platform underneath is Charming** ([usecharming.com](https://usecharming.com)),
an existing product with a public HTTP API for creating and hosting apps. It also
has an existing iOS client: a 1,451-line Expo app that signs in, lists your apps,
and opens one in a webview. That app has **no generative capability whatsoever**
and contains no reference to OpenAI.

**Everything in this repository was written during the hackathon**, from an empty
directory, in Swift. Nothing was copied from Charming's private repository, not
even its auth code. Specifically, what is new here is:

- the native shell where an app is described, watched, steered, and opened;
- the GPT-6 Astra tool loop that authors a Charming app end to end;
- mid-turn steering, so a build in flight can be redirected by voice or text;
- the guardrails that make model-authored apps actually publish (below).

Morph talks to Charming the way any third-party client would, over its public
API. The one piece of Charming's own material it uses at runtime is Charming's
published authoring guide, fetched from a public endpoint.

## How GPT-6 Astra is used

Astra is not a text generator bolted on the side. It is the runtime. Three of its
new capabilities are load-bearing:

**Mid-turn steering** (`Morph/AstraSession.swift`) is why the whole thing runs
over the Responses **WebSocket** transport rather than HTTP. Steering exists only
there. When you interrupt, Morph sends `response.steer` against the open
response; the server replies `response.steer.accepted`, ends the current response
as `response.incomplete` with reason `steered`, and Morph continues it. Completed
work survives. This is the difference between "changing your mind" and "starting
over," and it is the centrepiece of the demo.

**Async tool calling** (`Morph/AstraTools.swift`). Creating an app on Charming is
the slow step. The write tools are declared `async: true`, so Astra keeps
reasoning and can call other tools while Morph is still waiting on the network,
instead of stalling its own generation behind a round trip. It is why the icon can
appear before the app exists.

**Reasoning effort** is set per turn on `response.create`. Authoring initially ran
at `high`; with a worked example carrying the contract, `low` produces valid apps
and keeps the build fast enough to watch.

## The interesting engineering problem

Getting a model to emit a valid app for a platform it has never seen is most of
the work, and prompt size was the enemy.

Charming publishes a 52 KB authoring guide. Putting all of it in `instructions`
seemed obviously right and was actively harmful: buried in roughly 13k tokens of
prose, Astra wrote a confident, plausible manifest out of its own priors, with
`collections`, `fields`, and `ctx`-style handlers that Charming has never had.
After several schema rejections it "succeeded" by shipping an app with
`routes: []`, which publishes fine and does nothing.

Four changes fixed it, and all four are in the repo:

- **A focused contract plus one worked example** replaced the full guide in the
  prompt. `Morph/AstraExample.swift` holds a complete app that was published
  successfully against the live API before being pasted in. The guide is still
  available, as a tool Astra calls when it needs depth it does not have.
- **Constants are supplied, not requested.** Astra kept omitting `$schema`, a
  fixed string. Morph injects it (`withSchema`) rather than spending a retry
  asking the model to remember a constant.
- **Local shape validation before the network call** (`shapeComplaint`). Wrong
  handler signatures, `collections`, `localStorage`, missing storage capability,
  and empty `routes` are all rejected with a specific message. Rejecting an empty
  `routes` array with *"do not simplify the app to get past an error, fix the
  error"* is what stopped the degenerate outcome.
- **Errors are fed back verbatim.** Charming's 400s, 422s, and its own
  `advisories` go straight into the tool result, so Astra fixes its source and
  retries without a human. In one logged run it worked through four distinct
  schema rejections unaided and then published a working app.

There is also a smaller one worth noting: after a steer, Astra assumed an app
already existed and went looking for source that was never written. Resumed turns
now receive an explicit progress report of what does and does not exist, rather
than being left to infer it.

## Architecture

Two network dependencies, no backend of our own. One process, which matters when
you are demoing live.

```
SwiftUI shell ──── wss://api.openai.com/v1/responses ──── GPT-6 Astra
      │                  (response.create / response.steer)
      │
      └─────────── https://charm.ing (public API) ──────── hosted app
                   create · patch source · call operations
```

| File | Role |
|---|---|
| `Morph/AstraSession.swift` | The engine: WebSocket, event loop, tool dispatch, steering |
| `Morph/AstraTools.swift` | Tool definitions and Morph's operating instructions |
| `Morph/AstraExample.swift` | The verified worked example Astra copies |
| `Morph/CharmingClient.swift` | Thin client over Charming's public HTTP API |
| `Morph/HomeView.swift` | Home grid and composer |
| `Morph/BuildStripView.swift` | The build strip and the steer bar |
| `Morph/AppWebView.swift` | The generated app, full screen |

No Swift Package dependencies. Plain `URLSession` and `WKWebView`.

## Running it

Xcode 26 or newer, an iOS 26 simulator.

```bash
xcodebuild -project Morph.xcodeproj -target Morph \
  -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO
xcrun simctl install booted build/Debug-iphonesimulator/Morph.app
xcrun simctl launch booted so.charming.morph
```

Open the gear and paste two keys: an OpenAI API key, and a Charming personal
access token from your Charming account settings. Keys are entered at runtime and
stored in `UserDefaults`, so nothing secret is built into the binary or committed.
A shipping app would use the Keychain.

To rehearse a run without typing, three launch-time defaults drive it:

```bash
xcrun simctl spawn booted defaults write so.charming.morph \
  morphPrompt -string "track my gym sets, weight and reps, and progress over time"
xcrun simctl spawn booted defaults write so.charming.morph \
  morphSteerText -string "actually make it for climbing, grades not weight"
xcrun simctl spawn booted defaults write so.charming.morph morphSteerAfter -int 10
```

`morphSteerAfter` fires the interrupt through the same path the steer bar uses.

## Honest limitations

- A build takes roughly 60 to 90 seconds, most of it generating the app's source.
  The icon lands in about two seconds, and the steering window is the wait, so the
  demo uses the latency rather than hiding it. It is still latency.
- Keys live in `UserDefaults`, not the Keychain.
- Astra sometimes calls the authoring guide tool when the inline contract would
  have been enough, which costs a round trip.
- Voice input is not wired up; the interrupt is typed. The steering path itself is
  identical either way.
- Errors surface in the build strip rather than anywhere more considered.

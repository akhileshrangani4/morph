import SwiftUI

struct HomeView: View {
    @StateObject private var store: TileStore
    @StateObject private var session: AstraSession
    @ObservedObject private var credentials = Credentials.shared

    @State private var prompt = ""
    @State private var openTile: Tile?
    @State private var pendingDeletion: Tile?
    @State private var isEditing = false
    @State private var showSettings = false
    @State private var showTranscript = false
    @State private var hasRehearsed = false
    @FocusState private var promptFocused: Bool

    init() {
        let store = TileStore()
        _store = StateObject(wrappedValue: store)
        _session = StateObject(wrappedValue: AstraSession(store: store))
    }

    /// Three things people actually ask for. Tapping one is the fastest way to
    /// learn what Morph does, and it doubles as the empty state.
    private let suggestions = [
        "a climbing log, grades and sends",
        "split rent and bills with my roommates",
        "how much water I drink each day",
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if session.phase == .working, !showTranscript {
                    BuildingScreen(
                        tile: store.tiles.last(where: { $0.isSettling }),
                        line: session.latestLine
                    )
                    .transition(.opacity)
                } else {
                    content
                        .transition(.opacity)
                }
                composer
            }
            .animation(.easeOut(duration: 0.35), value: session.phase)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(item: $openTile) { AppWebView(tile: $0) }
        .alert("Delete \(pendingDeletion?.name ?? "app")?", isPresented: deletionBinding) {
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Delete", role: .destructive) {
                if let tile = pendingDeletion {
                    Task { await session.delete(tile) }
                }
                pendingDeletion = nil
            }
        } message: {
            Text("This removes the app and everything stored in it.")
        }
        .onAppear(perform: rehearse)
    }

    private var deletionBinding: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("Morph")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Text(countLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.faint)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.25), value: store.tiles.count)

            Spacer()

            if isEditing {
                Button("Done") { withAnimation(.easeOut(duration: 0.25)) { isEditing = false } }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            } else {
                HStack(spacing: 18) {
                    if !session.turns.isEmpty {
                        Button {
                            withAnimation(.easeOut(duration: 0.3)) { showTranscript.toggle() }
                        } label: {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(showTranscript ? Theme.accent : Theme.dim)
                        }
                    }
                    Button { showSettings = true } label: {
                        Image(systemName: "key")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 26)
    }

    private var countLabel: String {
        let live = store.tiles.filter { !$0.isSettling }.count
        switch live {
        case 0: return ""
        case 1: return "one app"
        default: return "\(live) apps"
        }
    }

    // MARK: - Content

    /// The grid is the product. The trace of what Astra did is there for
    /// whoever wants it and out of the way for everyone else.
    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if store.tiles.isEmpty {
                        emptyState
                    } else {
                        grid
                    }

                    if showTranscript, !session.turns.isEmpty {
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(session.turns) { turn in
                                TurnView(turn: turn).id(turn.id)
                            }
                        }
                        .padding(.top, 34)
                        .transition(.opacity)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: session.turns.last?.events.count) {
                guard showTranscript else { return }
                withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What do you\nneed today?")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineSpacing(1)
                .padding(.top, 18)

            Text("Say it, and it becomes an app on this screen.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.dim)
                .padding(.top, 14)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        prompt = suggestion
                        submit()
                    } label: {
                        HStack(spacing: 10) {
                            Text(suggestion)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.ink)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.faint)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Theme.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(session.phase == .working)
                }
            }
            .padding(.top, 36)
        }
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4),
            alignment: .leading,
            spacing: 14
        ) {
            ForEach(store.tiles) { tile in
                TileView(tile: tile, isEditing: isEditing) { pendingDeletion = tile }
                    .onTapGesture {
                        guard !tile.isSettling else { return }
                        if isEditing {
                            withAnimation(.easeOut(duration: 0.25)) { isEditing = false }
                        } else {
                            openTile = tile
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.45) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.easeOut(duration: 0.25)) { isEditing = true }
                    }
            }
        }
        .padding(.horizontal, -6)
        .animation(.easeOut(duration: 0.4), value: store.tiles)
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .tint(Theme.accent)
                .lineLimit(1...5)
                .focused($promptFocused)
                .submitLabel(.send)

            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(canSubmit ? Theme.background : Theme.faint)
                    .frame(width: 32, height: 32)
                    .background(canSubmit ? tint : Theme.raised, in: Circle())
            }
            .disabled(!canSubmit)
            .animation(.easeOut(duration: 0.2), value: canSubmit)
        }
        .padding(.leading, 18)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(session.canSteer ? Theme.accent.opacity(0.6) : Theme.hairline, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var canSubmit: Bool {
        let typed = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return typed && (session.phase != .working || session.canSteer)
    }

    private var tint: Color { session.canSteer ? Theme.accent : Theme.ink }

    private var placeholder: String {
        if session.canSteer {
            return session.steerRedirects ? "change your mind while it builds" : "changes will land as an edit"
        }
        if session.phase == .working { return "working" }
        return store.tiles.isEmpty ? "or type your own" : "another app, or a change to one"
    }

    /// One input. While a build is open it interrupts that build; otherwise it
    /// starts a new one.
    private func submit() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        prompt = ""
        promptFocused = false
        if session.canSteer {
            session.steer(text)
        } else {
            Task { await session.run(prompt: text) }
        }
    }

    /// Launch-time hooks so a run can be rehearsed from the command line.
    private func rehearse() {
        if !credentials.isConfigured { showSettings = true }
        // onAppear fires again when a full-screen cover dismisses, which would
        // otherwise kick off a second build behind the first.
        guard !hasRehearsed else { return }
        hasRehearsed = true
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "morphEditMode") { isEditing = true }
        if defaults.bool(forKey: "morphOpenNewest"),
           let newest = store.tiles.last(where: { !$0.isSettling }) {
            openTile = newest
        }
        guard let seeded = defaults.string(forKey: "morphPrompt"), !seeded.isEmpty else { return }
        Task { await session.run(prompt: seeded) }

        let steer = defaults.string(forKey: "morphSteerText") ?? ""
        let steerAfter = defaults.double(forKey: "morphSteerAfter")
        if !steer.isEmpty, steerAfter > 0 {
            Task {
                try? await Task.sleep(for: .seconds(steerAfter))
                session.steer(steer)
            }
        }

        let second = defaults.string(forKey: "morphSecondPrompt") ?? ""
        let secondAfter = defaults.double(forKey: "morphSecondAfter")
        if !second.isEmpty, secondAfter > 0 {
            Task {
                try? await Task.sleep(for: .seconds(secondAfter))
                await session.run(prompt: second)
            }
        }
    }
}

/// One home-grid icon. A hairline circles it while Astra is still writing the
/// app behind it, and it jiggles with a delete badge in edit mode.
struct TileView: View {
    let tile: Tile
    let isEditing: Bool
    let onDelete: () -> Void

    @State private var jiggle = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(Color(hex: tile.bg))
                    .frame(width: 66, height: 66)
                    .overlay(
                        Image(systemName: tile.symbol)
                            .font(.system(size: 27, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .opacity(tile.isSettling ? 0.55 : 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .stroke(Theme.ink.opacity(0.08), lineWidth: 1)
                    )

                if isEditing && !tile.isSettling {
                    Button(action: onDelete) {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(Theme.background)
                            .frame(width: 22, height: 22)
                            .background(Theme.ink, in: Circle())
                    }
                    .offset(x: -8, y: -8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(9)
            .rotationEffect(.degrees(isEditing && !tile.isSettling ? (jiggle ? 1.5 : -1.5) : 0))
            .animation(
                isEditing
                    ? .easeInOut(duration: 0.13).repeatForever(autoreverses: true)
                    : .default,
                value: jiggle
            )

            Text(tile.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tile.isSettling ? Theme.dim : Theme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: 84)
        .onAppear { jiggle = isEditing }
        .onChange(of: isEditing) { _, editing in jiggle = editing }
    }
}

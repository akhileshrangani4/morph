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
    @FocusState private var promptFocused: Bool

    init() {
        let store = TileStore()
        _store = StateObject(wrappedValue: store)
        _session = StateObject(wrappedValue: AstraSession(store: store))
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                transcript
                if session.canSteer {
                    SteerBar(session: session)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                composer
            }
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
            Text("This removes the app and everything stored in it. It cannot be undone.")
        }
        .onAppear(perform: rehearse)
    }

    private var deletionBinding: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 12) {
            Text("Morph")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            if isEditing {
                Button("Done") { withAnimation(.spring(duration: 0.3)) { isEditing = false } }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            } else {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 16)
    }

    /// Grid and conversation share one scroll view, so the apps sit above the
    /// talk the way a home screen sits above what you asked for.
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if store.tiles.isEmpty {
                        emptyState
                    } else {
                        grid
                    }

                    ForEach(session.turns) { turn in
                        TurnView(turn: turn).id(turn.id)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: session.turns.last?.events.count) {
                withAnimation(.spring(duration: 0.35)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: session.turns.count) {
                withAnimation(.spring(duration: 0.35)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing here yet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            Text("Say what you need. It becomes an app on this screen, and you can change your mind while it builds.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4),
            spacing: 20
        ) {
            ForEach(store.tiles) { tile in
                TileView(tile: tile, isEditing: isEditing) { pendingDeletion = tile }
                    .onTapGesture {
                        guard !tile.isSettling else { return }
                        if isEditing {
                            withAnimation(.spring(duration: 0.3)) { isEditing = false }
                        } else {
                            openTile = tile
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.45) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(duration: 0.3)) { isEditing = true }
                    }
            }
        }
        .animation(.spring(duration: 0.45), value: store.tiles)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .lineLimit(1...5)
                .focused($promptFocused)
                .submitLabel(.send)

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 29))
                    .foregroundStyle(canSubmit ? Theme.accent : Theme.hairline)
            }
            .disabled(!canSubmit)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 9)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var canSubmit: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && session.phase != .working
    }

    private var placeholder: String {
        if session.phase == .working { return "building, steer it above" }
        return store.tiles.isEmpty ? "what do you need?" : "ask for another, or change one"
    }

    private func submit() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        prompt = ""
        promptFocused = false
        Task { await session.run(prompt: text) }
    }

    /// Launch-time hooks so a run can be rehearsed from the command line.
    private func rehearse() {
        if !credentials.isConfigured { showSettings = true }
        let defaults = UserDefaults.standard
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

        // A follow-up turn in the same session, to rehearse the change flow
        // (the conversation tail lives in memory, so it needs one launch).
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

/// One home-grid icon. It breathes while Astra is still authoring the app behind
/// it, and jiggles with a delete badge in edit mode, the way iOS does.
struct TileView: View {
    let tile: Tile
    let isEditing: Bool
    let onDelete: () -> Void

    @State private var breathing = false
    @State private var jiggle = false

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color(hex: tile.bg))
                    .frame(width: 62, height: 62)
                    .overlay(
                        Image(systemName: tile.symbol)
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    )
                    .opacity(tile.isSettling && breathing ? 0.45 : 1)
                    .scaleEffect(tile.isSettling && breathing ? 0.96 : 1)
                    .animation(
                        tile.isSettling
                            ? .easeInOut(duration: 0.85).repeatForever(autoreverses: true)
                            : .spring(duration: 0.4),
                        value: breathing
                    )

                if isEditing && !tile.isSettling {
                    Button(action: onDelete) {
                        Image(systemName: "minus")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.black)
                            .frame(width: 22, height: 22)
                            .background(.white, in: Circle())
                            .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 0.5))
                    }
                    .offset(x: -7, y: -7)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .rotationEffect(.degrees(isEditing && !tile.isSettling ? (jiggle ? 1.6 : -1.6) : 0))
            .animation(
                isEditing
                    ? .easeInOut(duration: 0.13).repeatForever(autoreverses: true)
                    : .default,
                value: jiggle
            )

            Text(tile.name)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: 68)
        .onAppear {
            breathing = tile.isSettling
            jiggle = isEditing
        }
        .onChange(of: tile.isSettling) { _, settling in breathing = settling }
        .onChange(of: isEditing) { _, editing in jiggle = editing }
    }
}

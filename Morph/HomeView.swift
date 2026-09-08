import SwiftUI

struct HomeView: View {
    @StateObject private var store = TileStore()
    @StateObject private var session: AstraSession
    @ObservedObject private var credentials = Credentials.shared

    @State private var prompt = ""
    @State private var openTile: Tile?
    @State private var showSettings = false
    @FocusState private var promptFocused: Bool

    init() {
        let store = TileStore()
        _store = StateObject(wrappedValue: store)
        _session = StateObject(wrappedValue: AstraSession(store: store))
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 18), count: 4)

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if store.tiles.isEmpty && session.events.isEmpty {
                    emptyState
                } else {
                    grid
                }

                Spacer(minLength: 12)

                if session.phase == .working || !session.events.isEmpty {
                    BuildStripView(session: session)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                composer
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(item: $openTile) { tile in
            AppWebView(tile: tile)
        }
        .onAppear {
            if !credentials.isConfigured { showSettings = true }
            // Rehearsal hook: `-morphPrompt "..."` at launch runs a turn without
            // typing, so the flow can be exercised from the command line.
            if let seeded = UserDefaults.standard.string(forKey: "morphPrompt"), !seeded.isEmpty {
                Task { await session.run(prompt: seeded) }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Morph")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("No apps yet")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
            Text("Say what you need and it becomes an app.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(store.tiles) { tile in
                    TileView(tile: tile)
                        .onTapGesture {
                            guard !tile.isSettling else { return }
                            openTile = tile
                        }
                        .contextMenu {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                store.remove(tile.id)
                            }
                        }
                }
            }
            .padding(.horizontal, 22)
            .animation(.spring(duration: 0.45), value: store.tiles)
        }
    }

    private var composer: some View {
        HStack(spacing: 12) {
            TextField(placeholder, text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .lineLimit(1...4)
                .focused($promptFocused)
                .disabled(session.phase == .working)

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(prompt.isEmpty ? Theme.hairline : Theme.accent)
            }
            .disabled(prompt.isEmpty || session.phase == .working)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var placeholder: String {
        session.phase == .working ? "building, steer it above" : "what do you need?"
    }

    private func submit() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        prompt = ""
        promptFocused = false
        Task { await session.run(prompt: text) }
    }
}

/// One home-grid icon. While Astra is still authoring the app behind it, the
/// tile breathes, so the user can see it is not finished.
struct TileView: View {
    let tile: Tile
    @State private var breathing = false

    var body: some View {
        VStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color(hex: tile.bg))
                .frame(width: 62, height: 62)
                .overlay(
                    Image(systemName: tile.symbol)
                        .font(.system(size: 27, weight: .medium))
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

            Text(tile.name)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .onAppear { breathing = tile.isSettling }
        .onChange(of: tile.isSettling) { _, settling in breathing = settling }
    }
}


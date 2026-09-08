import SwiftUI

/// A window onto Astra's actual work. Every row here is a model event or a
/// tool Morph really ran, in the order it happened.
struct BuildStripView: View {
    @ObservedObject var session: AstraSession
    @State private var steerText = ""
    @FocusState private var steerFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(session.events) { event in
                            row(event)
                                .id(event.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(16)
                }
                .frame(maxHeight: 240)
                .onChange(of: session.events.count) {
                    withAnimation(.spring(duration: 0.35)) {
                        proxy.scrollTo(session.events.last?.id, anchor: .bottom)
                    }
                }
            }

            if session.canSteer {
                Divider().overlay(Theme.hairline)
                steerBar
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(session.canSteer ? Theme.steer.opacity(0.35) : Theme.hairline, lineWidth: 1)
        )
    }

    private func row(_ event: BuildEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.glyph)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint(event.kind))
                .frame(width: 16, height: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.text)
                    .font(.system(size: 14, weight: event.kind == .reasoning ? .regular : .medium))
                    .foregroundStyle(event.kind == .reasoning ? Theme.dim : .white)
                if let detail = event.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func tint(_ kind: BuildEvent.Kind) -> Color {
        switch kind {
        case .reasoning: return Theme.dim
        case .tool: return Theme.accent
        case .toolDone: return .green
        case .steer: return Theme.steer
        case .done: return .green
        case .error: return .orange
        }
    }

    /// The interrupt. Sending here does not cancel the build; Astra keeps
    /// whatever it has already finished and folds this in.
    private var steerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.steer)
            TextField("change it while it builds", text: $steerText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .focused($steerFocused)
                .submitLabel(.send)
                .onSubmit(sendSteer)
            Button(action: sendSteer) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(steerText.isEmpty ? Theme.hairline : Theme.steer)
            }
            .disabled(steerText.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func sendSteer() {
        let text = steerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        session.steer(text)
        steerText = ""
    }
}

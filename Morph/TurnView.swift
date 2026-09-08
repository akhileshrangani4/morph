import SwiftUI

/// One exchange in the conversation: what was said, then what Astra did about
/// it. Every row under a prompt is a real model event or a tool Morph ran.
struct TurnView: View {
    let turn: Turn

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            said
            if !turn.events.isEmpty {
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(turn.events) { event in
                        row(event)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .padding(.leading, 2)
            }
        }
    }

    private var said: some View {
        HStack {
            Spacer(minLength: 40)
            VStack(alignment: .trailing, spacing: 3) {
                if turn.isSteer {
                    Label("mid-build", systemImage: "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.steer)
                }
                Text(turn.prompt)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        (turn.isSteer ? Theme.steer.opacity(0.16) : Color(white: 0.16)),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(turn.isSteer ? Theme.steer.opacity(0.4) : .clear, lineWidth: 1)
                    )
            }
        }
    }

    private func row(_ event: BuildEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.glyph)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint(event.kind))
                .frame(width: 15, height: 15)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.text)
                    .font(.system(size: 14, weight: weight(event.kind)))
                    .foregroundStyle(event.kind == .reasoning ? Theme.dim : .white)
                if let detail = event.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(event.kind == .error ? .orange.opacity(0.9) : Theme.dim)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func weight(_ kind: BuildEvent.Kind) -> Font.Weight {
        switch kind {
        case .reasoning: return .regular
        case .done: return .semibold
        default: return .medium
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
}

/// The interrupt. Sending here does not cancel the build: Astra keeps whatever
/// it has already finished and folds the change into the rest.
struct SteerBar: View {
    @ObservedObject var session: AstraSession
    @State private var text = ""

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.steer)
            TextField("change it while it builds", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .submitLabel(.send)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(text.isEmpty ? Theme.hairline : Theme.steer)
            }
            .disabled(text.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.steer.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(Theme.steer.opacity(0.45), lineWidth: 1))
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session.steer(trimmed)
        text = ""
    }
}

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
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        (turn.isSteer ? Theme.accentSoft : Theme.raised),
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
                    .foregroundStyle(event.kind == .reasoning ? Theme.dim : Theme.ink)
                if let detail = event.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(event.kind == .error ? Theme.warn : Theme.dim)
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
        case .reasoning: return Theme.faint
        case .tool: return Theme.accent
        case .toolDone: return Theme.ok
        case .steer: return Theme.accent
        case .done: return Theme.ok
        case .error: return Theme.warn
        }
    }
}

import SwiftUI

/// What you watch while Astra builds. One line of what it is doing right now,
/// a light sweeping over the pill, and a way in if you want the full trace.
struct BuildingView: View {
    let line: String
    let isExpanded: Bool
    let onToggle: () -> Void

    @State private var sweep: CGFloat = -1
    @State private var arc = false

    var body: some View {
        HStack(spacing: 12) {
            spinner

            Text(line)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .id(line)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: line)

            Spacer(minLength: 0)

            Button(action: onToggle) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.06), in: Circle())
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .background {
            ZStack {
                Capsule().fill(Theme.surface)
                // A light travelling the length of the pill, so the wait reads
                // as work in progress rather than a stall.
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.clear, Theme.accent.opacity(0.30), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .scaleEffect(x: 0.45, anchor: .leading)
                    .offset(x: sweep * 240)
                    .clipShape(Capsule())
            }
        }
        .overlay(Capsule().stroke(Theme.accent.opacity(0.28), lineWidth: 1))
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                sweep = 1.6
            }
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                arc = true
            }
        }
    }

    private var spinner: some View {
        Circle()
            .trim(from: 0, to: 0.22)
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            .frame(width: 15, height: 15)
            .rotationEffect(.degrees(arc ? 360 : 0))
    }
}

/// The ring that orbits a tile while the app behind it is still being written.
struct SettlingRing: View {
    @State private var spin = false

    var body: some View {
        RoundedRectangle(cornerRadius: 17, style: .continuous)
            .strokeBorder(
                AngularGradient(
                    gradient: Gradient(colors: [
                        .clear, Theme.accent.opacity(0.15), Theme.accent, .white, Theme.accent, .clear,
                    ]),
                    center: .center
                ),
                lineWidth: 2.5
            )
            .rotationEffect(.degrees(spin ? 360 : 0))
            .shadow(color: Theme.accent.opacity(0.45), radius: 7)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    spin = true
                }
            }
    }
}

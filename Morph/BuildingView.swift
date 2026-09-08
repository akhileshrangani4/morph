import SwiftUI

/// The whole screen while Astra builds. The app being made is the subject:
/// its icon and name sit in the middle, slow ripples widen behind it, and one
/// line underneath says what is happening right now. Nothing else competes.
struct BuildingScreen: View {
    let tile: Tile?
    let line: String

    @State private var ripple = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(Theme.accent.opacity(0.55), lineWidth: 1)
                        .frame(width: 96, height: 96)
                        .scaleEffect(ripple ? 4.2 : 1)
                        .opacity(ripple ? 0 : 0.9)
                        .animation(
                            .easeOut(duration: 3.6)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 1.2),
                            value: ripple
                        )
                }

                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(tile.map { Color(hex: $0.bg) } ?? Theme.raised)
                    .frame(width: 96, height: 96)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Theme.ink.opacity(0.10), lineWidth: 1)
                    )
                    .overlay {
                        if let tile {
                            Image(systemName: tile.symbol)
                                .font(.system(size: 40, weight: .medium))
                                .foregroundStyle(Theme.ink)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        } else {
                            Circle()
                                .fill(Theme.accent)
                                .frame(width: 10, height: 10)
                        }
                    }
                    .animation(.easeOut(duration: 0.4), value: tile?.id)
            }
            .frame(height: 320)

            Text(tile?.name ?? "Listening")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.3), value: tile?.name)
                .padding(.top, 6)

            Text(line)
                .font(.system(size: 15))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 300)
                .id(line)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.25), value: line)
                .padding(.top, 10)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear { ripple = true }
    }
}

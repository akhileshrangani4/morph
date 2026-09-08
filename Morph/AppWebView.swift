import SwiftUI
import WebKit

/// The generated app itself, hosted on Charming, rendered full screen.
struct AppWebView: View {
    let tile: Tile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: tile.bg).ignoresSafeArea()
            CharmingWebView(appID: tile.id)
                .ignoresSafeArea(edges: .bottom)

            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(9)
                        .background(.black.opacity(0.45), in: Circle())
                }
                Text(tile.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 6)
                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .preferredColorScheme(.dark)
    }
}

struct CharmingWebView: UIViewRepresentable {
    let appID: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        let client = CharmingClient(token: Credentials.shared.charmingToken)
        view.load(client.webViewRequest(appID: appID))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}

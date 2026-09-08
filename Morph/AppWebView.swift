import SwiftUI
import WebKit

/// The generated app itself, hosted on Charming, rendered full screen.
struct AppWebView: View {
    let tile: Tile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // A bar above the app rather than floating over it: the generated
            // app draws its own header, and an overlay collided with it.
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.12), in: Circle())
                }
                Text(tile.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: tile.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink.opacity(0.55))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .background(Color(hex: tile.bg))

            CharmingWebView(appID: tile.id)
        }
        .background(Color(hex: tile.bg))
        .preferredColorScheme(.dark)
    }
}

struct CharmingWebView: UIViewRepresentable {
    let appID: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        // The hosted page ships its own chrome: a floating widget in the corner
        // and an "add to Home Screen" hint. Inside Morph the app already is the
        // home screen, so both go. The host marks its chrome with data-chrm-*.
        let hideShell = """
        (function () {
          const css = '#charming-widget-root, [data-chrm-install-hint], [data-chrm-app-settings-bottom] { display: none !important; }';
          const style = document.createElement('style');
          style.textContent = css;
          (document.head || document.documentElement).appendChild(style);
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: hideShell, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
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

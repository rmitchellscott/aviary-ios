import SwiftUI

struct ContentView: View {
    var network = NetworkMonitor.shared
    var shareState: ShareState
    @State private var showQueuedBanner = false
    @AppStorage("server_url") private var serverURL: String = ""
    private var isOffline: Bool {
        !network.isConnected
    }

    private var trimmedServerURL: String? {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        Group {
            if let serverURL = trimmedServerURL {
                ZStack(alignment: .top) {
                    WebView(serverURL: serverURL, shareItem: shareState.pendingItem, isOffline: isOffline)

                    if showQueuedBanner {
                        queuedBanner
                    }
                }
                .ignoresSafeArea()
            } else {
                noServerView
            }
        }
    }

    private var noServerView: some View {
        VStack(spacing: 16) {
            Image(systemName: "gear")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Server Configured")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Open iOS Settings \u{2192} Aviary to set your server URL.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var queuedBanner: some View {
        Text("Queued \u{2014} will send when online")
            .font(.subheadline)
            .fontWeight(.medium)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { showQueuedBanner = false }
                }
            }
    }

}

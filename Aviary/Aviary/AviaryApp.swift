import SwiftUI
import UserNotifications

@Observable
final class ShareState {
    var pendingItem: QueueItem?
}

@main
struct AviaryApp: App {
    @State private var shareState = ShareState()

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(shareState: shareState)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        print("[Aviary] handleIncomingURL: \(url)")
        guard url.scheme == "aviary", url.host == "share" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let idString = components.queryItems?.first(where: { $0.name == "id" })?.value,
              let uuid = UUID(uuidString: idString) else { return }

        print("[Aviary] Looking up queue item: \(uuid)")
        guard let item = UploadQueue.shared.item(for: uuid) else {
            print("[Aviary] Queue item NOT found for \(uuid)")
            return
        }
        print("[Aviary] Found queue item: type=\(item.type), filename=\(item.filename ?? "nil")")
        shareState.pendingItem = item
    }
}

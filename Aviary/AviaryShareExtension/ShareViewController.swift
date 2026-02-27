import UIKit
import UniformTypeIdentifiers
import Network

class ShareViewController: UIViewController {
    private let queue = UploadQueue.shared
    private let statusLabel = UILabel()
    private var queuedItems: [QueueItem] = []
    private var pendingLoads = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)

        statusLabel.text = "Preparing…"
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        processInputItems()
    }

    private func processInputItems() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            dismiss()
            return
        }

        var providers: [(NSItemProvider, String)] = []

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                let fileTypes = [UTType.pdf, UTType.image, UTType.epub, UTType.html, UTType("net.daringfireball.markdown")].compactMap { $0 }
                var matched = false
                for type in fileTypes {
                    if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                        providers.append((provider, type.identifier))
                        matched = true
                        break
                    }
                }
                if matched { continue }
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    providers.append((provider, UTType.fileURL.identifier))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    providers.append((provider, UTType.url.identifier))
                }
            }
        }

        if providers.isEmpty {
            dismiss()
            return
        }

        pendingLoads = providers.count
        for (provider, typeId) in providers {
            if typeId == UTType.url.identifier {
                loadURL(provider)
            } else {
                loadFile(provider, typeIdentifier: typeId)
            }
        }
    }

    private func loadURL(_ provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
            guard let self else { return }
            if let url = item as? URL {
                let queueItem = QueueItem(
                    id: UUID(), type: .url, url: url.absoluteString,
                    filename: nil, mimeType: nil, createdAt: Date(), status: .pending
                )
                self.queue.enqueue(queueItem)
                self.itemLoaded(queueItem)
            } else if let str = item as? String {
                let queueItem = QueueItem(
                    id: UUID(), type: .url, url: str,
                    filename: nil, mimeType: nil, createdAt: Date(), status: .pending
                )
                self.queue.enqueue(queueItem)
                self.itemLoaded(queueItem)
            } else {
                self.itemLoaded(nil)
            }
        }
    }

    private func loadFile(_ provider: NSItemProvider, typeIdentifier: String) {
        provider.loadItem(forTypeIdentifier: typeIdentifier) { [weak self] item, _ in
            guard let self else { return }
            let fileURL: URL?
            if let url = item as? URL {
                fileURL = url
            } else if let data = item as? Data {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try? data.write(to: tmp)
                fileURL = tmp
            } else {
                self.itemLoaded(nil)
                return
            }
            guard let fileURL, let data = try? Data(contentsOf: fileURL) else {
                self.itemLoaded(nil)
                return
            }

            let queueItem = QueueItem(
                id: UUID(), type: .file, url: nil,
                filename: fileURL.lastPathComponent,
                mimeType: Self.mimeType(for: fileURL),
                createdAt: Date(), status: .pending
            )
            self.queue.enqueue(queueItem, fileData: data)
            self.itemLoaded(queueItem)
        }
    }

    private func itemLoaded(_ item: QueueItem?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let item { queuedItems.append(item) }
            pendingLoads -= 1
            if pendingLoads <= 0 {
                allItemsLoaded()
            }
        }
    }

    private func allItemsLoaded() {
        guard !queuedItems.isEmpty else {
            dismiss()
            return
        }

        let monitor = NWPathMonitor()
        let semaphore = DispatchSemaphore(value: 0)
        var isOnline = false
        monitor.pathUpdateHandler = { path in
            isOnline = path.status == .satisfied
            semaphore.signal()
        }
        let monitorQueue = DispatchQueue(label: "share.netcheck")
        monitor.start(queue: monitorQueue)
        _ = semaphore.wait(timeout: .now() + 1.0)
        monitor.cancel()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if isOnline, let first = queuedItems.first {
                let urlStr = "aviary://share?id=\(first.id.uuidString)"
                if let url = URL(string: urlStr) {
                    openURL(url)
                }
                dismiss()
            } else {
                let count = queuedItems.count
                statusLabel.text = count == 1 ? "Queued for later" : "\(count) items queued"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.dismiss()
                }
            }
        }
    }

    @objc private func openURL(_ url: URL) {
        var responder: UIResponder? = self
        while let r = responder {
            if let application = r as? UIApplication {
                application.open(url)
                return
            }
            responder = r.next
        }
        let selector = sel_registerName("openURL:")
        var current: UIResponder? = self
        while let r = current {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                return
            }
            current = r.next
        }
    }

    private func dismiss() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private static func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "application/pdf"
        case "epub": return "application/epub+zip"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "html", "htm": return "text/html"
        case "md", "markdown": return "text/markdown"
        default: return "application/octet-stream"
        }
    }
}

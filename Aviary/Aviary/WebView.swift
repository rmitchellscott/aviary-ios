import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let serverURL: String
    var shareItem: QueueItem?
    var isOffline: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.add(context.coordinator, name: "aviary")

        let nativeAppFlag = WKUserScript(
            source: "document.documentElement.classList.add('native-app');",
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(nativeAppFlag)


        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        context.coordinator.webView = webView

        if isOffline {
            context.coordinator.loadOfflinePage(webView)
        } else if let url = URL(string: serverURL) {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let wasOffline = context.coordinator.showingOffline
        let nowOffline = isOffline

        if serverURL != context.coordinator.loadedServerURL {
            context.coordinator.loadedServerURL = serverURL
            if !nowOffline, let url = URL(string: serverURL) {
                webView.load(URLRequest(url: url))
            }
            return
        }

        if wasOffline && !nowOffline {
            context.coordinator.showingOffline = false
            if let url = URL(string: serverURL) {
                webView.load(URLRequest(url: url))
            }
        } else if !wasOffline && nowOffline {
            context.coordinator.loadOfflinePage(webView)
        }

        if nowOffline {
            context.coordinator.updateOfflinePendingItems(webView)
        }

        if let item = shareItem, item.id != context.coordinator.lastInjectedItemID {
            context.coordinator.lastInjectedItemID = item.id
            if nowOffline {
                context.coordinator.updateOfflinePendingItems(webView)
            } else {
                context.coordinator.injectAllPendingFiles(into: webView)
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: WebView
        weak var webView: WKWebView?
        var lastInjectedItemID: UUID?
        var showingOffline = false
        var loadedServerURL: String

        init(_ parent: WebView) {
            self.parent = parent
            self.loadedServerURL = parent.serverURL
        }

        func loadOfflinePage(_ webView: WKWebView) {
            showingOffline = true
            guard let path = Bundle.main.path(forResource: "offline", ofType: "html") else { return }
            let url = URL(fileURLWithPath: path)
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        func updateOfflinePendingItems(_ webView: WKWebView) {
            let items = UploadQueue.shared.listPending()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let json = try? encoder.encode(items),
                  let jsonString = String(data: json, encoding: .utf8) else { return }
            let js = "if (typeof window.aviaryOfflineSetItems === 'function') { window.aviaryOfflineSetItems(\(jsonString)); }"
            webView.evaluateJavaScript(js)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if showingOffline {
                updateOfflinePendingItems(webView)
            } else {
                AuthManager.shared.syncCookies(from: webView)
                injectAllPendingFiles(into: webView)
            }
        }

        func injectAllPendingFiles(into webView: WKWebView) {
            let pending = UploadQueue.shared.listPending()
            let fileItems = pending.filter { $0.type == .file }
            let urlItems = pending.filter { $0.type == .url }

            guard !fileItems.isEmpty || !urlItems.isEmpty else { return }
            print("[Aviary] Injecting \(fileItems.count) files, \(urlItems.count) URLs from queue")

            injectWhenReady(fileItems: fileItems, urlItems: urlItems, into: webView, attempts: 0)
        }

        private func injectWhenReady(fileItems: [QueueItem], urlItems: [QueueItem], into webView: WKWebView, attempts: Int) {
            let checkJS = "typeof window.aviaryInjectFiles === 'function'"
            webView.evaluateJavaScript(checkJS) { [weak self] result, _ in
                if let ready = result as? Bool, ready {
                    self?.doBatchInject(fileItems: fileItems, urlItems: urlItems, into: webView)
                } else if attempts < 20 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        self?.injectWhenReady(fileItems: fileItems, urlItems: urlItems, into: webView, attempts: attempts + 1)
                    }
                }
            }
        }

        private func doBatchInject(fileItems: [QueueItem], urlItems: [QueueItem], into webView: WKWebView) {
            if !fileItems.isEmpty {
                var jsArray: [String] = []
                for item in fileItems {
                    guard let data = UploadQueue.shared.fileData(for: item.id),
                          let filename = item.filename,
                          let mimeType = item.mimeType else { continue }
                    UploadQueue.shared.removeItem(item.id)
                    let base64 = data.base64EncodedString()
                    let escapedFilename = filename.replacingOccurrences(of: "'", with: "\\'")
                    jsArray.append("['\(base64)', '\(escapedFilename)', '\(mimeType)']")
                }
                if !jsArray.isEmpty {
                    let js = "window.aviaryInjectFiles([\(jsArray.joined(separator: ","))]);"
                    webView.evaluateJavaScript(js)
                }
            }

            if let urlItem = urlItems.first {
                injectShareItem(urlItem, into: webView)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            if nsError.code == NSURLErrorNotConnectedToInternet ||
               nsError.code == NSURLErrorTimedOut ||
               nsError.code == NSURLErrorCannotConnectToHost {
                loadOfflinePage(webView)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            if nsError.code == NSURLErrorNotConnectedToInternet ||
               nsError.code == NSURLErrorTimedOut ||
               nsError.code == NSURLErrorCannotConnectToHost ||
               nsError.code == NSURLErrorCannotFindHost {
                loadOfflinePage(webView)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url,
               url.scheme == "blob" || navigationAction.navigationType == .linkActivated,
               let host = url.host,
               let serverHost = URL(string: parent.serverURL)?.host,
               host != serverHost {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        }

        func injectShareItem(_ item: QueueItem, into webView: WKWebView) {
            print("[Aviary] injectShareItem called: type=\(item.type), id=\(item.id)")
            switch item.type {
            case .url:
                guard let urlString = item.url else { return }
                UploadQueue.shared.removeItem(item.id)
                let escaped = urlString.replacingOccurrences(of: "'", with: "\\'")
                let js = """
                (function() {
                    const params = new URLSearchParams(window.location.search);
                    params.set('share_url', '\(escaped)');
                    window.history.replaceState({}, '', '?' + params.toString());
                    window.dispatchEvent(new PopStateEvent('popstate'));
                    window.dispatchEvent(new CustomEvent('aviary-share-url', { detail: '\(escaped)' }));
                })();
                """
                webView.evaluateJavaScript(js)

            case .file:
                guard let data = UploadQueue.shared.fileData(for: item.id),
                      let filename = item.filename,
                      let mimeType = item.mimeType else {
                    print("[Aviary] File inject failed: data=\(UploadQueue.shared.fileData(for: item.id) != nil), filename=\(item.filename ?? "nil"), mimeType=\(item.mimeType ?? "nil")")
                    return
                }
                UploadQueue.shared.removeItem(item.id)
                print("[Aviary] Injecting file: \(filename), \(mimeType), \(data.count) bytes")
                let base64 = data.base64EncodedString()
                let escapedFilename = filename.replacingOccurrences(of: "'", with: "\\'")
                let js = """
                if (typeof window.aviaryInjectFile === 'function') {
                    window.aviaryInjectFile('\(base64)', '\(escapedFilename)', '\(mimeType)');
                }
                """
                webView.evaluateJavaScript(js)
            }
        }
    }
}

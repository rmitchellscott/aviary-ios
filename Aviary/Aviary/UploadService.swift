import Foundation
import Observation
import UserNotifications

@Observable
final class UploadService {
    static let shared = UploadService()

    private(set) var isDraining = false

    private let uploadQueue = UploadQueue.shared
    private let auth = AuthManager.shared
    private let network = NetworkMonitor.shared

    private init() {
        startMonitoring()
    }

    private func startMonitoring() {
        Task {
            while true {
                try? await Task.sleep(for: .seconds(5))
                if network.isConnected {
                    await drainQueue()
                }
            }
        }
    }

    func drainQueue() async {
        guard !isDraining else { return }
        guard network.isConnected else { return }
        guard let serverURL = auth.serverURL, !serverURL.isEmpty else { return }

        isDraining = true
        defer { isDraining = false }

        let pending = uploadQueue.listPending()
        for item in pending {
            do {
                uploadQueue.updateStatus(item.id, status: .uploading)
                try await upload(item, serverURL: serverURL)
                uploadQueue.markCompleted(item.id)
                uploadQueue.removeItem(item.id)
            } catch {
                uploadQueue.markFailed(item.id)
                sendNotification(title: "Upload Failed", body: item.filename ?? item.url ?? "Unknown item")
            }
        }
    }

    private func upload(_ item: QueueItem, serverURL: String) async throws {
        switch item.type {
        case .url:
            try await uploadURL(item, serverURL: serverURL)
        case .file:
            try await uploadFile(item, serverURL: serverURL)
        }
    }

    private func uploadURL(_ item: QueueItem, serverURL: String) async throws {
        guard let urlString = item.url else { return }
        let endpoint = URL(string: "\(serverURL)/api/webhook")!

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        auth.applyAuth(to: &request)

        let body = "Body=\(urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)"
        request.httpBody = Data(body.utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func uploadFile(_ item: QueueItem, serverURL: String) async throws {
        guard let data = uploadQueue.fileData(for: item.id) else { return }
        let endpoint = URL(string: "\(serverURL)/api/upload")!

        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        auth.applyAuth(to: &request)

        var body = Data()
        let filename = item.filename ?? "file"
        let mimeType = item.mimeType ?? "application/octet-stream"

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")

        request.httpBody = body

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

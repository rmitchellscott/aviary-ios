import Foundation

final class UploadQueue {
    static let shared = UploadQueue()

    private let fileManager = FileManager.default

    private var queueDirectory: URL {
        let groupContainer = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.io.scottlabs.aviary")
        print("[Aviary] App Group container: \(groupContainer?.path ?? "NIL")")
        let container = groupContainer ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = container.appendingPathComponent("Library/queue", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        print("[Aviary] Queue directory: \(dir.path)")
        return dir
    }

    private init() {}

    func enqueue(_ item: QueueItem, fileData: Data? = nil) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let json = try? encoder.encode(item) else { return }

        let jsonPath = queueDirectory.appendingPathComponent("\(item.id.uuidString).json")
        try? json.write(to: jsonPath)

        if let fileData {
            let dataPath = queueDirectory.appendingPathComponent("\(item.id.uuidString).dat")
            try? fileData.write(to: dataPath)
        }
    }

    func listPending() -> [QueueItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let files = try? fileManager.contentsOfDirectory(at: queueDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(QueueItem.self, from: $0) }
            .filter { $0.status == .pending || $0.status == .failed }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func item(for id: UUID) -> QueueItem? {
        let path = queueDirectory.appendingPathComponent("\(id.uuidString).json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? decoder.decode(QueueItem.self, from: data)
    }

    func fileData(for id: UUID) -> Data? {
        let path = queueDirectory.appendingPathComponent("\(id.uuidString).dat")
        return try? Data(contentsOf: path)
    }

    func updateStatus(_ id: UUID, status: QueueItem.QueueStatus) {
        let path = queueDirectory.appendingPathComponent("\(id.uuidString).json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var item = (try? Data(contentsOf: path)).flatMap({ try? decoder.decode(QueueItem.self, from: $0) }) else { return }

        item.status = status
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let json = try? encoder.encode(item) else { return }
        try? json.write(to: path)
    }

    func markCompleted(_ id: UUID) {
        updateStatus(id, status: .completed)
    }

    func markFailed(_ id: UUID) {
        updateStatus(id, status: .failed)
    }

    func removeItem(_ id: UUID) {
        let jsonPath = queueDirectory.appendingPathComponent("\(id.uuidString).json")
        let dataPath = queueDirectory.appendingPathComponent("\(id.uuidString).dat")
        try? fileManager.removeItem(at: jsonPath)
        try? fileManager.removeItem(at: dataPath)
    }
}

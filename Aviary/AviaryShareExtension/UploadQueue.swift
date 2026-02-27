import Foundation

final class UploadQueue {
    static let shared = UploadQueue()

    private let fileManager = FileManager.default

    private var queueDirectory: URL {
        let groupContainer = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.io.scottlabs.aviary")
        print("[AviaryExt] App Group container: \(groupContainer?.path ?? "NIL")")
        let container = groupContainer ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = container.appendingPathComponent("Library/queue", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        print("[AviaryExt] Queue directory: \(dir.path)")
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

    func item(for id: UUID) -> QueueItem? {
        let path = queueDirectory.appendingPathComponent("\(id.uuidString).json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? decoder.decode(QueueItem.self, from: data)
    }
}

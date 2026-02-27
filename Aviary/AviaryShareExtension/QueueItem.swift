import Foundation

struct QueueItem: Codable, Identifiable {
    let id: UUID
    let type: ShareType
    let url: String?
    let filename: String?
    let mimeType: String?
    let createdAt: Date
    var status: QueueStatus

    enum ShareType: String, Codable { case url, file }
    enum QueueStatus: String, Codable { case pending, uploading, completed, failed }
}

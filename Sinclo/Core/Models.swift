import Foundation

struct Rule: Codable {
    var minSizeMB: UInt64? // optional
    var maxSizeMB: UInt64? // optional
    var allowedExtensions: [String]?
    var treatFolderAsUnit: Bool = false
}

struct SyncTask: Identifiable {
    let id = UUID()
    let localURL: URL
    let destinationURL: URL
    var state: SyncState = .pending
}

enum SyncState {
    case pending, uploading, completed, failed
}

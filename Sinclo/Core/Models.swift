import Foundation

enum SizeUnit: String, Codable, CaseIterable {
    case kb = "KB"
    case mb = "MB"
    case gb = "GB"

    var multiplier: UInt64 {
        switch self {
        case .kb: return 1024
        case .mb: return 1024 * 1024
        case .gb: return 1024 * 1024 * 1024
        }
    }
}

struct Rule: Codable, Identifiable {
    let id = UUID()
    var lowerBound: UInt64 = 0
    var upperBound: UInt64 = 100
    var unit: SizeUnit = .mb
    var allowedExtensions: [String]?
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

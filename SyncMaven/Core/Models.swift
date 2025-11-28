
import Foundation

enum SizeUnit: String, Codable, CaseIterable {
    case B, KB, MB, GB
    
    var multiplier: UInt64 {
        switch self {
        case .B: return 1
        case .KB: return 1024
        case .MB: return 1024 * 1024
        case .GB: return 1024 * 1024 * 1024
        }
    }
}

struct Rule: Identifiable, Codable, Equatable {
    var id = UUID()
    var lowerBound: UInt64 = 0
    var upperBound: UInt64 = 100
    var unit: SizeUnit = .MB
    
    // New: Explicit Ignore List
    var ignoredExtensions: [String] = []
    
    // New: Common file types for dropdown suggestions
    static let commonExtensions = ["dmg", "iso", "zip", "app", "txt", "pdf", "jpg", "png", "mov", "mp4"]
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

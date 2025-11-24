import Foundation
import  Combine
class WatchedFolder: ObservableObject, Identifiable, Codable {

    // MARK: Codable Keys
    enum CodingKeys: String, CodingKey {
        case id
        case localPath
        case maxSizeMB
        case enabled
        case driveFolder
        case driveFolderName
    }

    // MARK: Properties
    let id: UUID
    @Published var localPath: String
    @Published var maxSizeMB: Int
    @Published var enabled: Bool
    @Published var driveFolder: DriveFolder? {
        didSet { driveFolderName = driveFolder?.name }
    }
    @Published var driveFolderName: String?

    // MARK: Normal Init
    init(path: String) {
        self.id = UUID()
        self.localPath = path
        self.maxSizeMB = 200
        self.enabled = true
        self.driveFolder = nil
        self.driveFolderName = nil
    }

    // MARK: Codable Init
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: .id)
        self.localPath = try container.decode(String.self, forKey: .localPath)
        self.maxSizeMB = try container.decode(Int.self, forKey: .maxSizeMB)
        self.enabled = try container.decode(Bool.self, forKey: .enabled)

        self.driveFolder = try container.decodeIfPresent(DriveFolder.self, forKey: .driveFolder)
        self.driveFolderName = try container.decodeIfPresent(String.self, forKey: .driveFolderName)
    }

    // MARK: Encode
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(localPath, forKey: .localPath)
        try container.encode(maxSizeMB, forKey: .maxSizeMB)
        try container.encode(enabled, forKey: .enabled)
        try container.encodeIfPresent(driveFolder, forKey: .driveFolder)
        try container.encodeIfPresent(driveFolderName, forKey: .driveFolderName)
    }
}

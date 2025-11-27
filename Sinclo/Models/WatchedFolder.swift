import Foundation
import Combine

class WatchedFolder: ObservableObject, Identifiable, Codable {

    // MARK: Codable Keys
    enum CodingKeys: String, CodingKey {
        case id, localPath, enabled, driveFolder, driveFolderName, bookmarkData, rules, accountID, syncedFiles
    }

    // MARK: Properties
    let id: UUID
    @Published var localPath: String
    @Published var enabled: Bool
    @Published var driveFolder: DriveFolder? {
        didSet { driveFolderName = driveFolder?.name }
    }
    @Published var driveFolderName: String?
    var bookmarkData: Data?
    @Published var rules: [Rule] = [Rule()]
    @Published var accountID: String?
    @Published var syncedFiles: [String: String] = [:]

    // MARK: Normal Init
    init(localPath: String, bookmarkData: Data?) {
        self.id = UUID()
        self.localPath = localPath
        self.enabled = true
        self.driveFolder = nil
        self.driveFolderName = nil
        self.bookmarkData = bookmarkData
    }

    // MARK: Codable Init
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        localPath = try container.decode(String.self, forKey: .localPath)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        driveFolder = try container.decodeIfPresent(DriveFolder.self, forKey: .driveFolder)
        driveFolderName = try container.decodeIfPresent(String.self, forKey: .driveFolderName)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        rules = try container.decodeIfPresent([Rule].self, forKey: .rules) ?? [Rule()]
        accountID = try container.decodeIfPresent(String.self, forKey: .accountID)
        syncedFiles = try container.decodeIfPresent([String: String].self, forKey: .syncedFiles) ?? [:]
    }

    // MARK: Encode
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(localPath, forKey: .localPath)
        try container.encode(enabled, forKey: .enabled)
        try container.encodeIfPresent(driveFolder, forKey: .driveFolder)
        try container.encodeIfPresent(driveFolderName, forKey: .driveFolderName)
        try container.encodeIfPresent(bookmarkData, forKey: .bookmarkData)
        try container.encode(rules, forKey: .rules)
        try container.encodeIfPresent(accountID, forKey: .accountID)
        try container.encode(syncedFiles, forKey: .syncedFiles)
    }
}

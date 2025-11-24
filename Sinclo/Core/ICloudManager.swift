import Foundation

final class ICloudManager {
    static let shared = ICloudManager()
    private init() {}

    func ubiquityContainerURL() -> URL? {
        return FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents/Sinclo")
    }

    func copyToICloud(localURL: URL) throws -> URL {
        guard let container = ubiquityContainerURL() else { throw NSError(domain: "ICloud", code: 1) }
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true, attributes: nil)
        let dest = container.appendingPathComponent(localURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            // simple conflict resolution: rename with timestamp
            let t = Int(Date().timeIntervalSince1970)
            let newname = "\(localURL.deletingPathExtension().lastPathComponent)-\(t).\(localURL.pathExtension)"
            let newdest = container.appendingPathComponent(newname)
            try FileManager.default.copyItem(at: localURL, to: newdest)
            return newdest
        } else {
            try FileManager.default.copyItem(at: localURL, to: dest)
            return dest
        }
    }
}

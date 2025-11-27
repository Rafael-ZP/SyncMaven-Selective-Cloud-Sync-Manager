import Foundation

final class RuleEngine {
    static func fileMatchesRule(fileURL: URL, rule: Rule) -> Bool {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard let fileSize = attrs[.size] as? UInt64 else { return false }

            let lowerBoundBytes = rule.lowerBound * rule.unit.multiplier
            let upperBoundBytes = rule.upperBound * rule.unit.multiplier

            if fileSize < lowerBoundBytes { return false }
            if fileSize > upperBoundBytes { return false }

            if let exts = rule.allowedExtensions, !exts.isEmpty {
                let fileExt = fileURL.pathExtension.lowercased()
                if !exts.contains(fileExt) { return false }
            }

            return true
        } catch {
            return false
        }
    }

    static func folderTotalSize(url: URL) -> UInt64 {
        var size: UInt64 = 0
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [], errorHandler: nil) {
            for case let f as URL in enumerator {
                do {
                    let attr = try f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    if attr.isRegularFile == true {
                        size += UInt64(attr.fileSize ?? 0)
                    }
                } catch { continue }
            }
        }
        return size
    }
}

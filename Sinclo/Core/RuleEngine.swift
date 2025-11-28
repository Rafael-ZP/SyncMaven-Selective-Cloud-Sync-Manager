// RuleEngine.swift
// Sinclo
// Robust Validation

import Foundation

final class RuleEngine {
    
    /// Determines if a file should be synced based on a list of rules.
    /// Logic: Returns true if the file matches AT LEAST ONE rule.
    /// Edge Case: If a file matches the size rule but is in the ignore list, that specific rule fails.
    ///            If another rule allows it, it passes (OR logic between rules).
    static func fileMatchesRule(fileURL: URL, rule: Rule) -> Bool {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard let fileSize = attrs[.size] as? UInt64 else { return false }
            
            // 1. Check Size
            let lowerBytes = rule.lowerBound * rule.unit.multiplier
            let upperBoundBytes = rule.upperBound * rule.unit.multiplier
            
            // Robustness: Handle if user swaps Min/Max
            let actualMin = min(lowerBytes, upperBoundBytes)
            let actualMax = max(lowerBytes, upperBoundBytes)
            
            if fileSize < actualMin || fileSize > actualMax {
                return false
            }
            
            // 2. Check Ignored Extensions
            let fileExt = fileURL.pathExtension.lowercased()
            if rule.ignoredExtensions.contains(fileExt) {
                return false // Explicitly ignored by this rule
            }
            
            // Note: If you previously had "Allowed Extensions", decide if you want Whitelist or Blacklist.
            // The prompt requested "Ignore file types", so this implies Blacklist logic (Allow all except these).
            
            return true
        } catch {
            return false
        }
    }
    
    /// Helper for folder calculations
    static func folderTotalSize(url: URL) -> UInt64 {
        var size: UInt64 = 0
        let fm = FileManager.default
        // Using NSDirectoryEnumerator is efficient
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                   resourceValues.isRegularFile == true {
                    size += UInt64(resourceValues.fileSize ?? 0)
                }
            }
        }
        return size
    }
}

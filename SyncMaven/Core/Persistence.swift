// Persistence.swift
import Foundation

final class Persistence {
    static let shared = Persistence()
    private let k = "SyncMaven.WatchedFolders"

    func saveWatchedFolders(_ arr: [WatchedFolder]) {
        if let d = try? JSONEncoder().encode(arr) {
            UserDefaults.standard.set(d, forKey: k)
        }
    }

    // Persistence.swift
    func loadWatchedFolders() -> [WatchedFolder] {
        
        guard
            let d = UserDefaults.standard.data(forKey: k),
            var arr = try? JSONDecoder().decode([WatchedFolder].self, from: d)
        else {
            return []
        }

        // Fix invalid account IDs
        let validIDs = Set(AccountManager.shared.accounts.map { $0.id })
        if validIDs.isEmpty {
            NSLog("⚠️ No valid account IDs. Skipping auto-fix.")
            return arr
        }
        var modified = false
        for i in arr.indices {
            let id = arr[i].accountID

            if id == nil || !validIDs.contains(id!) {
                NSLog("⚠️ Fixing invalid folder accountID \(id.debugDescription) -> \(validIDs.first!)")
                if validIDs.isEmpty {
                    NSLog("⚠️ No accounts available — leaving folder.accountID nil")
                    arr[i].accountID = nil
                } else {
                    arr[i].accountID = validIDs.first!
                }
                modified = true
            }
        }

        if modified {
            saveWatchedFolders(arr)
        }

        return arr
    }
}

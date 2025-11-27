// Persistence.swift
import Foundation

final class Persistence {
    static let shared = Persistence()
    private let k = "Sinclo.WatchedFolders"

    func saveWatchedFolders(_ arr: [WatchedFolder]) {
        if let d = try? JSONEncoder().encode(arr) {
            UserDefaults.standard.set(d, forKey: k)
        }
    }

    func loadWatchedFolders() -> [WatchedFolder] {
        // load stored folders (if any)
        let folders: [WatchedFolder]
        if let d = UserDefaults.standard.data(forKey: k),
           let decoded = try? JSONDecoder().decode([WatchedFolder].self, from: d) {
            folders = decoded
        } else {
            return []
        }

        // ------------------------------------------------
        // 🔥 AUTO-FIX INVALID accountIDs HERE
        // ------------------------------------------------
        let validIDs = Set(AccountManager.shared.accounts.map { $0.id })

        // if there are no valid accounts at all, we won't rewrite every folder to a garbage id,
        // but we'll normalize nil accountIDs to empty string so UI can treat them consistently.
        var modified = false
        var fixed = folders

        for i in fixed.indices {
            // treat nil as empty string for comparison
            let current = fixed[i].accountID ?? ""
            if !validIDs.contains(current) {
                // if there are valid accounts, pick the first as a fallback; otherwise set to empty
                let fallback = AccountManager.shared.accounts.first?.id ?? ""
                print("⚠️ Fixing invalid accountID for folder:", fixed[i].localPath, "->", fallback.isEmpty ? "(none)" : fallback)
                fixed[i].accountID = fallback
                modified = true
            }
        }

        if modified {
            saveWatchedFolders(fixed)
        }

        return fixed
    }
}

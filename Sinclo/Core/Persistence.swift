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
        if let d = UserDefaults.standard.data(forKey: k),
           let arr = try? JSONDecoder().decode([WatchedFolder].self, from: d) {
            return arr
        }
        return []
    }
}

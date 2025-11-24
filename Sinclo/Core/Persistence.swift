import Foundation

// For MVP we use UserDefaults + JSON. For scale, switch to SQLite/CoreData.

final class Persistence {
    static func saveWatchedFolders(_ folders: [WatchedFolder]) {
        if let d = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(d, forKey: "watchedFolders")
        }
    }

    static func loadWatchedFolders() -> [WatchedFolder] {
        if let d = UserDefaults.standard.data(forKey: "watchedFolders"), let arr = try? JSONDecoder().decode([WatchedFolder].self, from: d) {
            return arr
        }
        return []
    }
}

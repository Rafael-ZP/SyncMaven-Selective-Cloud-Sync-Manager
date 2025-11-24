import Foundation

final class SecurityBookmark {
    static func createBookmark(for url: URL) -> Data? {
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            return bookmark
        } catch {
            print("Bookmark creation failed: \(error)")
            return nil
        }
    }

    static func restoreURL(from bookmark: Data) -> URL? {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            return url
        } catch {
            print("Bookmark restore failed: \(error)")
            return nil
        }
    }

    static func startAccessing(url: URL) -> Bool {
        return url.startAccessingSecurityScopedResource()
    }

    static func stopAccessing(url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

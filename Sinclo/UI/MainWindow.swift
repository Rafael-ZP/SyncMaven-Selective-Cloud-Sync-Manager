internal import SwiftUI

struct MainWindow: View {
    @StateObject var app = AppState.shared

    var body: some View {
        MainWindowTabsView()
            .frame(minWidth: 650, minHeight: 420)   // ← minimum usable size
            .toolbar {
                ToolbarItemGroup(placement: .principal) {
                    Button(action: { app.toggleMonitoring() }) {
                        Image(systemName: app.isMonitoring ? "stop.fill" : "play.fill")
                    }

                    Button(action: { app.pickLocalFolder() }) {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
    }
}

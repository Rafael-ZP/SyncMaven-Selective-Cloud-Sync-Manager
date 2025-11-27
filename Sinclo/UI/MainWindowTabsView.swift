internal import SwiftUI

struct MainWindowTabsView: View {

    enum Tab { case folders, accounts, logs }

    @State private var selectedTab: Tab = .folders

    static var shared: MainWindowTabsView?

    init() {
        MainWindowTabsView.shared = self
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            WatchedFoldersTab()
                .tag(Tab.folders)
                .tabItem { Label("Watched Folders", systemImage: "folder.badge.plus") }

            AccountsTab()
                .tag(Tab.accounts)
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }

            LogsTab()
                .tag(Tab.logs)
                .tabItem { Label("Activity Log", systemImage: "text.alignleft") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // ← expands but NOT forced
        .padding(12)                                        // small padding only
    }

    func activateTab(_ tab: Tab) {
        selectedTab = tab
    }
}

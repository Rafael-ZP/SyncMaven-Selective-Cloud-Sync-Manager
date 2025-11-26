//
//  MainWindowTabsView.swift
//  Sinclo
//
//  Created by Rafael Zieganpalg on 26/11/25.
//

//
//  MainWindowTabsView.swift
//  Sinclo
//

import SwiftUI
import Combine

enum SincloTab: Hashable {
    case folders
    case accounts
    case logs
}

struct MainWindowTabsView: View {

    // Allow external tab switching
    static weak var shared: MainWindowTabsViewCoordinator?

    @StateObject private var coordinator = MainWindowTabsViewCoordinator()

    init() {
        MainWindowTabsView.shared = coordinator
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
    }

    // ----------------------------------------------------------
    // MARK: Sidebar Tabs
    // ----------------------------------------------------------
    private var sidebar: some View {
        VStack(spacing: 0) {
            tabButton(.folders, title: "Watched Folders", icon: "folder")
            tabButton(.accounts, title: "Accounts", icon: "person.crop.circle")
            tabButton(.logs, title: "Logs", icon: "text.book.closed")

            Spacer()
        }
        .frame(width: 160)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func tabButton(_ tab: SincloTab, title: String, icon: String) -> some View {
        Button(action: { coordinator.activeTab = tab }) {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
            }
            .padding(12)
            .background(coordinator.activeTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    // ----------------------------------------------------------
    // MARK: Content area
    // ----------------------------------------------------------
    private var content: some View {
        VStack(spacing: 0) {
            switch coordinator.activeTab {
            case .folders:
                WatchedFoldersTab()
            case .accounts:
                AccountsTab()
            case .logs:
                LogsTab()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }
}

final class MainWindowTabsViewCoordinator: ObservableObject {
    @Published var activeTab: SincloTab = .folders

    func activateTab(_ tab: SincloTab) {
        self.activeTab = tab
    }
}

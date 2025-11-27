//
//  AppWindowView.swift
//  Sinclo
//
//  Created by Rafael Zieganpalg on 26/11/25.
//


internal import SwiftUI

struct AppWindowView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var accounts = AccountManager.shared
    @StateObject private var sync = SyncManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // header
            HStack {
                Image("MenubarIcon")
                    .resizable()
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)
                Text("Sinclo")
                    .font(.title2)
                    .bold()
                Spacer()
                Toggle(isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "Sinclo.ShowInDock") },
                    set: { UserDefaults.standard.set($0, forKey: "Sinclo.ShowInDock"); NSApp.setActivationPolicy($0 ? .regular : .accessory) }
                )) {
                    Text("Show in Dock")
                }
                .toggleStyle(SwitchToggleStyle())
                .frame(width: 150)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14).padding(.bottom, 14)

            Divider()

            TabView {
                WatchedFoldersTab()
                    .tabItem { Label("Watched Folders", systemImage: "folder.fill.badge.plus") }

                AccountsTab()
                    .tabItem { Label("Accounts", systemImage: "person.crop.circle.badge.plus") }

                LogsTab()
                    .tabItem { Label("Logs", systemImage: "doc.plaintext") }
            }
            .padding()
        }
        .frame(minWidth: 680, minHeight: 480)
    }
}

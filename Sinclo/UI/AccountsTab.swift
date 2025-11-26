//
//  AccountsTab.swift
//

import SwiftUI

struct AccountsTab: View {
    @ObservedObject private var manager = AccountManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack {
                Text("Accounts")
                    .font(.title2)
                    .bold()

                Spacer()

                Button {
                    manager.addAccount { _ in }
                } label: {
                    Label("Add Account", systemImage: "plus.circle")
                }
            }

            Divider()

            List {
                ForEach(manager.accounts) { acc in
                    HStack {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 30))
                        VStack(alignment: .leading) {
                            Text(acc.email)
                            Text("ID: \(acc.id)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Remove") {
                            manager.remove(account: acc)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Spacer()
        }
    }
}

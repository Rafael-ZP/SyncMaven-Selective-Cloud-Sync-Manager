import SwiftUI

struct AccountsTab: View {
    @StateObject private var mgr = AccountManager.shared
    @EnvironmentObject var app: AppState
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Accounts").font(.headline)
                Spacer()
                Button(action: { adding = true }) {
                    Label("Add Account", systemImage: "person.crop.circle.badge.plus")
                }
            }

            List {
                ForEach(mgr.accounts, id: \.id) { acc in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(acc.email).font(.subheadline)
                            Text(acc.id).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Remove") {
                            mgr.remove(account: acc)
                        }
                    }
                }
            }
            .frame(minHeight: 300)

            HStack {
                Spacer()
                Button("Refresh Accounts") { mgr.reload() }
            }
        }
        .sheet(isPresented: $adding) {
            AddAccountView(isPresented: $adding)
        }
    }
}

struct AddAccountView: View {
    @Binding var isPresented: Bool
    @StateObject private var mgr = AccountManager.shared
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Google Account").font(.title2).bold()
            Text("This will open your browser to sign in and grant Sinclo Drive access.")
                .font(.subheadline)
            if working { ProgressView("Waiting for authorization…").padding(.top, 10) }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Sign in") {
                    working = true
                    mgr.addAccount { res in
                        DispatchQueue.main.async {
                            working = false
                            isPresented = false
                        }
                    }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 180)
    }
}
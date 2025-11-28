// AccountsTab.swift
// SyncMaven
// Fixed: Removed GeometryReader to prevent AttributeGraph cycles.

internal import SwiftUI
import LocalAuthentication

struct AccountsTab: View {
    @StateObject var accountManager = AccountManager.shared
    
    // State for Deletion Alert
    @State private var accountToDelete: SyncMavenAccount?
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            
            // --- Header ---
            HStack {
                Text("Cloud Accounts")
                    .font(.title2)
                    .bold()
                Spacer()
                
                // Add Account Button
                Button(action: {
                    authenticateUser(reason: "Authenticate to add a new account") { success in
                        if success {
                            OAuth2PKCE.shared.startAuthorization { result in
                                switch result {
                                case .success(let tokens):
                                    withAnimation {
                                        AccountManager.shared.addAccount(
                                            usingAccessToken: tokens.accessToken,
                                            refreshToken: tokens.refreshToken
                                        )
                                    }
                                case .failure(let error):
                                    AppState.shared.log("Authentication failed: \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                }) {
                    Label("Add Google Account", systemImage: "plus.circle")
                }
            }
            .padding(.bottom, 10)
            
            // --- List ---
            // Replaced fixed height calculation with flexible frame
            List {
                ForEach(accountManager.accounts) { account in
                    HStack {
                        if let data = account.avatarData, let image = NSImage(data: data) {
                            Image(nsImage: image)
                                .resizable()
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .foregroundColor(.gray)
                        }
                        
                        VStack(alignment: .leading) {
                            Text(account.name ?? "Unknown Name")
                                .fontWeight(.medium)
                            Text(account.email)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            self.accountToDelete = account
                            self.showDeleteConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.vertical, 8)
                }
            }
            .listStyle(InsetListStyle())
            .frame(maxHeight: .infinity) // Allow list to fill remaining space naturally
        }
        .padding()
        // Alert Logic
        .alert("Remove Account?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                accountToDelete = nil
            }
            Button("Remove", role: .destructive) {
                if let account = accountToDelete {
                    authenticateUser(reason: "Authenticate to remove this account") { success in
                        if success {
                            withAnimation {
                                accountManager.remove(account: account)
                            }
                        }
                    }
                }
            }
        } message: {
            Text("Are you sure you want to remove \(accountToDelete?.email ?? "this account") from SyncMaven? This cannot be undone.")
        }
    }
    
    // Authentication Helper
    func authenticateUser(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                DispatchQueue.main.async {
                    if success {
                        completion(true)
                    } else {
                        AppState.shared.log("Authentication failed or cancelled.")
                        completion(false)
                    }
                }
            }
        } else {
            // If no biometrics set up, allow proceed
            completion(true)
        }
    }
}

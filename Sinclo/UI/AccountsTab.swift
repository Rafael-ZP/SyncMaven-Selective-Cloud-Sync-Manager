internal import SwiftUI

struct AccountsTab: View {
    @StateObject var accountManager = AccountManager.shared
    
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Cloud Accounts")
                        .font(.title2)
                        .bold()
                    Spacer()
                    Button(action: {
                        OAuth2PKCE.shared.startAuthorization { result in
                            switch result {
                            case .success(let tokens):
                                AccountManager.shared.addAccount(
                                    usingAccessToken: tokens.accessToken,
                                    refreshToken: tokens.refreshToken
                                )
                            case .failure(let error):
                                AppState.shared.log("Authentication failed: \(error.localizedDescription)")
                            }
                        }
                    }) {
                        Label("Add Google Account", systemImage: "plus.circle")
                    }
                }
                .padding(.bottom, 10)
                
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
                                accountManager.remove(account: account)
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
                .frame(height: geometry.size.height * 0.8)
            }
            .padding()
        }
    }
}

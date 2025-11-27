internal import SwiftUI

struct LogsTab: View {
    @StateObject var app = AppState.shared

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 14) {
                Text("Activity Log")
                    .font(.title2)
                    .bold()
                    .padding(.bottom, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(app.logs, id: \.self) { log in
                            Text(log)
                                .font(.system(.body, design: .monospaced))
                                .padding(.vertical, 2)
                        }
                    }
                }
                .frame(height: geometry.size.height * 0.8)
            }
            .padding()
        }
    }
}

//
//  LogsTab.swift
//

import SwiftUI

struct LogsTab: View {
    @ObservedObject private var app = AppState.shared
    @State private var scrollID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Text("Logs")
                    .font(.title2)
                    .bold()

                Spacer()

                Button("Clear Logs") {
                    app.logs.removeAll()
                }
            }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(app.logs, id: \.self) { log in
                            Text(log)
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                    .onChange(of: app.logs.count) { _ in
                        if let last = app.logs.last {
                            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }
            }

            Spacer()
        }
    }
}

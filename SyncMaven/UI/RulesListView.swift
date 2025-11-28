internal import SwiftUI

struct RulesListView: View {
    @Binding var rules: [Rule]
    var onSave: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sync Rules")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Done") {
                    // Safety Check: Ensure at least one rule exists
                    if rules.isEmpty { rules.append(Rule()) }
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // List
            List {
                ForEach($rules.indices, id: \.self) { index in
                    RuleEditorView(
                        rule: $rules[index],
                        canRemove: rules.count > 1, // Compulsory 1 rule
                        onRemove: {
                            rules.remove(at: index)
                        }
                    )
                    .padding(.vertical, 8)
                }
            }
            .frame(minWidth: 500, minHeight: 400)
            
            Divider()
            
            // Footer
            HStack {
                Button(action: {
                    withAnimation { rules.append(Rule()) }
                }) {
                    Label("Add Another Rule", systemImage: "plus")
                }
                Spacer()
                Text("\(rules.count) Active Rules")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

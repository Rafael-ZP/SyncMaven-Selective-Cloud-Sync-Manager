internal import SwiftUI

struct RulesListView: View {
    @Binding var rules: [Rule]
    var onSave: () -> Void
    
    var body: some View {
        VStack {
            Text("Edit Rules")
                .font(.title)
                .padding()
            
            List {
                ForEach($rules) { $rule in
                    RuleEditorView(rule: $rule)
                }
                .onDelete { indices in
                    rules.remove(atOffsets: indices)
                }
            }
            
            HStack {
                Button("Add Rule") {
                    rules.append(Rule())
                }
                Spacer()
                Button("Done") {
                    onSave()
                }
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

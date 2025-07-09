import SwiftUI

struct VocabookSettingView: View {
    @AppStorage("wordCountPerPage") private var wordCountPerPage = 10.0
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Vocabulary Notebook Settings")) {
                    VStack {
                        Text("Word Count Per Page: \(Int(wordCountPerPage))")
                        Slider(
                            value: $wordCountPerPage,
                            in: 5...25,
                            step: 1
                        )
                    }
                }
            }
            .navigationTitle("Notebook Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct VocabookSettingView_Previews: PreviewProvider {
    static var previews: some View {
        VocabookSettingView()
    }
}

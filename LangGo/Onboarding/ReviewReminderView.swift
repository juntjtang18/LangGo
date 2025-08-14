import SwiftUI

struct ReviewReminderView: View {
    var onContinue: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Want to remember 10× more — with less effort?")
                .font(.largeTitle)
                .bold()

            Text("Without review, most people forget 90% of new words in 2 days. Our smart Vocabulary Notebook reminds you only when you’re about to forget — not too soon, not too late.")

            Button(action: { onContinue(true) }) {
                Text("Yes, help me remember better")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            Button(action: { onContinue(false) }) {
                Text("Not now — I’ll review manually")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}

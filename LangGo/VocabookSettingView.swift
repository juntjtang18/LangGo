import SwiftUI
import os

struct VocabookSettingView: View {
    @AppStorage("wordCountPerPage") private var wordCountPerPage = 10.0
    @AppStorage("interval1") private var interval1 = 1.5
    @AppStorage("interval2") private var interval2 = 2.0
    @AppStorage("interval3") private var interval3 = 2.0

    // Track initial server-loaded values to detect changes
    @State private var initialWordCountPerPage: Double? = nil
    @State private var initialInterval1: Double? = nil
    @State private var initialInterval2: Double? = nil
    @State private var initialInterval3: Double? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appEnvironment: AppEnvironment
    private let logger = Logger(subsystem: "com.langGo.swift", category: "VocabookSettingView")

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Vocabulary Notebook Settings")) {
                    VStack(spacing: 16) {
                        settingSlider(
                            title: "Word Count Per Page",
                            value: $wordCountPerPage,
                            range: 5.0...25.0,
                            step: 1.0,
                            format: { "\(Int($0))" }
                        )
                        settingSlider(
                            title: "Interval 1",
                            value: $interval1,
                            range: 0.5...5.0,
                            step: 0.1,
                            format: { String(format: "%.1f", $0) }
                        )
                        settingSlider(
                            title: "Interval 2",
                            value: $interval2,
                            range: 0.5...5.0,
                            step: 0.1,
                            format: { String(format: "%.1f", $0) }
                        )
                        settingSlider(
                            title: "Interval 3",
                            value: $interval3,
                            range: 0.5...5.0,
                            step: 0.1,
                            format: { String(format: "%.1f", $0) }
                        )
                    }
                }
            }
            .navigationTitle("Notebook Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task {
                            // Only save if something changed
                            if initialWordCountPerPage == wordCountPerPage &&
                               initialInterval1 == interval1 &&
                               initialInterval2 == interval2 &&
                               initialInterval3 == interval3 {
                                dismiss()
                                return
                            }
                            do {
                                let updated = try await appEnvironment.strapiService.updateVBSetting(
                                    wordsPerPage: Int(wordCountPerPage),
                                    interval1: interval1,
                                    interval2: interval2,
                                    interval3: interval3
                                )
                                // Update local AppStorage to reflect saved values
                                wordCountPerPage = Double(updated.attributes.wordsPerPage)
                                interval1 = updated.attributes.interval1
                                interval2 = updated.attributes.interval2
                                interval3 = updated.attributes.interval3
                                // Reset initial markers
                                initialWordCountPerPage = wordCountPerPage
                                initialInterval1 = interval1
                                initialInterval2 = interval2
                                initialInterval3 = interval3
                                logger.info("Saved VBSetting: wordsPerPage=\(Int(wordCountPerPage)), intervals=[\(interval1), \(interval2), \(interval3)]")
                            } catch {
                                logger.error("Failed to save VBSetting: \(error.localizedDescription, privacy: .public)")
                            }
                            dismiss()
                        }
                    }
                }
            }
            .task {
                do {
                    let vbSetting = try await appEnvironment.strapiService.fetchVBSetting()
                    // Load into UI and initial trackers
                    wordCountPerPage = Double(vbSetting.attributes.wordsPerPage)
                    interval1 = vbSetting.attributes.interval1
                    interval2 = vbSetting.attributes.interval2
                    interval3 = vbSetting.attributes.interval3
                    initialWordCountPerPage = wordCountPerPage
                    initialInterval1 = interval1
                    initialInterval2 = interval2
                    initialInterval3 = interval3
                    logger.info("Loaded VBSetting: wordsPerPage=\(vbSetting.attributes.wordsPerPage), intervals=[\(vbSetting.attributes.interval1), \(vbSetting.attributes.interval2), \(vbSetting.attributes.interval3)]")
                } catch {
                    logger.error("Failed to load VBSetting: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // Helper for Double sliders
    private func settingSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(format(value.wrappedValue))")
            Slider(value: value, in: range, step: step)
        }
    }
}

struct VocabookSettingView_Previews: PreviewProvider {
    static var previews: some View {
        VocabookSettingView()
    }
}

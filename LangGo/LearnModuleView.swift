import Foundation
import SwiftUI
import SwiftData

// The old LearnView and its components are no longer directly used in the tab
// but are kept to prevent breaking other parts of the app.
// They can be safely removed in a future refactor.

// MARK: - Primary Learn Screen UI
struct LearnView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: VocabookViewModel
    
    let mainUnits: [CourseUnit] = [
        .init(number: 1, title: "Introductions", progress: 1.0, isSelected: true),
        .init(number: 2, title: "Connections", progress: 0.6),
        .init(number: 3, title: "Community", progress: 0.0),
        .init(number: 4, title: "Lifestyle", progress: 0.0),
        .init(number: 5, title: "Ambitions", progress: 0.0)
    ]
    
    let specialtyUnits: [CourseUnit] = [
        .init(icon: "wineglass.fill", title: "Wine and Cheese", progress: 0.0),
        .init(icon: "heart.fill", title: "Romance", progress: 0.0),
        .init(icon: "text.quote", title: "Argot", progress: 0.0)
    ]

    init(modelContext: ModelContext, strapiService: StrapiService) {
        _viewModel = State(initialValue: VocabookViewModel(modelContext: modelContext, strapiService: strapiService))
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                ResumeLearningView()
                VocabularyNotebookView(viewModel: viewModel)
                
                UnitListView(title: "Main Units", units: mainUnits)
                
                UnitListView(title: "Specialty Units", units: specialtyUnits)
                
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .task {
            await viewModel.loadVocabookPages()
        }
    }
}

// MARK: - LearnView Components
struct CourseUnit: Identifiable {
    let id = UUID()
    var number: Int? = nil
    var icon: String? = nil
    var title: String
    var progress: Double
    var isSelected: Bool = false
}

struct ResumeLearningView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: { /* Action for resuming lesson */ }) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Resume Learning")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.black)
                .cornerRadius(12)
            }
            
            Text("Unit 1 Introductions")
                .font(.headline)
                .fontWeight(.bold)
            
            Text("Lesson 3 Good Morning")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
    }
}

struct UnitListView: View {
    var title: String
    var units: [CourseUnit]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            VStack(spacing: 8) {
                ForEach(units) { unit in
                    UnitRowView(unit: unit)
                }
            }
            .padding()
            .background(Color.white)
            .cornerRadius(16)
        }
    }
}

struct UnitRowView: View {
    var unit: CourseUnit
    
    var body: some View {
        HStack(spacing: 15) {
            if let number = unit.number {
                Text("\(number)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.purple)
            } else if let icon = unit.icon {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundColor(.purple)
            }
            
            Text(unit.title)
                .font(.headline)
            
            Spacer()
            
            ProgressCircleView(progress: unit.progress)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(unit.isSelected ? .purple : .clear, lineWidth: 2)
        )
    }
}

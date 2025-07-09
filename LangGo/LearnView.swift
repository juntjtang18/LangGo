// LangGo/LearnView.swift
//
//  LearnView.swift
//  LangGo
//
//  Created by James Tang on 2025/6/25.
//

import SwiftUI
import SwiftData

// MARK: - Learn Tab Container
// This is the top-level view for the "Learn" tab.
// It's placed in the TabView in MainView.swift.

struct LearnTabView: View {
    @Binding var isSideMenuShowing: Bool
    @EnvironmentObject var languageSettings: LanguageSettings
    @Environment(\.modelContext) private var modelContext // Inject modelContext

    var body: some View {
        NavigationStack {
            // Pass the modelContext to LearnView
            LearnView(modelContext: modelContext)
                .navigationTitle("Learn English")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { MenuToolbar(isSideMenuShowing: $isSideMenuShowing) }
        }
    }
}

// MARK: - Primary Learn Screen UI

struct LearnView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: LearnViewModel // Use the new ViewModel
    
    // Sample data to populate the view, matching your design
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

    init(modelContext: ModelContext) {
        _viewModel = State(initialValue: LearnViewModel(modelContext: modelContext))
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                ResumeLearningView()
                VocabularyNotebookView(viewModel: viewModel) // Pass viewModel directly
                
                // --- Main Units List ---
                UnitListView(title: "Main Units", units: mainUnits)
                
                // --- Specialty Units List ---
                UnitListView(title: "Specialty Units", units: specialtyUnits)
                
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground)) // A subtle grey background
        .task {
            await viewModel.loadVocabookPages()
        }
    }
    // MARK: - NEW: Test Function for Vocapage Details
    private func testFetchVocapageDetails(vocapageId: Int) async {
        do {
            print("Attempting to fetch details for vocapage ID: \(vocapageId)")
            print("----------------------------------\n")
            
        } catch {
            print("Failed to fetch vocapage details: \(error.localizedDescription)")
        }
    }}

// MARK: - LearnView Components

// Data Model for a Unit
struct CourseUnit: Identifiable {
    let id = UUID()
    var number: Int? = nil
    var icon: String? = nil
    var title: String
    var progress: Double
    var isSelected: Bool = false
}

// The Top "Resume Learning" Panel
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

// A Reusable View for a List of Units
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


// A View for a Single Row in the Unit List
struct UnitRowView: View {
    var unit: CourseUnit
    
    var body: some View {
        HStack(spacing: 15) {
            // Icon or Number
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

// The Circular Progress Indicator
struct ProgressCircleView: View {
    var progress: Double
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 5.0)
                .opacity(0.3)
                .foregroundColor(Color.gray)
            
            Circle()
                .trim(from: 0.0, to: min(progress, 1.0))
                .stroke(style: StrokeStyle(lineWidth: 5.0, lineCap: .round, lineJoin: .round))
                .foregroundColor(progress > 0 ? .green : .clear)
                .rotationEffect(Angle(degrees: 270.0))
                .animation(.linear, value: progress)
        }
        .frame(width: 30, height: 30)
    }
}

// MARK: - NEW: Vocabulary Notebook Subview
struct VocabularyNotebookView: View {
    @Bindable var viewModel: LearnViewModel // Changed from @ObservedObject
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Vocabulary Notebook")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                if viewModel.isLoadingVocabooks {
                    ProgressView()
                }
            }
            .padding(.horizontal)
            
            VStack(spacing: 8) {
                if let vocabook = viewModel.vocabook, !viewModel.isLoadingVocabooks {
                    VocabookSectionView(vocabook: vocabook, viewModel: viewModel)
                } else if !viewModel.isLoadingVocabooks {
                    Text("No vocabooks found.")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .padding()
            .background(Color.white)
            .cornerRadius(16)
        }
    }
}

struct VocabookSectionView: View {
    let vocabook: Vocabook
    @Bindable var viewModel: LearnViewModel // Changed from @ObservedObject

    var body: some View {
        VStack(alignment: .leading) {
            Button(action: {
                withAnimation {
                    viewModel.toggleVocabookExpansion(vocabookId: vocabook.id)
                }
            }) {
                HStack {
                    Text(vocabook.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: viewModel.expandedVocabooks.contains(vocabook.id) ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)

            if viewModel.expandedVocabooks.contains(vocabook.id) {
                if let vocapages = vocabook.vocapages, !vocapages.isEmpty {
                    let sortedPages = vocapages.sorted(by: { $0.order < $1.order })
                    ForEach(sortedPages) { vocapage in
                        VocapageRowView(
                            vocapage: vocapage,
                            allVocapageIds: sortedPages.map { $0.id }
                        )
                    }
                } else {
                    Text("No pages in this vocabook.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.leading)
                }
            }
        }
        .padding(.horizontal)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

struct VocapageRowView: View {
    @Environment(\.modelContext) private var modelContext // Get model context
    let vocapage: Vocapage
    let allVocapageIds: [Int] // Pass the list of all page IDs

    var body: some View {
        NavigationLink(destination: VocapageHostView(
            allVocapageIds: allVocapageIds,
            selectedVocapageId: vocapage.id,
            modelContext: modelContext // Pass the context to the host view
        )) {
            HStack(spacing: 15) {
                Text("Page \(vocapage.order)") // Display order
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.blue) // Different color for pages
                
                Text(vocapage.title)
                    .font(.headline)
                
                Spacer()
                
                ProgressCircleView(progress: vocapage.progress)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.clear) // No fill for rows
            )
        }
        .buttonStyle(PlainButtonStyle()) // To remove default button styling
    }
}

#Preview {
    // This makes it easy to preview your LearnView in isolation
    LearnTabView(isSideMenuShowing: .constant(false))
}

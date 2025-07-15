// LangGo/HomeTabView.swift
import SwiftUI
import SwiftData

// MARK: - Home Tab Container
struct HomeTabView: View {
    @Binding var isSideMenuShowing: Bool
    @Binding var selectedTab: Int // Accepts binding to control the tab
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appEnvironment: AppEnvironment

    // View models needed for the destination view are initialized here
    @State private var flashcardViewModel: FlashcardViewModel?
    @State private var vocabookViewModel: VocabookViewModel?

    var body: some View {
        NavigationStack {
            if let flashcardViewModel = flashcardViewModel, let vocabookViewModel = vocabookViewModel {
                // Pass the view models and the tab selection binding to the HomeView
                HomeView(
                    flashcardViewModel: flashcardViewModel,
                    vocabookViewModel: vocabookViewModel,
                    selectedTab: $selectedTab
                )
            } else {
                ProgressView()
                    .onAppear {
                        // Initialize view models on appear
                        if flashcardViewModel == nil {
                            flashcardViewModel = FlashcardViewModel(modelContext: modelContext, strapiService: appEnvironment.strapiService)
                        }
                        if vocabookViewModel == nil {
                            vocabookViewModel = VocabookViewModel(modelContext: modelContext, strapiService: appEnvironment.strapiService)
                        }
                    }
            }
        }
        .navigationTitle("Home") // Title is set on the container
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { MenuToolbar(isSideMenuShowing: $isSideMenuShowing) }
    }
}



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

// MARK: - Vocabulary Notebook Subview
struct VocabularyNotebookView: View {
    @Bindable var viewModel: VocabookViewModel

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
    @Bindable var viewModel: VocabookViewModel

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
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appEnvironment: AppEnvironment
    let vocapage: Vocapage
    let allVocapageIds: [Int]

    var body: some View {
        NavigationLink(destination: VocapageHostView(
            allVocapageIds: allVocapageIds,
            selectedVocapageId: vocapage.id,
            modelContext: modelContext,
            strapiService: appEnvironment.strapiService
        )) {
            HStack(spacing: 15) {
                Text("Page \(vocapage.order)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                
                Text(vocapage.title)
                    .font(.headline)
                
                Spacer()
                
                ProgressCircleView(progress: vocapage.progress)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

//
//  Vocapage.swift
//  LangGo
//
//  Created by James Tang on 2025/7/30.
//

import Foundation
import CoreData

// A struct for weighted progress, which is calculated in the view.
struct WeightedProgress {
    let progress: Double
    let isComplete: Bool
}

// Vocapage is also an NSManagedObject subclass
public class Vocapage: NSManagedObject, Identifiable {
    // No custom implementation needed here
}

extension Vocapage {
    @NSManaged public var id: Int64
    @NSManaged public var title: String?
    @NSManaged public var order: Int32
    @NSManaged public var flashcards: NSSet? // Use NSSet for to-many relationships
    @NSManaged public var vocabook: Vocabook?

    // The progress calculation can remain, but the weighted one is now done in the view.
    var progress: Double {
        guard let cards = flashcards?.allObjects as? [Flashcard], !cards.isEmpty else { return 0.0 }
        let rememberedCount = cards.filter { $0.isRemembered || $0.correctStreak >= 11 }.count
        return Double(rememberedCount) / Double(cards.count)
    }

    var weightedProgress: WeightedProgress {
        return WeightedProgress(progress: 0.0, isComplete: false)
    }
}

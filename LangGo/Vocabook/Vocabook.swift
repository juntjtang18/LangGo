//
//  Vocabook.swift
//  LangGo
//
//  Created by James Tang on 2025/7/30.
//


import Foundation
import CoreData

// Vocabook is now an NSManagedObject subclass
public class Vocabook: NSManagedObject, Identifiable {
    // No custom implementation needed here
}

extension Vocabook {
    // Use @NSManaged for all properties stored by Core Data
    @NSManaged public var id: Int64
    @NSManaged public var title: String?
    @NSManaged public var vocapages: NSSet? // Use NSSet for to-many relationships
}
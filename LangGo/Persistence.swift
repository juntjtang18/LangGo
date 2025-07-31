//
//  Persistence.swift
//  LangGo
//
//  Created by James Tang on 2025/6/24.
//

import CoreData

struct PersistenceController {
    // A singleton for our entire app to use
    static let shared = PersistenceController()

    // A persistence controller for previews, using an in-memory store
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        // You can add sample data here for your previews if needed
        // For example:
        // for _ in 0..<10 {
        //     let newItem = Item(context: viewContext)
        //     newItem.timestamp = Date()
        // }
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    // The NSPersistentContainer that holds the Core Data stack
    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        // The name "LangGo" must match the name of your .xcdatamodeld file
        container = NSPersistentContainer(name: "LangGo")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // This is a serious error and should be handled in a production app
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}

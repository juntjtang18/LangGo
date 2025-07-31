import Foundation
import CoreData

// This is the most critical fix. It explicitly tells Core Data's runtime
// that this Swift class corresponds to the "Flashcard" entity in your model.
@objc(Flashcard)
public class Flashcard: NSManagedObject, Identifiable {
    // The class body is empty because all properties are correctly defined in the extension.
}

extension Flashcard {

    // This is a standard helper function that makes fetching objects much cleaner and safer.
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Flashcard> {
        return NSFetchRequest<Flashcard>(entityName: "Flashcard")
    }
    
    // Your properties from the refactor are all correct.
    @NSManaged public var id: Int
    @NSManaged public var frontContent: String
    @NSManaged public var backContent: String
    @NSManaged public var register: String?
    @NSManaged public var rawComponentData: Data?
    @NSManaged public var contentType: String
    @NSManaged public var lastReviewedAt: Date?
    @NSManaged public var correctStreak: Int
    @NSManaged public var wrongStreak: Int
    @NSManaged public var isRemembered: Bool
    @NSManaged public var reviewTire: String?

    // Your computed properties are also preserved exactly as you had them.
    private var decodedComponent: StrapiComponent? {
        guard let data = rawComponentData else { return nil }
        return try? JSONDecoder().decode(StrapiComponent.self, from: data)
    }
    
    var wordAttributes: WordAttributes? {
        guard contentType == "a.word-ref" else { return nil }
        return decodedComponent?.word?.data?.attributes
    }
    
    var sentenceAttributes: SentenceAttributes? {
        guard contentType == "a.sent-ref" else { return nil }
        return decodedComponent?.sentence?.data?.attributes
    }
    
    var userWordAttributes: UserWordAttributes? {
        guard contentType == "a.user-word-ref" else { return nil }
        return decodedComponent?.userWord?.data?.attributes
    }
    
    var userSentenceAttributes: UserSentenceAttributes? {
        guard contentType == "a.user-sent-ref" else { return nil }
        return decodedComponent?.userSentence?.data?.attributes
    }
}

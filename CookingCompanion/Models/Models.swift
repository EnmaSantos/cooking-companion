import Foundation
import SwiftData

@Model final class Recipe {
    @Attribute(.unique) var id: UUID
    var name: String
    var source: String
    var sourceID: String?
    var sourceURL: String?
    var imageURL: String?
    var imageData: Data?
    var originalInstructions: String
    var servings: Int?
    var isFavorite: Bool
    var createdAt: Date
    init(name: String, source: String = "custom", sourceID: String? = nil, sourceURL: String? = nil,
         imageURL: String? = nil, originalInstructions: String = "", servings: Int? = nil) {
        self.id = UUID(); self.name = name; self.source = source; self.sourceID = sourceID
        self.sourceURL = sourceURL; self.imageURL = imageURL; self.originalInstructions = originalInstructions
        self.servings = servings; self.isFavorite = false; self.createdAt = .now
    }
}

@Model final class RecipeIngredient {
    @Attribute(.unique) var id: UUID
    var recipeID: UUID
    var ingredientID: UUID?
    var name: String
    var amount: Double?
    var unit: String?
    var originalMeasure: String
    var position: Int
    init(recipeID: UUID, name: String, amount: Double? = nil, unit: String? = nil,
         originalMeasure: String = "", position: Int, ingredientID: UUID? = nil) {
        self.id = UUID(); self.recipeID = recipeID; self.ingredientID = ingredientID
        self.name = name; self.amount = amount; self.unit = unit
        self.originalMeasure = originalMeasure; self.position = position
    }
}

@Model final class RecipeStep {
    @Attribute(.unique) var id: UUID
    var recipeID: UUID
    var position: Int
    var text: String
    var ingredientIDsData: Data?
    init(recipeID: UUID, position: Int, text: String) {
        self.id = UUID(); self.recipeID = recipeID; self.position = position; self.text = text
        self.ingredientIDsData = Data("[]".utf8)
    }
    var ingredientIDs: [UUID] {
        get { guard let ingredientIDsData else { return [] }; return (try? JSONDecoder().decode([UUID].self, from: ingredientIDsData)) ?? [] }
        set { ingredientIDsData = (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8) }
    }
}

@Model final class Ingredient {
    @Attribute(.unique) var id: UUID
    var name: String
    var normalizedName: String
    var fdcID: Int?
    var fdcDescription: String?
    var fdcDataType: String?
    var nutrientsData: Data?
    var confirmedAliasesData: Data
    var gramsPerMilliliter: Double?
    var gramsPerCount: Double?
    init(name: String) {
        self.id = UUID(); self.name = name; self.normalizedName = IngredientMatcher.normalize(name)
        self.confirmedAliasesData = Data("[]".utf8)
    }
    var confirmedAliases: [String] {
        get { (try? JSONDecoder().decode([String].self, from: confirmedAliasesData)) ?? [] }
        set { confirmedAliasesData = (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8) }
    }
    var nutrients: [NutrientValue] {
        get { guard let nutrientsData else { return [] }; return (try? JSONDecoder().decode([NutrientValue].self, from: nutrientsData)) ?? [] }
        set { nutrientsData = try? JSONEncoder().encode(newValue) }
    }
}

struct NutrientValue: Codable, Identifiable {
    var id: Int
    var name: String
    var amount: Double
    var unit: String
    var basis: String
}

@Model final class PantryItem {
    @Attribute(.unique) var id: UUID
    var ingredientID: UUID
    var trackingMode: String // exact, estimated, available
    var quantity: Double?
    var unit: String?
    var displayUnit: String?
    var startingQuantity: Double?
    var lowFraction: Double
    var lastConfirmedAt: Date
    init(ingredientID: UUID, trackingMode: String, quantity: Double? = nil, unit: String? = nil,
         displayUnit: String? = nil, lowFraction: Double = 0.2) {
        self.id = UUID(); self.ingredientID = ingredientID; self.trackingMode = trackingMode
        self.quantity = quantity; self.unit = unit; self.displayUnit = displayUnit ?? unit
        self.startingQuantity = quantity; self.lowFraction = lowFraction; self.lastConfirmedAt = .now
    }
}

@Model final class InventoryTransaction {
    @Attribute(.unique) var id: UUID
    var pantryItemID: UUID
    var ingredientID: UUID
    var kind: String // purchase, cook, correction, discard
    var signedQuantity: Double
    var unit: String
    var note: String
    var happenedAt: Date
    var sessionID: UUID?
    var shoppingItemID: UUID?
    init(pantryItemID: UUID, ingredientID: UUID, kind: String, signedQuantity: Double,
         unit: String, note: String = "", sessionID: UUID? = nil, shoppingItemID: UUID? = nil) {
        self.id = UUID(); self.pantryItemID = pantryItemID; self.ingredientID = ingredientID
        self.kind = kind; self.signedQuantity = signedQuantity; self.unit = unit
        self.note = note; self.happenedAt = .now; self.sessionID = sessionID
        self.shoppingItemID = shoppingItemID
    }
}

struct SessionIngredient: Codable, Identifiable {
    var id: UUID
    var ingredientID: UUID?
    var name: String
    var amount: Double?
    var unit: String?
    var originalMeasure: String
}
struct SessionStep: Codable, Identifiable {
    var id: UUID
    var text: String
    var ingredientIDs: [UUID]
    init(id: UUID, text: String, ingredientIDs: [UUID] = []) {
        self.id = id; self.text = text; self.ingredientIDs = ingredientIDs
    }
    private enum CodingKeys: String, CodingKey { case id, text, ingredientIDs }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        ingredientIDs = try values.decodeIfPresent([UUID].self, forKey: .ingredientIDs) ?? []
    }
}
struct SessionSnapshot: Codable {
    var ingredients: [SessionIngredient]
    var steps: [SessionStep]
    var checkedIngredients: Set<UUID>
    var checkedSteps: Set<UUID>
    var currentStep: Int = 0
    init(ingredients: [SessionIngredient], steps: [SessionStep], checkedIngredients: Set<UUID>, checkedSteps: Set<UUID>, currentStep: Int = 0) {
        self.ingredients = ingredients; self.steps = steps
        self.checkedIngredients = checkedIngredients; self.checkedSteps = checkedSteps
        self.currentStep = currentStep
    }
    private enum CodingKeys: String, CodingKey { case ingredients, steps, checkedIngredients, checkedSteps, currentStep }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ingredients = try values.decode([SessionIngredient].self, forKey: .ingredients)
        steps = try values.decode([SessionStep].self, forKey: .steps)
        checkedIngredients = try values.decode(Set<UUID>.self, forKey: .checkedIngredients)
        checkedSteps = try values.decode(Set<UUID>.self, forKey: .checkedSteps)
        currentStep = try values.decodeIfPresent(Int.self, forKey: .currentStep) ?? 0
    }
}

@Model final class CookingSession {
    @Attribute(.unique) var id: UUID
    var recipeID: UUID
    var recipeName: String
    var snapshotData: Data
    var startedAt: Date
    var completedAt: Date?
    var status: String // active, completed, canceled
    init(recipeID: UUID, recipeName: String, snapshot: SessionSnapshot) {
        self.id = UUID(); self.recipeID = recipeID; self.recipeName = recipeName
        self.snapshotData = (try? JSONEncoder().encode(snapshot)) ?? Data()
        self.startedAt = .now; self.status = "active"
    }
    var snapshot: SessionSnapshot {
        get { (try? JSONDecoder().decode(SessionSnapshot.self, from: snapshotData)) ?? SessionSnapshot(ingredients: [], steps: [], checkedIngredients: [], checkedSteps: []) }
        set { snapshotData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

@Model final class IngredientUsage {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var ingredientID: UUID?
    var name: String
    var amount: Double?
    var unit: String?
    var transactionID: UUID?
    init(sessionID: UUID, ingredientID: UUID?, name: String, amount: Double?, unit: String?, transactionID: UUID? = nil) {
        self.id = UUID(); self.sessionID = sessionID; self.ingredientID = ingredientID
        self.name = name; self.amount = amount; self.unit = unit; self.transactionID = transactionID
    }
}

@Model final class ShoppingItem {
    @Attribute(.unique) var id: UUID
    var ingredientID: UUID?
    var name: String
    var amount: Double?
    var unit: String?
    var note: String
    var sourceKind: String // recipe, lowStock, manual
    var sourceID: UUID?
    var purchased: Bool
    var createdAt: Date
    init(name: String, ingredientID: UUID? = nil, amount: Double? = nil, unit: String? = nil,
         note: String = "", sourceKind: String, sourceID: UUID? = nil) {
        self.id = UUID(); self.ingredientID = ingredientID; self.name = name
        self.amount = amount; self.unit = unit; self.note = note
        self.sourceKind = sourceKind; self.sourceID = sourceID
        self.purchased = false; self.createdAt = .now
    }
}

@Model final class ShoppingContribution {
    @Attribute(.unique) var sourceKey: String
    var shoppingItemID: UUID
    var amount: Double?
    var unit: String?
    init(sourceKey: String, shoppingItemID: UUID, amount: Double?, unit: String?) {
        self.sourceKey = sourceKey; self.shoppingItemID = shoppingItemID
        self.amount = amount; self.unit = unit
    }
}

@Model final class AppSetting {
    @Attribute(.unique) var key: String
    var value: String
    init(key: String, value: String) { self.key = key; self.value = value }
}

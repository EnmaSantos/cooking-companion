import XCTest
import SwiftData
@testable import CookingCompanion

final class CookingCompanionTests: XCTestCase {
    func testCatalogUsesConfiguredServiceWithoutProviderKeys() throws {
        let service = TheMealDBService(baseURL: "https://catalog.example.test")
        let search = try service.url(for: "recipes/search", query: [.init(name: "q", value: "chicken alfredo")])
        let details = try service.url(for: "recipes/52772")
        XCTAssertEqual(search.path, "/recipes/search")
        XCTAssertEqual(URLComponents(url: search, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "chicken alfredo")
        XCTAssertEqual(details.path, "/recipes/52772")
        XCTAssertThrowsError(try TheMealDBService(baseURL: "not a URL").url(for: "recipes/search"))
    }

    func testQuantityParsingPreservesUncertainMeasures() {
        XCTAssertEqual(Quantity.parse("1 1/2 cups").0, 1.5)
        XCTAssertEqual(Quantity.parse("¼ cup").1, "cup")
        XCTAssertNil(Quantity.parse("to taste").0)
        XCTAssertNil(Quantity.parse("1 tin").0)
        XCTAssertNil(Quantity.parse("").0)
    }

    func testFivePoundFlourAfterCooking() throws {
        let container = try ModelContainer(for: Ingredient.self, PantryItem.self, InventoryTransaction.self,
                                           CookingSession.self, IngredientUsage.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let ingredient = Ingredient(name: "Bread flour")
        let item = PantryItem(ingredientID: ingredient.id, trackingMode: "estimated",
                              quantity: Quantity.canonical(5, "lb")!.0, unit: "g")
        let lineID = UUID()
        let session = CookingSession(recipeID: UUID(), recipeName: "Bread",
                                     snapshot: SessionSnapshot(ingredients: [.init(id: lineID, ingredientID: ingredient.id, name: "Bread flour", amount: 500, unit: "g", originalMeasure: "500 g")],
                                                               steps: [], checkedIngredients: [lineID], checkedSteps: []))
        context.insert(ingredient); context.insert(item); context.insert(session)
        try context.save()
        try KitchenStore.finish(session: session,
                                inputs: [.init(id: lineID, name: "Bread flour", ingredientID: ingredient.id, amount: 500, unit: "g")],
                                pantry: [item], ingredients: [ingredient], context: context)
        XCTAssertEqual(item.quantity!, 1767.96185, accuracy: 0.001)
        XCTAssertThrowsError(try KitchenStore.finish(session: session,
                                                      inputs: [.init(id: lineID, name: "Bread flour", ingredientID: ingredient.id, amount: 500, unit: "g")],
                                                      pantry: [item], ingredients: [ingredient], context: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<InventoryTransaction>()).count, 1)
    }

    func testVolumeCannotClaimMassReadiness() {
        let ingredient = Ingredient(name: "Flour")
        let item = PantryItem(ingredientID: ingredient.id, trackingMode: "exact", quantity: 1000, unit: "g")
        let line = RecipeIngredient(recipeID: UUID(), name: "Flour", amount: 1, unit: "cup", position: 0)
        XCTAssertEqual(Readiness.check(line: line, ingredients: [ingredient], pantry: [item]).status, .needsReview)
        ingredient.gramsPerMilliliter = 0.53
        XCTAssertEqual(Readiness.check(line: line, ingredients: [ingredient], pantry: [item]).status, .ready)
    }

    func testConfirmedAliasMatchesWithoutGuessing() {
        let chicken = Ingredient(name: "Chicken breast, raw")
        let cooked = Ingredient(name: "Chicken breast, cooked")
        XCTAssertNil(IngredientMatcher.match(name: "chicken breast", linkedID: nil, ingredients: [chicken, cooked]))
        chicken.confirmedAliases = ["chicken breast"]
        XCTAssertEqual(IngredientMatcher.match(name: "Chicken Breast", linkedID: nil,
                                               ingredients: [chicken, cooked])?.id, chicken.id)
    }

    func testIngredientSpecificCountConversionAndDiscard() throws {
        let ingredient = Ingredient(name: "Eggs")
        XCTAssertNil(Quantity.convert(2, from: "count", to: "g", ingredient: ingredient))
        ingredient.gramsPerCount = 50
        XCTAssertEqual(Quantity.convert(2, from: "count", to: "g", ingredient: ingredient), 100)
        let container = try ModelContainer(for: Ingredient.self, PantryItem.self, InventoryTransaction.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let item = PantryItem(ingredientID: ingredient.id, trackingMode: "exact", quantity: 300, unit: "g")
        context.insert(ingredient); context.insert(item)
        try context.save()
        try KitchenStore.discard(item: item, amount: 2, unit: "count", ingredient: ingredient, context: context)
        XCTAssertEqual(item.quantity, 200)
        XCTAssertEqual(try context.fetch(FetchDescriptor<InventoryTransaction>()).first?.kind, "discard")
        XCTAssertThrowsError(try KitchenStore.discard(item: item, amount: 5, unit: "count", ingredient: ingredient, context: context))
    }

    func testSessionSnapshotSurvivesRecipeChange() throws {
        let recipe = Recipe(name: "Bread")
        let line = RecipeIngredient(recipeID: recipe.id, name: "Flour", amount: 500, unit: "g", position: 0)
        let container = try ModelContainer(for: Recipe.self, RecipeIngredient.self, RecipeStep.self, CookingSession.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.insert(recipe); context.insert(line)
        let session = try KitchenStore.start(recipe: recipe, lines: [line], steps: [], sessions: [], context: context)
        line.amount = 700
        try context.save()
        XCTAssertEqual(session.snapshot.ingredients.first?.amount, 500)
    }

    func testMealDTOIgnoresBlankIngredients() throws {
        let json = #"{"meals":[{"idMeal":"1","strMeal":"Soup","strIngredient1":"Salt","strMeasure1":"to taste","strIngredient2":" ","strMeasure2":"1 tin"}]}"#.data(using: .utf8)!
        let meal = try JSONDecoder().decode(MealEnvelope.self, from: json).meals!.first!
        XCTAssertEqual(meal.ingredients.count, 20)
        XCTAssertEqual(meal.ingredients[0], "Salt")
        XCTAssertNil(Quantity.parse(meal.measures[0]).0)
    }

    func testShoppingGenerationAndPurchaseAreIdempotent() throws {
        let container = try ModelContainer(for: Recipe.self, RecipeIngredient.self, Ingredient.self,
                                           PantryItem.self, InventoryTransaction.self, ShoppingItem.self,
                                           ShoppingContribution.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let recipe = Recipe(name: "Soup")
        let line = RecipeIngredient(recipeID: recipe.id, name: "Carrots", amount: 3, unit: "count", position: 0)
        context.insert(recipe); context.insert(line)
        try KitchenStore.addShopping(recipe: recipe, lines: [line], ingredients: [], pantry: [],
                                     items: [], contributions: [], context: context)
        let items = try context.fetch(FetchDescriptor<ShoppingItem>())
        let contributions = try context.fetch(FetchDescriptor<ShoppingContribution>())
        try KitchenStore.addShopping(recipe: recipe, lines: [line], ingredients: [], pantry: [],
                                     items: items, contributions: contributions, context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ShoppingItem>()).count, 1)
        XCTAssertEqual(items[0].amount, 3)
        try KitchenStore.purchase(name: "Carrots", ingredientID: nil, amount: 3, unit: "count",
                                  shoppingItem: items[0], ingredients: [], pantry: [], context: context)
        XCTAssertThrowsError(try KitchenStore.purchase(name: "Carrots", ingredientID: nil, amount: 3,
                                                        unit: "count", shoppingItem: items[0],
                                                        ingredients: [], pantry: [], context: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<InventoryTransaction>()).count, 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ShoppingContribution>()).isEmpty)
    }

    func testCompatibleRecipeShortagesMerge() throws {
        let container = try ModelContainer(for: Recipe.self, RecipeIngredient.self, Ingredient.self,
                                           PantryItem.self, ShoppingItem.self, ShoppingContribution.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let recipe = Recipe(name: "Cake")
        let a = RecipeIngredient(recipeID: recipe.id, name: "Sugar", amount: 100, unit: "g", position: 0)
        let b = RecipeIngredient(recipeID: recipe.id, name: "Sugar", amount: 50, unit: "g", position: 1)
        context.insert(recipe); context.insert(a); context.insert(b)
        try KitchenStore.addShopping(recipe: recipe, lines: [a, b], ingredients: [], pantry: [],
                                     items: [], contributions: [], context: context)
        let items = try context.fetch(FetchDescriptor<ShoppingItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].amount, 150)
    }

    func testRepeatedIngredientUsesSharedPantryBalance() {
        let ingredient = Ingredient(name: "Sugar")
        let item = PantryItem(ingredientID: ingredient.id, trackingMode: "exact", quantity: 50, unit: "g")
        let recipeID = UUID()
        let first = RecipeIngredient(recipeID: recipeID, name: "Sugar", amount: 100, unit: "g", position: 0)
        let second = RecipeIngredient(recipeID: recipeID, name: "Sugar", amount: 50, unit: "g", position: 1)
        let result = Readiness.evaluate(lines: [first, second], ingredients: [ingredient], pantry: [item])
        XCTAssertEqual(result[first.id]?.shortage, 50)
        XCTAssertEqual(result[second.id]?.shortage, 50)
    }

    func testUSDAFoodMapperKeepsUnitsAndBasis() throws {
        let json = #"{"fdcId":42,"description":"Milk","dataType":"Branded","servingSizeUnit":"ML","foodNutrients":[{"nutrient":{"id":1008,"name":"Energy","unitName":"KCAL"},"amount":60}]}"#.data(using: .utf8)!
        let food = try JSONDecoder().decode(USDAFoodDTO.self, from: json)
        let ingredient = Ingredient(name: "Milk")
        FoodMapper.confirm(food, for: ingredient)
        XCTAssertEqual(ingredient.fdcID, 42)
        XCTAssertEqual(ingredient.nutrients.first?.amount, 60)
        XCTAssertEqual(ingredient.nutrients.first?.unit, "KCAL")
        XCTAssertEqual(ingredient.nutrients.first?.basis, "per 100 mL")
    }
}

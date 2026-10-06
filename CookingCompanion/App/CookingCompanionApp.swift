import SwiftUI
import SwiftData

@main
struct CookingCompanionApp: App {
    init() {
        let preferences = UserDefaults.standard
        if preferences.string(forKey: "serviceBaseURL") == nil,
           let previousURL = preferences.string(forKey: "usdaBaseURL") {
            preferences.set(previousURL, forKey: "serviceBaseURL")
        }
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeStep.self, Ingredient.self,
            PantryItem.self, InventoryTransaction.self, CookingSession.self,
            IngredientUsage.self, ShoppingItem.self, ShoppingContribution.self, AppSetting.self
        ])
        do { return try ModelContainer(for: schema) }
        catch { fatalError("Unable to open local data: \(error)") }
    }()

    var body: some Scene {
        WindowGroup { RootView() }
            .modelContainer(sharedModelContainer)
    }
}

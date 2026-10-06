import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var recipes: [Recipe]
    @Query private var ingredients: [Ingredient]
    @Query private var pantry: [PantryItem]
    @AppStorage("usdaBaseURL") private var baseURL = "http://127.0.0.1:8000"
    @State private var mealDBKey = ""
    @State private var keyMessage: String?
    @State private var message: String?
    var body: some View {
        Form {
            Section("TheMealDB discovery") {
                SecureField("TheMealDB V2 API key", text: $mealDBKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save TheMealDB key") {
                    if !TheMealDBKeyStore.isValid(mealDBKey.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        keyMessage = "Enter only the API key, using letters, numbers, hyphens, or underscores."
                    } else {
                        keyMessage = TheMealDBKeyStore.save(mealDBKey)
                            ? "Saved on this iPhone. Discovery now uses TheMealDB V2."
                            : "Could not save the key. Try again."
                    }
                }
                if TheMealDBKeyStore.read() != nil {
                    Button("Remove key", role: .destructive) {
                        if TheMealDBKeyStore.remove() { mealDBKey = ""; keyMessage = "Key removed. Discovery uses the V1 development API." }
                    }
                }
                Text("Paste only the key, not the full URL. Without a saved key, Discover uses the V1 development API.")
                    .font(.caption).foregroundStyle(.secondary)
                if let keyMessage { Text(keyMessage).font(.caption).foregroundStyle(.secondary) }
            }
            Section("USDA connection") {
                TextField("Mac server URL", text: $baseURL)
                    .textInputAutocapitalization(.never).keyboardType(.URL)
                Text("In Simulator, use http://127.0.0.1:8000. On your iPhone, use your Mac’s local network address, such as http://192.168.1.20:8000.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Portfolio demo") {
                Button("Load sample kitchen") { loadDemo() }
                Text("Adds a pancake recipe and pantry items once so you can try the complete workflow.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message { Text(message).foregroundStyle(.secondary) }
            }
            Section("Sources") {
                Link("TheMealDB", destination: URL(string: "https://www.themealdb.com")!)
                Link("USDA FoodData Central", destination: URL(string: "https://fdc.nal.usda.gov")!)
            }
        }
        .navigationTitle("Settings")
        .onAppear { mealDBKey = TheMealDBKeyStore.read() ?? "" }
    }
    private func loadDemo() {
        guard !recipes.contains(where: { $0.sourceID == "sample-pancakes" }) else { message = "Sample kitchen is already loaded."; return }
        let recipe = Recipe(name: "Buttermilk Pancakes", source: "demo", sourceID: "sample-pancakes", servings: 4)
        context.insert(recipe)
        let specs: [(String, Double, String, Double, String)] = [
            ("Bread flour", 250, "g", 5, "lb"), ("Eggs", 2, "count", 6, "count"),
            ("Milk", 300, "ml", 1000, "ml")
        ]
        var lineIDs: [UUID] = []
        for (index, spec) in specs.enumerated() {
            let existing = ingredients.first { $0.normalizedName == IngredientMatcher.normalize(spec.0) }
            let ingredient = existing ?? Ingredient(name: spec.0)
            if existing == nil { context.insert(ingredient) }
            let line = RecipeIngredient(recipeID: recipe.id, name: spec.0, amount: spec.1,
                                        unit: spec.2, originalMeasure: "\(spec.1.formatted()) \(spec.2)",
                                        position: index, ingredientID: ingredient.id)
            context.insert(line)
            lineIDs.append(line.id)
            if !pantry.contains(where: { $0.ingredientID == ingredient.id }) {
                let canonical = Quantity.canonical(spec.3, spec.4)!
                let item = PantryItem(ingredientID: ingredient.id, trackingMode: spec.0 == "Bread flour" ? "estimated" : "exact",
                                      quantity: canonical.0, unit: canonical.1, displayUnit: spec.4)
                context.insert(item)
                context.insert(InventoryTransaction(pantryItemID: item.id, ingredientID: ingredient.id,
                                                    kind: "correction", signedQuantity: canonical.0,
                                                    unit: canonical.1, note: "Sample starting balance"))
            }
        }
        let mixing = RecipeStep(recipeID: recipe.id, position: 0, text: "Mix the flour, eggs, and milk until just combined.")
        mixing.ingredientIDs = lineIDs
        context.insert(mixing)
        context.insert(RecipeStep(recipeID: recipe.id, position: 1, text: "Cook portions in a lightly oiled skillet until golden."))
        do { try context.save(); message = "Sample kitchen loaded." }
        catch { message = error.localizedDescription }
    }
}

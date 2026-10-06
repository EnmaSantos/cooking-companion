import SwiftUI
import SwiftData

struct RootView: View {
    @Query private var sessions: [CookingSession]
    @State private var showActive = false
    private var active: CookingSession? { sessions.first { $0.status == "active" } }
    var body: some View {
        TabView {
            NavigationStack { RecipesView() }.tabItem { Label("Recipes", systemImage: "book.closed") }
            NavigationStack { PantryView() }.tabItem { Label("Pantry", systemImage: "cabinet") }
            NavigationStack { ShoppingView() }.tabItem { Label("Shopping", systemImage: "cart") }
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .safeAreaInset(edge: .bottom) {
            if let active {
                Button { showActive = true } label: {
                    Label("Resume \(active.recipeName)", systemImage: "play.fill")
                        .frame(maxWidth: .infinity).padding(10)
                }
                .buttonStyle(.borderedProminent).padding(.horizontal)
                .background(.regularMaterial)
            }
        }
        .sheet(isPresented: $showActive) {
            if let active { NavigationStack { CookingView(session: active) } }
        }
    }
}

struct RecipesView: View {
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @Query private var lines: [RecipeIngredient]
    @Query private var ingredients: [Ingredient]
    @Query private var pantry: [PantryItem]
    @State private var selection = 0
    @State private var showNew = false
    var body: some View {
        VStack {
            Picker("Recipes", selection: $selection) {
                Text("My Recipes").tag(0); Text("Discover").tag(1)
            }.pickerStyle(.segmented).padding(.horizontal)
            if selection == 0 {
                List {
                    Section("What can I make?") {
                        if recipes.isEmpty { ContentUnavailableView("No saved recipes", systemImage: "book", description: Text("Create or discover your first recipe.")) }
                        ForEach(recipes.sorted {
                            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
                            return rank($0) < rank($1)
                        }) { recipe in
                            NavigationLink { RecipeDetailView(recipe: recipe) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 5) {
                                            Text(recipe.name).font(.headline)
                                            if recipe.isFavorite { Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink) }
                                        }
                                        Text(recipe.source == "TheMealDB" ? "TheMealDB" : "My recipe")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(status(recipe)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else { DiscoverView() }
        }
        .navigationTitle("Recipes")
        .toolbar { Button { showNew = true } label: { Image(systemName: "plus") }.accessibilityLabel("Create recipe") }
        .sheet(isPresented: $showNew) { NavigationStack { RecipeEditorView() } }
    }
    private func rank(_ recipe: Recipe) -> Int {
        let recipeLines = lines.filter { $0.recipeID == recipe.id }
        let states = Readiness.evaluate(lines: recipeLines, ingredients: ingredients, pantry: pantry)
        let values = recipeLines.compactMap { states[$0.id]?.status }
        if values.isEmpty { return 3 }
        if values.contains(.missing) { return 2 }
        if values.contains(.needsReview) { return 3 }
        if values.contains(.likelyReady) { return 1 }
        return 0
    }
    private func status(_ recipe: Recipe) -> String {
        switch rank(recipe) {
        case 0: return "Ready"
        case 1: return "Likely ready"
        case 2: return "Missing items"
        default: return "Needs review"
        }
    }
}

struct DiscoverView: View {
    @State private var mode = 0
    @State private var query = ""
    @State private var ingredient = ""
    @State private var category = "All"
    @State private var categories: [MealCategory] = []
    @State private var results: [MealDTO] = []
    @State private var loading = false
    @State private var error: String?
    private var service: TheMealDBService { TheMealDBService() }
    var body: some View {
        List {
            Section {
                Picker("Search by", selection: $mode) {
                    Text("Name").tag(0); Text("Category").tag(1); Text("Ingredient").tag(2)
                }
                .pickerStyle(.segmented)
                if mode == 0 { TextField("Search recipes", text: $query).submitLabel(.search).onSubmit { Task { await search() } } }
                if mode == 1 {
                    Picker("Category", selection: $category) {
                        Text("Choose category").tag("All")
                        ForEach(categories) { Text($0.strCategory).tag($0.strCategory) }
                    }
                }
                if mode == 2 { TextField("One ingredient", text: $ingredient).textInputAutocapitalization(.never).onSubmit { Task { await search() } } }
                Button("Search") { Task { await search() } }
            }
            if loading { ProgressView("Searching…") }
            if let error { ContentUnavailableView(error, systemImage: "wifi.exclamationmark") ; Button("Retry") { Task { await search() } } }
            if !loading && error == nil && results.isEmpty { ContentUnavailableView("No recipes yet", systemImage: "magnifyingglass", description: Text("Search by name, category, or one ingredient.")) }
            ForEach(results) { meal in
                NavigationLink { DiscoveredRecipeView(mealID: meal.idMeal) } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: URL(string: meal.strMealThumb ?? "")) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: "fork.knife").frame(maxWidth: .infinity, maxHeight: .infinity) }
                            .frame(width: 54, height: 54).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(meal.strMeal)
                    }
                }
            }
        }
        .task {
            guard categories.isEmpty else { return }
            categories = (try? await service.categories()) ?? []
        }
    }
    private func search() async {
        loading = true; error = nil
        do {
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let i = ingredient.trimmingCharacters(in: .whitespacesAndNewlines)
            switch mode {
            case 1: results = category == "All" ? [] : try await service.filter(category: category, ingredient: nil)
            case 2: results = i.isEmpty ? [] : try await service.filter(category: nil, ingredient: i)
            default: results = try await service.search(q)
            }
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}

struct DiscoveredRecipeView: View {
    let mealID: String
    @Environment(\.modelContext) private var context
    @Query private var savedRecipes: [Recipe]
    @State private var meal: MealDTO?
    @State private var loading = true
    @State private var error: String?
    @State private var saved: Recipe?
    var body: some View {
        Group {
            if loading { ProgressView("Loading recipe…") }
            else if let error { ContentUnavailableView(error, systemImage: "wifi.exclamationmark"); Button("Retry") { Task { await fetch() } } }
            else if let meal {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        AsyncImage(url: URL(string: meal.strMealThumb ?? "")) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.1) }
                            .frame(height: 220).clipped()
                        Text(meal.strMeal).font(.largeTitle.bold())
                        Text("Source: TheMealDB").font(.caption).foregroundStyle(.secondary)
                        Text("Servings: not provided").font(.caption)
                        Text("Ingredients").font(.title2.bold())
                        ForEach(0..<20, id: \.self) { index in
                            let name = meal.ingredients[index].trimmingCharacters(in: .whitespacesAndNewlines)
                            if !name.isEmpty { Text("\(meal.measures[index]) \(name)") }
                        }
                        Text("Instructions").font(.title2.bold())
                        Text(meal.strInstructions ?? "Instructions unavailable")
                        if let saved { NavigationLink("Open saved recipe") { RecipeDetailView(recipe: saved) }.buttonStyle(.borderedProminent) }
                        else { Button("Save to My Recipes") { save(meal) }.buttonStyle(.borderedProminent) }
                    }.padding()
                }
            }
        }
        .navigationTitle("Discover")
        .task { await fetch() }
    }
    private func fetch() async {
        loading = true; error = nil
        do { meal = try await TheMealDBService().details(id: mealID) }
        catch { self.error = error.localizedDescription }
        saved = savedRecipes.first { $0.source == "TheMealDB" && $0.sourceID == mealID }
        loading = false
    }
    private func save(_ meal: MealDTO) {
        do {
            let recipe = try RecipeMapper.save(meal, existing: savedRecipes, context: context)
            saved = recipe
            Task { await RecipeMapper.cacheImage(for: recipe); try? context.save() }
        } catch { self.error = error.localizedDescription }
    }
}

struct RecipeDetailView: View {
    let recipe: Recipe
    @Environment(\.modelContext) private var context
    @Query private var allLines: [RecipeIngredient]
    @Query private var allSteps: [RecipeStep]
    @Query private var allIngredients: [Ingredient]
    @Query private var pantry: [PantryItem]
    @Query private var sessions: [CookingSession]
    @Query private var shopping: [ShoppingItem]
    @Query private var contributions: [ShoppingContribution]
    @State private var showEditor = false
    @State private var showCook = false
    @State private var error: String?
    private var lines: [RecipeIngredient] { allLines.filter { $0.recipeID == recipe.id }.sorted { $0.position < $1.position } }
    private var steps: [RecipeStep] { allSteps.filter { $0.recipeID == recipe.id }.sorted { $0.position < $1.position } }
    private var readiness: [UUID: ReadinessResult] { Readiness.evaluate(lines: lines, ingredients: allIngredients, pantry: pantry) }
    var body: some View {
        List {
            if let data = recipe.imageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill().frame(height: 210).clipped().listRowInsets(EdgeInsets())
            } else if let url = recipe.imageURL.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.1) }
                    .frame(height: 210).clipped().listRowInsets(EdgeInsets())
            }
            Section {
                Text(recipe.source == "TheMealDB" ? "TheMealDB recipe" : "My recipe").foregroundStyle(.secondary)
                Text(recipe.servings.map { "Serves \($0)" } ?? "Servings need review")
                if recipe.source == "TheMealDB", let url = recipe.sourceURL.flatMap(URL.init(string:)) {
                    Link("View source", destination: url)
                }
            }
            Section("Pantry check") {
                ForEach(lines) { line in
                    let result = readiness[line.id] ?? ReadinessResult(status: .needsReview, shortage: nil, unit: nil)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading) {
                            Text(line.name)
                            Text(line.originalMeasure.isEmpty ? Quantity.format(line.amount, unit: line.unit) : line.originalMeasure)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(label(result.status)).font(.caption).foregroundStyle(result.status == .missing ? .red : .secondary)
                        Menu {
                            ForEach(allIngredients) { ingredient in
                                Button(ingredient.name) {
                                    line.ingredientID = ingredient.id
                                    try? context.save()
                                }
                            }
                        } label: { Image(systemName: "link").accessibilityLabel("Match \(line.name) to pantry ingredient") }
                    }
                }
                Button("Add missing items to Shopping") {
                    do { try KitchenStore.addShopping(recipe: recipe, lines: lines, ingredients: allIngredients, pantry: pantry, items: shopping, contributions: contributions, context: context) }
                    catch { self.error = error.localizedDescription }
                }
            }
            Section("Steps") {
                ForEach(steps) { step in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(step.position + 1). \(step.text)")
                        let names = lines.filter { step.ingredientIDs.contains($0.id) }.map(\.name)
                        if !names.isEmpty { Text("Uses: \(names.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            Section {
                Button("Start Cooking") {
                    do { _ = try KitchenStore.start(recipe: recipe, lines: lines, steps: steps, sessions: sessions, context: context); showCook = true }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
                if let error { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle(recipe.name)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { recipe.isFavorite.toggle(); try? context.save() } label: { Image(systemName: recipe.isFavorite ? "heart.fill" : "heart") }
                    .accessibilityLabel(recipe.isFavorite ? "Remove favorite" : "Favorite")
                Button("Edit") { showEditor = true }
            }
        }
        .sheet(isPresented: $showEditor) { NavigationStack { RecipeEditorView(recipe: recipe, lines: lines, steps: steps) } }
        .sheet(isPresented: $showCook) {
            if let session = sessions.first(where: { $0.status == "active" && $0.recipeID == recipe.id }) { NavigationStack { CookingView(session: session) } }
        }
    }
    private func label(_ status: ReadinessStatus) -> String {
        switch status { case .ready: return "Ready"; case .likelyReady: return "Likely"; case .missing: return "Missing"; case .needsReview: return "Review" }
    }
}

private struct DraftIngredient: Identifiable {
    var id = UUID()
    var name = ""
    var amount = ""
    var unit = "g"
    var original = ""
    var linkedID: UUID?
}
private struct DraftStep: Identifiable { var id = UUID(); var text = ""; var ingredientIDs: [UUID] = [] }

struct RecipeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let recipe: Recipe?
    @State private var name: String
    @State private var servings: String
    @State private var ingredients: [DraftIngredient]
    @State private var steps: [DraftStep]
    @State private var error: String?
    init(recipe: Recipe? = nil, lines: [RecipeIngredient] = [], steps: [RecipeStep] = []) {
        self.recipe = recipe
        _name = State(initialValue: recipe?.name ?? "")
        _servings = State(initialValue: recipe?.servings.map { String($0) } ?? "")
        _ingredients = State(initialValue: lines.map { DraftIngredient(id: $0.id, name: $0.name, amount: $0.amount.map { String($0) } ?? "", unit: $0.unit ?? "g", original: $0.originalMeasure, linkedID: $0.ingredientID) })
        _steps = State(initialValue: steps.map { DraftStep(id: $0.id, text: $0.text, ingredientIDs: $0.ingredientIDs) })
    }
    var body: some View {
        Form {
            Section("Recipe") {
                TextField("Name", text: $name)
                TextField("Servings (optional)", text: $servings).keyboardType(.numberPad)
            }
            Section("Ingredients") {
                ForEach($ingredients) { $item in
                    VStack(alignment: .leading) {
                        TextField("Ingredient name", text: $item.name)
                        HStack {
                            TextField("Amount", text: $item.amount).keyboardType(.decimalPad)
                            Picker("Unit", selection: $item.unit) {
                                ForEach(["g", "kg", "oz", "lb", "ml", "l", "tsp", "tbsp", "cup", "count"], id: \.self) { Text($0).tag($0) }
                            }.labelsHidden()
                        }
                        if !item.original.isEmpty { Text("Original: \(item.original)").font(.caption).foregroundStyle(.secondary) }
                    }
                }.onDelete { ingredients.remove(atOffsets: $0) }
                Button("Add ingredient") { ingredients.append(DraftIngredient()) }
            }
            Section("Steps") {
                ForEach($steps) { $step in
                    VStack(alignment: .leading) {
                        TextField("Step", text: $step.text, axis: .vertical).lineLimit(2...5)
                        Menu {
                            ForEach(ingredients) { item in
                                Button {
                                    if step.ingredientIDs.contains(item.id) { step.ingredientIDs.removeAll { $0 == item.id } }
                                    else { step.ingredientIDs.append(item.id) }
                                } label: {
                                    Label(item.name.isEmpty ? "Unnamed ingredient" : item.name,
                                          systemImage: step.ingredientIDs.contains(item.id) ? "checkmark" : "plus")
                                }
                            }
                        } label: { Text("Ingredients in this step (\(step.ingredientIDs.count))").font(.caption) }
                    }
                }
                    .onDelete { steps.remove(atOffsets: $0) }
                Button("Add step") { steps.append(DraftStep()) }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(recipe == nil ? "New Recipe" : "Edit Recipe")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }
    }
    private func save() {
        let target = recipe ?? Recipe(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        if recipe == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.servings = Int(servings)
        if let recipe {
            for item in ((try? context.fetch(FetchDescriptor<RecipeIngredient>())) ?? []).filter({ $0.recipeID == recipe.id }) { context.delete(item) }
            for item in ((try? context.fetch(FetchDescriptor<RecipeStep>())) ?? []).filter({ $0.recipeID == recipe.id }) { context.delete(item) }
        }
        var newLineIDs: [UUID: UUID] = [:]
        for (index, item) in ingredients.enumerated() where !item.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let line = RecipeIngredient(recipeID: target.id, name: item.name.trimmingCharacters(in: .whitespaces), amount: Double(item.amount), unit: Double(item.amount) == nil ? nil : item.unit,
                                        originalMeasure: item.original, position: index, ingredientID: item.linkedID)
            context.insert(line)
            newLineIDs[item.id] = line.id
        }
        for (index, step) in steps.enumerated() where !step.text.trimmingCharacters(in: .whitespaces).isEmpty {
            let savedStep = RecipeStep(recipeID: target.id, position: index, text: step.text)
            savedStep.ingredientIDs = step.ingredientIDs.compactMap { newLineIDs[$0] }
            context.insert(savedStep)
        }
        do { try context.save(); dismiss() } catch { context.rollback(); self.error = error.localizedDescription }
    }
}

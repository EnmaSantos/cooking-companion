import SwiftUI
import SwiftData

struct PantryView: View {
    @Query private var pantry: [PantryItem]
    @Query private var ingredients: [Ingredient]
    @Query(sort: \InventoryTransaction.happenedAt, order: .reverse) private var transactions: [InventoryTransaction]
    @State private var showAdd = false
    var body: some View {
        List {
            if pantry.isEmpty {
                ContentUnavailableView("Your pantry is empty", systemImage: "cabinet", description: Text("Add what you have to check recipes."))
            }
            ForEach(pantry) { item in
                NavigationLink {
                    PantryDetailView(item: item)
                } label: {
                    let ingredient = ingredients.first { $0.id == item.ingredientID }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ingredient?.name ?? "Ingredient").font(.headline)
                        Text(summary(item)).foregroundStyle(.secondary)
                            .font(.subheadline)
                        if low(item) { Label("Running low", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                    }
                }
            }
            if !transactions.isEmpty {
                Section("Recent changes") {
                    ForEach(transactions.prefix(5)) { tx in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(tx.note.isEmpty ? tx.kind.capitalized : tx.note)
                                Text(tx.happenedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(tx.signedQuantity >= 0 ? "+" : "")\(Quantity.format(tx.signedQuantity, unit: tx.unit))")
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle("Pantry")
        .toolbar { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add pantry item") }
        .sheet(isPresented: $showAdd) { NavigationStack { PantryEditorView() } }
    }
    private func summary(_ item: PantryItem) -> String {
        if item.trackingMode == "available" { return "Available" }
        let converted = item.quantity.flatMap { amount in item.unit.flatMap { unit in item.displayUnit.flatMap { Quantity.convert(amount, from: unit, to: $0) } } }
        return (item.trackingMode == "estimated" ? "About " : "") + Quantity.format(converted ?? item.quantity, unit: item.displayUnit ?? item.unit)
    }
    private func low(_ item: PantryItem) -> Bool {
        guard item.trackingMode != "available", let quantity = item.quantity, let start = item.startingQuantity, start > 0 else { return false }
        return quantity <= start * item.lowFraction
    }
}

struct PantryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var pantry: [PantryItem]
    @Query private var ingredients: [Ingredient]
    let item: PantryItem?
    @State private var name: String
    @State private var mode: String
    @State private var quantity: String
    @State private var unit: String
    @State private var lowPercent: String
    @State private var error: String?
    init(item: PantryItem? = nil, name: String = "") {
        self.item = item
        _name = State(initialValue: name)
        _mode = State(initialValue: item?.trackingMode ?? "exact")
        _quantity = State(initialValue: item?.quantity.map { String($0) } ?? "")
        _unit = State(initialValue: item?.displayUnit ?? "g")
        _lowPercent = State(initialValue: String(Int((item?.lowFraction ?? 0.2) * 100)))
    }
    var body: some View {
        Form {
            TextField("Ingredient", text: $name)
            Picker("Tracking", selection: $mode) {
                Text("Exact").tag("exact")
                Text("Estimated").tag("estimated")
                Text("Availability only").tag("available")
            }
            if mode != "available" {
                HStack {
                    TextField("Quantity", text: $quantity).keyboardType(.decimalPad)
                    Picker("Unit", selection: $unit) {
                        ForEach(["g", "kg", "oz", "lb", "ml", "l", "tsp", "tbsp", "cup", "count"], id: \.self) { Text($0).tag($0) }
                    }.labelsHidden()
                }
                TextField("Low warning (%)", text: $lowPercent).keyboardType(.numberPad)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(item == nil ? "Add Pantry Item" : "Edit Pantry Item")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
        .onAppear {
            if let item, name.isEmpty { name = ingredients.first(where: { $0.id == item.ingredientID })?.name ?? "" }
            if let item, item.trackingMode != "available", let amount = item.quantity, let from = item.unit,
               let shown = item.displayUnit,
               let display = Quantity.convert(amount, from: from, to: shown,
                                              ingredient: ingredients.first(where: { $0.id == item.ingredientID })) {
                quantity = String(display)
            }
        }
    }
    private func save() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { error = "Enter an ingredient name."; return }
        let parsed: (Double, String)?
        if mode == "available" { parsed = nil }
        else {
            guard let value = Double(quantity), value >= 0, let converted = Quantity.canonical(value, unit) else { error = "Enter a valid quantity and unit."; return }
            parsed = converted
        }
        let fraction = min(1, max(0, (Double(lowPercent) ?? 20) / 100))
        if let item {
            let ingredient = ingredients.first(where: { $0.id == item.ingredientID })
            let stored: (Double, String)?
            if let parsed, let oldUnit = item.unit {
                guard let converted = Quantity.convert(parsed.0, from: parsed.1, to: oldUnit, ingredient: ingredient) else {
                    error = "Set an ingredient-specific conversion before changing dimensions."; return
                }
                stored = (converted, oldUnit)
            } else { stored = parsed }
            if let ingredient {
                let duplicate = ingredients.contains { $0.id != ingredient.id && $0.normalizedName == IngredientMatcher.normalize(clean) }
                if duplicate { error = "Another ingredient already has this name."; return }
                ingredient.name = clean
                ingredient.normalizedName = IngredientMatcher.normalize(clean)
            }
            let old = item.quantity ?? 0
            let previousUnit = item.unit
            item.trackingMode = mode; item.quantity = stored?.0; item.unit = stored?.1
            item.displayUnit = mode == "available" ? nil : unit
            item.lowFraction = fraction; item.lastConfirmedAt = .now
            if let stored {
                item.startingQuantity = max(item.startingQuantity ?? 0, stored.0)
                let delta = stored.0 - old
                if abs(delta) > 0.000001 {
                    context.insert(InventoryTransaction(pantryItemID: item.id, ingredientID: item.ingredientID,
                                                        kind: "correction", signedQuantity: delta, unit: stored.1, note: "Manual balance correction"))
                }
            } else if old > 0, let oldUnit = previousUnit {
                context.insert(InventoryTransaction(pantryItemID: item.id, ingredientID: item.ingredientID,
                                                    kind: "correction", signedQuantity: -old, unit: oldUnit,
                                                    note: "Changed to availability tracking"))
            }
        } else {
            let normalized = IngredientMatcher.normalize(clean)
            let ingredient = ingredients.first { $0.normalizedName == normalized } ?? Ingredient(name: clean)
            if !ingredients.contains(where: { $0.id == ingredient.id }) { context.insert(ingredient) }
            if pantry.contains(where: { $0.ingredientID == ingredient.id }) { error = "This ingredient is already in your pantry."; return }
            let newItem = PantryItem(ingredientID: ingredient.id, trackingMode: mode, quantity: parsed?.0,
                                     unit: parsed?.1, displayUnit: mode == "available" ? nil : unit, lowFraction: fraction)
            context.insert(newItem)
            if let parsed {
                context.insert(InventoryTransaction(pantryItemID: newItem.id, ingredientID: ingredient.id,
                                                    kind: "correction", signedQuantity: parsed.0, unit: parsed.1, note: "Starting balance"))
            }
        }
        do { try context.save(); dismiss() } catch { context.rollback(); self.error = error.localizedDescription }
    }
}

struct PantryDetailView: View {
    let item: PantryItem
    @Query private var ingredients: [Ingredient]
    @Query(sort: \InventoryTransaction.happenedAt, order: .reverse) private var transactions: [InventoryTransaction]
    @State private var edit = false
    @State private var linkFood = false
    @State private var conversions = false
    @State private var discard = false
    @State private var alias = false
    private var ingredient: Ingredient? { ingredients.first { $0.id == item.ingredientID } }
    var body: some View {
        List {
            Section("Balance") {
                Text(item.trackingMode == "available" ? "Available" : Quantity.format(item.quantity, unit: item.unit))
                Text("Tracking: \(item.trackingMode.capitalized)")
                Text("Last confirmed \(item.lastConfirmedAt.formatted(date: .abbreviated, time: .omitted))")
            }
            Section("USDA FoodData Central") {
                if let ingredient {
                    if let id = ingredient.fdcID {
                        Text("\(ingredient.fdcDescription ?? ingredient.name) · FDC \(id)")
                        ForEach(ingredient.nutrients) { nutrient in
                            HStack { Text(nutrient.name); Spacer(); Text("\(nutrient.amount.formatted()) \(nutrient.unit)") }
                        }
                        if !ingredient.nutrients.isEmpty { Text("Nutrient basis: \(ingredient.nutrients[0].basis)").font(.caption).foregroundStyle(.secondary) }
                    } else { Text("No food linked").foregroundStyle(.secondary) }
                    Button(ingredient.fdcID == nil ? "Find a USDA food" : "Change USDA food") { linkFood = true }
                }
            }
            if let ingredient {
                Section("Confirmed names") {
                    ForEach(ingredient.confirmedAliases, id: \.self) { name in Text(name) }
                    Button("Add alias") { alias = true }
                }
                Section("Ingredient conversions") {
                    Text("Volume and count convert to weight only when you enter a value for this ingredient.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let density = ingredient.gramsPerMilliliter { Text("1 mL = \(density.formatted()) g") }
                    if let each = ingredient.gramsPerCount { Text("1 count = \(each.formatted()) g") }
                    Button("Edit conversions") { conversions = true }
                }
            }
            Section("History") {
                ForEach(transactions.filter { $0.pantryItemID == item.id }) { tx in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(tx.note.isEmpty ? tx.kind.capitalized : tx.note)
                            Text(tx.happenedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(tx.signedQuantity >= 0 ? "+" : "")\(Quantity.format(tx.signedQuantity, unit: tx.unit))")
                    }
                }
            }
        }
        .navigationTitle(ingredient?.name ?? "Pantry Item")
        .toolbar {
            Button("Edit") { edit = true }
            if item.trackingMode != "available" { Button("Discard") { discard = true } }
        }
        .sheet(isPresented: $edit) { NavigationStack { PantryEditorView(item: item) } }
        .sheet(isPresented: $conversions) {
            if let ingredient { NavigationStack { IngredientConversionView(ingredient: ingredient) } }
        }
        .sheet(isPresented: $alias) {
            if let ingredient { NavigationStack { IngredientAliasView(ingredient: ingredient) } }
        }
        .sheet(isPresented: $discard) {
            NavigationStack { DiscardView(item: item, ingredient: ingredient) }
        }
        .sheet(isPresented: $linkFood) {
            if let ingredient { NavigationStack { FoodSearchView(ingredient: ingredient) } }
        }
    }
}

struct IngredientAliasView: View {
    let ingredient: Ingredient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var error: String?
    var body: some View {
        Form {
            Text("Confirm another recipe name for this ingredient. Future recipes using that exact name can match this pantry item.")
                .foregroundStyle(.secondary)
            TextField("Alias", text: $name)
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Confirm Alias")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
    }
    private func save() {
        let normalized = IngredientMatcher.normalize(name)
        guard !normalized.isEmpty else { error = "Enter a name."; return }
        if normalized != ingredient.normalizedName && !ingredient.confirmedAliases.contains(normalized) {
            var aliases = ingredient.confirmedAliases
            aliases.append(normalized)
            ingredient.confirmedAliases = aliases
        }
        do { try context.save(); dismiss() } catch { context.rollback(); self.error = error.localizedDescription }
    }
}

struct IngredientConversionView: View {
    let ingredient: Ingredient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var density = ""
    @State private var each = ""
    @State private var error: String?
    var body: some View {
        Form {
            Section("Ingredient-specific values") {
                TextField("Grams per 1 mL", text: $density).keyboardType(.decimalPad)
                TextField("Grams per 1 count", text: $each).keyboardType(.decimalPad)
                Text("Leave a conversion blank when you do not know it. USDA food matches do not fill these values automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Conversions")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
        .onAppear {
            density = ingredient.gramsPerMilliliter.map { String($0) } ?? ""
            each = ingredient.gramsPerCount.map { String($0) } ?? ""
        }
    }
    private func save() {
        let d = density.isEmpty ? nil : Double(density)
        let e = each.isEmpty ? nil : Double(each)
        guard (density.isEmpty || (d ?? 0) > 0), (each.isEmpty || (e ?? 0) > 0) else {
            error = "Enter positive values or leave the fields blank."; return
        }
        ingredient.gramsPerMilliliter = d
        ingredient.gramsPerCount = e
        do { try context.save(); dismiss() } catch { context.rollback(); self.error = error.localizedDescription }
    }
}

struct DiscardView: View {
    let item: PantryItem
    let ingredient: Ingredient?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var amount = ""
    @State private var unit = "g"
    @State private var error: String?
    var body: some View {
        Form {
            Text("Record food you threw away. This reduces the pantry balance and remains in its history.")
                .foregroundStyle(.secondary)
            TextField("Quantity", text: $amount).keyboardType(.decimalPad)
            Picker("Unit", selection: $unit) {
                ForEach(["g", "kg", "oz", "lb", "ml", "l", "tsp", "tbsp", "cup", "count"], id: \.self) { Text($0).tag($0) }
            }
            Button("Record discard", role: .destructive) {
                guard let value = Double(amount) else { error = "Enter a quantity."; return }
                do { try KitchenStore.discard(item: item, amount: value, unit: unit, ingredient: ingredient, context: context); dismiss() }
                catch { self.error = error.localizedDescription }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Discard food")
        .toolbar { Button("Cancel") { dismiss() } }
        .onAppear { unit = item.displayUnit ?? item.unit ?? "g" }
    }
}

struct FoodSearchView: View {
    let ingredient: Ingredient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("serviceBaseURL") private var baseURL = "http://127.0.0.1:8000"
    @State private var query = ""
    @State private var results: [USDAFoodDTO] = []
    @State private var error: String?
    @State private var loading = false
    @State private var selected: USDAFoodDTO?
    var body: some View {
        List {
            Section {
                TextField("Search food", text: $query).onSubmit { Task { await search() } }
                Button("Search") { Task { await search() } }
            }
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red); Button("Retry") { Task { await search() } } }
            ForEach(results) { food in
                Button { selected = food } label: {
                    VStack(alignment: .leading) {
                        Text(food.description).foregroundStyle(.primary)
                        Text("\(food.dataType ?? "Food") · FDC \(food.fdcId)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Match \(ingredient.name)")
        .toolbar { Button("Close") { dismiss() } }
        .task { query = ingredient.name; await search() }
        .confirmationDialog("Use this USDA food?", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }), presenting: selected) { food in
            Button("Confirm match") { Task { await confirm(food) } }
        } message: { food in Text("\(food.description) · FDC \(food.fdcId)") }
    }
    private func search() async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        loading = true; error = nil
        do { results = try await USDAProxyService().search(query, page: 1, baseURL: baseURL) }
        catch { self.error = error.localizedDescription }
        loading = false
    }
    private func confirm(_ food: USDAFoodDTO) async {
        do {
            let details = try await USDAProxyService().details(id: food.fdcId, baseURL: baseURL)
            FoodMapper.confirm(details, for: ingredient)
            try context.save(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

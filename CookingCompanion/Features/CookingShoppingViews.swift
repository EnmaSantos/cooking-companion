import SwiftUI
import SwiftData

struct CookingView: View {
    let session: CookingSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var showReview = false
    @State private var showCancel = false
    @State private var currentStep = 0
    var body: some View {
        let snapshot = session.snapshot
        VStack(alignment: .leading, spacing: 16) {
            if snapshot.steps.isEmpty {
                Text("No structured steps yet").font(.title2)
                Text("Use the ingredients checklist while cooking.").foregroundStyle(.secondary)
            } else {
                Text("Step \(currentStep + 1) of \(snapshot.steps.count)").font(.headline).foregroundStyle(.secondary)
                Text(snapshot.steps[currentStep].text).font(.title2).frame(maxWidth: .infinity, alignment: .leading)
                let stepIngredients = snapshot.ingredients.filter { snapshot.steps[currentStep].ingredientIDs.contains($0.id) }
                if !stepIngredients.isEmpty {
                    Text("For this step: \(stepIngredients.map(\.name).joined(separator: ", "))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button {
                    let id = snapshot.steps[currentStep].id
                    toggleStep(id, !session.snapshot.checkedSteps.contains(id))
                } label: {
                    Label("Step complete", systemImage: session.snapshot.checkedSteps.contains(snapshot.steps[currentStep].id) ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain)
                HStack {
                    Button("Previous") { setStep(max(0, currentStep - 1)) }.disabled(currentStep == 0)
                    Spacer()
                    Button("Next") { setStep(min(snapshot.steps.count - 1, currentStep + 1)) }.disabled(currentStep >= snapshot.steps.count - 1)
                }.buttonStyle(.bordered)
            }
            Divider()
            Text("Ingredients used").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(snapshot.ingredients) { item in
                        Button {
                            toggleIngredient(item.id, !session.snapshot.checkedIngredients.contains(item.id))
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: session.snapshot.checkedIngredients.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                VStack(alignment: .leading) {
                                    Text(item.name)
                                    Text(item.originalMeasure.isEmpty ? Quantity.format(item.amount, unit: item.unit) : item.originalMeasure)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }.frame(minHeight: 44)
                        }.buttonStyle(.plain).accessibilityLabel(item.name)
                    }
                }
            }
            Button("Finish and review usage") { showReview = true }
                .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
        }
        .padding()
        .navigationTitle(session.recipeName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Cancel Session") { showCancel = true } }
        .confirmationDialog("Cancel cooking?", isPresented: $showCancel) {
            Button("Discard session", role: .destructive) { session.status = "canceled"; try? context.save(); dismiss() }
        } message: { Text("Your pantry will not change.") }
        .sheet(isPresented: $showReview) { NavigationStack { UsageReviewView(session: session) } }
        .onAppear { currentStep = min(session.snapshot.currentStep, max(0, session.snapshot.steps.count - 1)); UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: session.status) { _, status in if status != "active" { dismiss() } }
    }
    private func toggleStep(_ id: UUID, _ checked: Bool) {
        var snapshot = session.snapshot
        if checked { snapshot.checkedSteps.insert(id) } else { snapshot.checkedSteps.remove(id) }
        session.snapshot = snapshot; try? context.save()
    }
    private func setStep(_ index: Int) {
        currentStep = index
        var snapshot = session.snapshot
        snapshot.currentStep = index
        session.snapshot = snapshot; try? context.save()
    }
    private func toggleIngredient(_ id: UUID, _ checked: Bool) {
        var snapshot = session.snapshot
        if checked { snapshot.checkedIngredients.insert(id) } else { snapshot.checkedIngredients.remove(id) }
        session.snapshot = snapshot; try? context.save()
    }
}

private struct UsageDraft: Identifiable {
    var id: UUID
    var name: String
    var ingredientID: UUID?
    var amount: String
    var unit: String
}

struct UsageReviewView: View {
    let session: CookingSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var pantry: [PantryItem]
    @Query private var ingredients: [Ingredient]
    @State private var drafts: [UsageDraft] = []
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Text("Only confirmed usage changes your pantry. Review each amount before finishing.")
                    .foregroundStyle(.secondary)
            }
            Section("Ingredient usage") {
                ForEach($drafts) { $draft in
                    VStack(alignment: .leading) {
                        Text(draft.name)
                        HStack {
                            TextField("Amount", text: $draft.amount).keyboardType(.decimalPad)
                            TextField("Unit", text: $draft.unit).frame(width: 65)
                        }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            Button("Confirm and finish") { confirm() }.buttonStyle(.borderedProminent)
        }
        .navigationTitle("Review Usage")
        .toolbar { Button("Back") { dismiss() } }
        .onAppear {
            guard drafts.isEmpty else { return }
            let snapshot = session.snapshot
            drafts = snapshot.ingredients.map { item in
                UsageDraft(id: item.id, name: item.name, ingredientID: item.ingredientID,
                           amount: snapshot.checkedIngredients.contains(item.id) ? (item.amount.map { String($0) } ?? "") : "",
                           unit: item.unit ?? "")
            }
        }
    }
    private func confirm() {
        for draft in drafts where !draft.amount.isEmpty {
            guard let amount = Double(draft.amount), amount >= 0, Quantity.canonical(amount, draft.unit) != nil else {
                error = "Enter a valid amount and compatible unit, or leave it blank."; return
            }
        }
        let inputs = drafts.map { UsageInput(id: $0.id, name: $0.name, ingredientID: $0.ingredientID,
                                            amount: Double($0.amount), unit: $0.unit.isEmpty ? nil : $0.unit) }
        do {
            try KitchenStore.finish(session: session, inputs: inputs, pantry: pantry, ingredients: ingredients, context: context)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct ShoppingView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ShoppingItem.createdAt) private var items: [ShoppingItem]
    @Query private var pantry: [PantryItem]
    @Query private var ingredients: [Ingredient]
    @Query private var contributions: [ShoppingContribution]
    @State private var newName = ""
    @State private var error: String?
    var body: some View {
        List {
            Section("Add item") {
                HStack {
                    TextField("Ingredient", text: $newName)
                    Button("Add") { addManual() }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("Add low-stock suggestions") { addLowStock() }
            }
            Section("To buy") {
                if items.filter({ !$0.purchased }).isEmpty { Text("Your list is clear.").foregroundStyle(.secondary) }
                ForEach(items.filter { !$0.purchased }) { item in
                    NavigationLink { ShoppingDetailView(item: item) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).font(.headline)
                            Text(item.amount == nil ? (item.note.isEmpty ? "Amount needs review" : item.note) : Quantity.format(item.amount, unit: item.unit))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.onDelete { offsets in remove(items.filter { !$0.purchased }, offsets: offsets) }
            }
            if !items.filter({ $0.purchased }).isEmpty {
                Section("Purchased") {
                    ForEach(items.filter { $0.purchased }) { item in Label(item.name, systemImage: "checkmark.circle.fill") }
                        .onDelete { offsets in remove(items.filter { $0.purchased }, offsets: offsets) }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Shopping")
    }
    private func addManual() {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        context.insert(ShoppingItem(name: clean, sourceKind: "manual"))
        do { try context.save(); newName = "" } catch { self.error = error.localizedDescription }
    }
    private func addLowStock() {
        for item in pantry {
            guard item.trackingMode != "available", let quantity = item.quantity,
                  let start = item.startingQuantity, start > 0,
                  quantity <= start * item.lowFraction,
                  let ingredient = ingredients.first(where: { $0.id == item.ingredientID }) else { continue }
            let key = "low:\(item.id.uuidString)"
            if contributions.contains(where: { $0.sourceKey == key }) { continue }
            let suggestion = ShoppingItem(name: ingredient.name, ingredientID: ingredient.id,
                                          amount: nil, unit: item.unit, note: "Running low", sourceKind: "lowStock", sourceID: item.id)
            context.insert(suggestion)
            context.insert(ShoppingContribution(sourceKey: key, shoppingItemID: suggestion.id, amount: nil, unit: item.unit))
        }
        do { try context.save() } catch { self.error = error.localizedDescription }
    }
    private func remove(_ source: [ShoppingItem], offsets: IndexSet) {
        for offset in offsets {
            let item = source[offset]
            for contribution in contributions where contribution.shoppingItemID == item.id { context.delete(contribution) }
            context.delete(item)
        }
        do { try context.save() } catch { context.rollback(); self.error = error.localizedDescription }
    }
}

struct ShoppingDetailView: View {
    let item: ShoppingItem
    @Environment(\.modelContext) private var context
    @Query private var pantry: [PantryItem]
    @Query private var ingredients: [Ingredient]
    @State private var amount: String = ""
    @State private var unit = "g"
    @State private var error: String?
    var body: some View {
        Form {
            Section("Purchase") {
                Text("Confirm what you bought before adding it to your pantry.")
                    .foregroundStyle(.secondary)
                TextField("Quantity", text: $amount).keyboardType(.decimalPad)
                Picker("Unit", selection: $unit) {
                    ForEach(["g", "kg", "oz", "lb", "ml", "l", "tsp", "tbsp", "cup", "count"], id: \.self) { Text($0).tag($0) }
                }
                Button("Record purchase") { purchase() }.disabled(item.purchased)
                if let error { Text(error).foregroundStyle(.red) }
            }
            Section("Find online") {
                if let google = URL(string: "https://www.google.com/search?q=buy+\(encoded(item.name))") { Link("Search Google", destination: google) }
                if let walmart = URL(string: "https://www.walmart.com/search?q=\(encoded(item.name))") { Link("Search Walmart", destination: walmart) }
            }
        }
        .navigationTitle(item.name)
        .onAppear { amount = item.amount.map { String($0) } ?? ""; unit = item.unit ?? "g" }
    }
    private func encoded(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text }
    private func purchase() {
        guard let amount = Double(amount) else { error = "Enter a purchase quantity."; return }
        do { try KitchenStore.purchase(name: item.name, ingredientID: item.ingredientID, amount: amount,
                                       unit: unit, shoppingItem: item, ingredients: ingredients, pantry: pantry, context: context) }
        catch { self.error = error.localizedDescription }
    }
}

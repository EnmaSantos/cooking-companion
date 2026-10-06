import Foundation
import SwiftData

enum Quantity {
    static let mass: Set<String> = ["g", "kg", "oz", "lb"]
    static let volume: Set<String> = ["ml", "l", "tsp", "tbsp", "cup", "fl oz"]
    static let counts: Set<String> = ["count", "clove", "slice", "egg"]

    static func canonical(_ value: Double, _ unit: String) -> (Double, String)? {
        switch unit.lowercased() {
        case "g": return (value, "g")
        case "kg": return (value * 1000, "g")
        case "oz": return (value * 28.349523125, "g")
        case "lb": return (value * 453.59237, "g")
        case "ml": return (value, "ml")
        case "l": return (value * 1000, "ml")
        case "tsp": return (value * 4.92892159375, "ml")
        case "tbsp": return (value * 14.78676478125, "ml")
        case "cup": return (value * 236.5882365, "ml")
        case "fl oz": return (value * 29.5735295625, "ml")
        case "count", "clove", "slice", "egg": return (value, "count")
        default: return nil
        }
    }

    static func convert(_ value: Double, from: String, to: String, ingredient: Ingredient? = nil) -> Double? {
        guard let a = canonical(value, from), let b = canonical(1, to) else { return nil }
        if a.1 == b.1 { return a.0 / b.0 }
        let grams: Double?
        switch a.1 {
        case "g": grams = a.0
        case "ml": grams = ingredient?.gramsPerMilliliter.map { a.0 * $0 }
        case "count": grams = ingredient?.gramsPerCount.map { a.0 * $0 }
        default: grams = nil
        }
        guard let grams else { return nil }
        switch b.1 {
        case "g": return grams / b.0
        case "ml": guard let density = ingredient?.gramsPerMilliliter, density > 0 else { return nil }; return grams / density / b.0
        case "count": guard let each = ingredient?.gramsPerCount, each > 0 else { return nil }; return grams / each / b.0
        default: return nil
        }
    }

    static func parse(_ original: String) -> (Double?, String?) {
        var value = original.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fractions = ["¼":" 1/4", "½":" 1/2", "¾":" 3/4", "⅓":" 1/3", "⅔":" 2/3", "⅛":" 1/8"]
        for (mark, replacement) in fractions { value = value.replacingOccurrences(of: mark, with: replacement) }
        value = value.trimmingCharacters(in: .whitespaces)
        let pattern = #"^(\d+/\d+|\d+(?:\.\d+)?(?:\s+\d+/\d+)?)\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let quantityRange = Range(match.range(at: 1), in: value),
              let restRange = Range(match.range(at: 2), in: value) else { return (nil, nil) }
        let tokens = value[quantityRange].split(separator: " ")
        let amount = tokens.compactMap { token -> Double? in
            let pair = token.split(separator: "/")
            if pair.count == 2, let a = Double(pair[0]), let b = Double(pair[1]), b != 0 { return a / b }
            return Double(token)
        }.reduce(0, +)
        guard amount > 0 else { return (nil, nil) }
        let rest = value[restRange].trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.isEmpty { return (amount, "count") }
        let aliases: [(String, String)] = [
            ("fluid ounces", "fl oz"), ("fluid ounce", "fl oz"), ("fl oz", "fl oz"),
            ("tablespoons", "tbsp"), ("tablespoon", "tbsp"), ("tbsp", "tbsp"),
            ("teaspoons", "tsp"), ("teaspoon", "tsp"), ("tsp", "tsp"),
            ("kilograms", "kg"), ("kilogram", "kg"), ("kg", "kg"),
            ("grams", "g"), ("gram", "g"), ("g", "g"),
            ("pounds", "lb"), ("pound", "lb"), ("lbs", "lb"), ("lb", "lb"),
            ("ounces", "oz"), ("ounce", "oz"), ("oz", "oz"),
            ("milliliters", "ml"), ("milliliter", "ml"), ("ml", "ml"),
            ("liters", "l"), ("liter", "l"), ("l", "l"),
            ("cups", "cup"), ("cup", "cup"),
            ("cloves", "clove"), ("clove", "clove"),
            ("slices", "slice"), ("slice", "slice"),
            ("eggs", "egg"), ("egg", "egg")
        ]
        for (text, unit) in aliases where rest == text || rest.hasPrefix(text + " ") { return (amount, unit) }
        return (nil, nil)
    }

    static func format(_ value: Double?, unit: String?) -> String {
        guard let value else { return "Amount needs review" }
        return "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(unit ?? "")"
    }
}

enum IngredientMatcher {
    static func normalize(_ text: String) -> String {
        text.lowercased().folding(options: [.diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
    static func match(name: String, linkedID: UUID?, ingredients: [Ingredient]) -> Ingredient? {
        if let linkedID, let linked = ingredients.first(where: { $0.id == linkedID }) { return linked }
        let normalized = normalize(name)
        let candidates = ingredients.filter {
            $0.normalizedName == normalized || $0.confirmedAliases.contains(normalized)
        }
        return candidates.count == 1 ? candidates.first : nil
    }
}

enum ReadinessStatus: String { case ready, likelyReady, missing, needsReview }
struct ReadinessResult {
    let status: ReadinessStatus
    let shortage: Double?
    let unit: String?
}
enum Readiness {
    static func check(line: RecipeIngredient, ingredients: [Ingredient], pantry: [PantryItem]) -> ReadinessResult {
        evaluate(lines: [line], ingredients: ingredients, pantry: pantry)[line.id]!
    }

    static func evaluate(lines: [RecipeIngredient], ingredients: [Ingredient], pantry: [PantryItem]) -> [UUID: ReadinessResult] {
        var remaining: [UUID: Double] = [:]
        var ambiguous: Set<UUID> = []
        var results: [UUID: ReadinessResult] = [:]
        for line in lines.sorted(by: { $0.position < $1.position }) {
            guard let ingredient = IngredientMatcher.match(name: line.name, linkedID: line.ingredientID, ingredients: ingredients),
                  let item = pantry.first(where: { $0.ingredientID == ingredient.id }) else {
                results[line.id] = ReadinessResult(status: .missing, shortage: line.amount, unit: line.unit)
                continue
            }
            if item.trackingMode == "available" {
                results[line.id] = ReadinessResult(status: .likelyReady, shortage: nil, unit: nil)
                continue
            }
            guard !ambiguous.contains(item.id), let amount = line.amount, let from = line.unit,
                  let available = item.quantity, let to = item.unit,
                  let required = Quantity.convert(amount, from: from, to: to, ingredient: ingredient) else {
                ambiguous.insert(item.id)
                results[line.id] = ReadinessResult(status: .needsReview, shortage: nil, unit: nil)
                continue
            }
            let balance = remaining[item.id] ?? available
            let shortage = max(0, required - balance)
            remaining[item.id] = max(0, balance - required)
            results[line.id] = shortage > 0.000001
                ? ReadinessResult(status: .missing, shortage: shortage, unit: to)
                : ReadinessResult(status: item.trackingMode == "exact" ? .ready : .likelyReady, shortage: nil, unit: nil)
        }
        return results
    }
}

struct UsageInput: Identifiable {
    let id: UUID
    var name: String
    var ingredientID: UUID?
    var amount: Double?
    var unit: String?
}

enum StoreError: LocalizedError {
    case alreadyActive, alreadyCompleted, invalidQuantity, incompatibleUnit, insufficientStock(String)
    var errorDescription: String? {
        switch self {
        case .alreadyActive: return "Finish or cancel the active cooking session first."
        case .alreadyCompleted: return "This action was already confirmed."
        case .invalidQuantity: return "Enter a quantity greater than zero."
        case .incompatibleUnit: return "These units cannot be converted safely."
        case .insufficientStock(let name): return "Not enough \(name) in the pantry. Correct the balance or reduce the usage."
        }
    }
}

enum KitchenStore {
    static func start(recipe: Recipe, lines: [RecipeIngredient], steps: [RecipeStep], sessions: [CookingSession], context: ModelContext) throws -> CookingSession {
        if sessions.contains(where: { $0.status == "active" }) { throw StoreError.alreadyActive }
        let snapshot = SessionSnapshot(
            ingredients: lines.sorted(by: { $0.position < $1.position }).map { SessionIngredient(id: $0.id, ingredientID: $0.ingredientID, name: $0.name, amount: $0.amount, unit: $0.unit, originalMeasure: $0.originalMeasure) },
            steps: steps.sorted(by: { $0.position < $1.position }).map { SessionStep(id: $0.id, text: $0.text, ingredientIDs: $0.ingredientIDs) },
            checkedIngredients: [], checkedSteps: []
        )
        let session = CookingSession(recipeID: recipe.id, recipeName: recipe.name, snapshot: snapshot)
        context.insert(session); try context.save(); return session
    }

    static func finish(session: CookingSession, inputs: [UsageInput], pantry: [PantryItem], ingredients: [Ingredient], context: ModelContext) throws {
        guard session.status == "active" else { throw StoreError.alreadyCompleted }
        let namesByID = Dictionary(uniqueKeysWithValues: ingredients.map { ($0.id, $0.name) })
        var deductions: [(PantryItem, Double, UsageInput)] = []
        for input in inputs {
            guard let amount = input.amount, amount > 0, let unit = input.unit else { continue }
            let linked = IngredientMatcher.match(name: input.name, linkedID: input.ingredientID, ingredients: ingredients)
            guard let linked, let item = pantry.first(where: { $0.ingredientID == linked.id }), item.trackingMode != "available" else { continue }
            guard let balanceUnit = item.unit, let converted = Quantity.convert(amount, from: unit, to: balanceUnit, ingredient: linked) else { throw StoreError.incompatibleUnit }
            guard let balance = item.quantity, balance + 0.000001 >= converted else { throw StoreError.insufficientStock(namesByID[item.ingredientID] ?? input.name) }
            deductions.append((item, converted, input))
        }
        // Aggregate before writing so two uses of one ingredient cannot overdraw it.
        for item in pantry {
            let total = deductions.filter { $0.0.id == item.id }.reduce(0) { $0 + $1.1 }
            if total > (item.quantity ?? 0) + 0.000001 { throw StoreError.insufficientStock(namesByID[item.ingredientID] ?? "ingredient") }
        }
        do {
            for input in inputs {
                let linked = IngredientMatcher.match(name: input.name, linkedID: input.ingredientID, ingredients: ingredients)
                let deduction = deductions.first { $0.2.id == input.id }
                var transactionID: UUID?
                if let (item, converted, _) = deduction {
                    item.quantity = max(0, (item.quantity ?? 0) - converted)
                    let tx = InventoryTransaction(pantryItemID: item.id, ingredientID: item.ingredientID, kind: "cook", signedQuantity: -converted, unit: item.unit ?? "", note: session.recipeName, sessionID: session.id)
                    context.insert(tx); transactionID = tx.id
                }
                context.insert(IngredientUsage(sessionID: session.id, ingredientID: linked?.id, name: input.name, amount: input.amount, unit: input.unit, transactionID: transactionID))
            }
            session.status = "completed"; session.completedAt = .now
            try context.save()
        } catch { context.rollback(); throw error }
    }

    static func purchase(name: String, ingredientID: UUID?, amount: Double, unit: String, shoppingItem: ShoppingItem?,
                         ingredients: [Ingredient], pantry: [PantryItem], context: ModelContext) throws {
        guard amount > 0 else { throw StoreError.invalidQuantity }
        guard let canonical = Quantity.canonical(amount, unit) else { throw StoreError.incompatibleUnit }
        if shoppingItem?.purchased == true { throw StoreError.alreadyCompleted }
        let linked = IngredientMatcher.match(name: name, linkedID: ingredientID, ingredients: ingredients)
        let ingredient = linked ?? Ingredient(name: name)
        if linked == nil { context.insert(ingredient) }
        let existing = pantry.first { $0.ingredientID == ingredient.id }
        let item: PantryItem
        let quantity: Double
        if let existing {
            item = existing
            if let itemUnit = item.unit {
                guard let converted = Quantity.convert(amount, from: unit, to: itemUnit, ingredient: ingredient) else { throw StoreError.incompatibleUnit }
                quantity = converted
            } else if item.trackingMode == "available" {
                item.unit = canonical.1
                item.displayUnit = unit
                quantity = canonical.0
            } else { throw StoreError.incompatibleUnit }
            item.quantity = (item.quantity ?? 0) + quantity
            item.startingQuantity = max(item.startingQuantity ?? 0, item.quantity ?? 0)
            if item.trackingMode == "available" { item.trackingMode = "exact" }
        } else {
            quantity = canonical.0
            item = PantryItem(ingredientID: ingredient.id, trackingMode: "exact", quantity: quantity, unit: canonical.1, displayUnit: unit)
            context.insert(item)
        }
        let tx = InventoryTransaction(pantryItemID: item.id, ingredientID: ingredient.id, kind: "purchase", signedQuantity: quantity, unit: item.unit ?? canonical.1, note: shoppingItem == nil ? "Pantry purchase" : "Shopping list", shoppingItemID: shoppingItem?.id)
        context.insert(tx); shoppingItem?.purchased = true
        if let shoppingItem {
            for contribution in ((try? context.fetch(FetchDescriptor<ShoppingContribution>())) ?? []) where contribution.shoppingItemID == shoppingItem.id {
                context.delete(contribution)
            }
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }

    static func addShopping(recipe: Recipe, lines: [RecipeIngredient], ingredients: [Ingredient], pantry: [PantryItem],
                            items: [ShoppingItem], contributions: [ShoppingContribution], context: ModelContext) throws {
        var currentItems = items.filter { !$0.purchased }
        let readiness = Readiness.evaluate(lines: lines, ingredients: ingredients, pantry: pantry)
        for line in lines {
            guard let result = readiness[line.id] else { continue }
            guard result.status == .missing else { continue }
            let key = "recipe:\(recipe.id.uuidString):\(line.id.uuidString)"
            if contributions.contains(where: { $0.sourceKey == key }) { continue }
            let linked = IngredientMatcher.match(name: line.name, linkedID: line.ingredientID, ingredients: ingredients)
            let amount = result.shortage
            let unit = result.unit
            let existing = currentItems.first { IngredientMatcher.normalize($0.name) == IngredientMatcher.normalize(line.name) && $0.unit == unit && $0.amount != nil && amount != nil }
            let item = existing ?? ShoppingItem(name: line.name, ingredientID: linked?.id, amount: nil, unit: unit, note: amount == nil ? (line.originalMeasure.isEmpty ? "Review amount" : line.originalMeasure) : "", sourceKind: "recipe", sourceID: recipe.id)
            if existing == nil { context.insert(item); currentItems.append(item) }
            if let amount { item.amount = (item.amount ?? 0) + amount }
            context.insert(ShoppingContribution(sourceKey: key, shoppingItemID: item.id, amount: amount, unit: unit))
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }

    static func discard(item: PantryItem, amount: Double, unit: String, ingredient: Ingredient?, context: ModelContext) throws {
        guard amount > 0 else { throw StoreError.invalidQuantity }
        guard let balanceUnit = item.unit,
              let converted = Quantity.convert(amount, from: unit, to: balanceUnit, ingredient: ingredient) else { throw StoreError.incompatibleUnit }
        guard let balance = item.quantity, balance + 0.000001 >= converted else {
            throw StoreError.insufficientStock(ingredient?.name ?? "ingredient")
        }
        item.quantity = max(0, balance - converted)
        item.lastConfirmedAt = .now
        context.insert(InventoryTransaction(pantryItemID: item.id, ingredientID: item.ingredientID,
                                            kind: "discard", signedQuantity: -converted, unit: balanceUnit,
                                            note: "Discarded"))
        do { try context.save() } catch { context.rollback(); throw error }
    }
}

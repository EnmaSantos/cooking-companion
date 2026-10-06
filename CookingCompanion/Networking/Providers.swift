import Foundation
import SwiftData

enum NetworkIssue: LocalizedError {
    case invalidURL, offline, badResponse(Int), badData
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Check the Mac server address in Settings."
        case .offline: return "The service is unavailable. Your saved data still works offline."
        case .badResponse(let code): return code == 429 ? "The service is busy. Please retry shortly." : "The service returned an error (\(code))."
        case .badData: return "The service returned data this version cannot read."
        }
    }
}

private func load(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.timeoutInterval = 15
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkIssue.offline }
        guard (200..<300).contains(http.statusCode) else { throw NetworkIssue.badResponse(http.statusCode) }
        return data
    } catch let issue as NetworkIssue { throw issue }
    catch { throw NetworkIssue.offline }
}

struct MealEnvelope: Decodable { let meals: [MealDTO]? }
struct MealDTO: Decodable, Identifiable {
    let idMeal: String
    let strMeal: String
    let strMealThumb: String?
    let strCategory: String?
    let strInstructions: String?
    let strSource: String?
    let ingredients: [String]
    let measures: [String]
    var id: String { idMeal }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: DynamicKey.self)
        func value(_ key: String) -> String? {
            guard let k = DynamicKey(stringValue: key) else { return nil }
            return try? fields.decodeIfPresent(String.self, forKey: k)
        }
        guard let id = value("idMeal"), let title = value("strMeal") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Meal ID or title is missing"))
        }
        idMeal = id; strMeal = title; strMealThumb = value("strMealThumb")
        strCategory = value("strCategory"); strInstructions = value("strInstructions")
        strSource = value("strSource")
        ingredients = (1...20).map { value("strIngredient\($0)") ?? "" }
        measures = (1...20).map { value("strMeasure\($0)") ?? "" }
    }
    private struct DynamicKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

struct CategoryEnvelope: Decodable { let categories: [MealCategory] }
struct MealCategory: Decodable, Identifiable {
    let idCategory: String
    let strCategory: String
    var id: String { idCategory }
}

protocol RecipeDiscoveryService {
    func search(_ query: String) async throws -> [MealDTO]
    func categories() async throws -> [MealCategory]
    func filter(category: String?, ingredient: String?) async throws -> [MealDTO]
    func details(id: String) async throws -> MealDTO
}

struct TheMealDBService: RecipeDiscoveryService {
    private let root = "https://www.themealdb.com/api/json/v1/1/"
    private func get(_ endpoint: String, query: [URLQueryItem]) async throws -> Data {
        guard var parts = URLComponents(string: root + endpoint) else { throw NetworkIssue.invalidURL }
        parts.queryItems = query
        guard let url = parts.url else { throw NetworkIssue.invalidURL }
        return try await load(url)
    }
    func search(_ query: String) async throws -> [MealDTO] {
        let data = try await get("search.php", query: [.init(name: "s", value: query)])
        return try JSONDecoder().decode(MealEnvelope.self, from: data).meals ?? []
    }
    func categories() async throws -> [MealCategory] {
        try JSONDecoder().decode(CategoryEnvelope.self, from: await get("categories.php", query: [])).categories
    }
    func filter(category: String? = nil, ingredient: String? = nil) async throws -> [MealDTO] {
        let parameter = category.map { URLQueryItem(name: "c", value: $0) } ?? URLQueryItem(name: "i", value: ingredient)
        let data = try await get("filter.php", query: [parameter])
        return try JSONDecoder().decode(MealEnvelope.self, from: data).meals ?? []
    }
    func details(id: String) async throws -> MealDTO {
        let data = try await get("lookup.php", query: [.init(name: "i", value: id)])
        guard let meal = try JSONDecoder().decode(MealEnvelope.self, from: data).meals?.first else { throw NetworkIssue.badData }
        return meal
    }
}

enum RecipeMapper {
    @MainActor static func save(_ dto: MealDTO, existing: [Recipe], context: ModelContext) throws -> Recipe {
        if let saved = existing.first(where: { $0.source == "TheMealDB" && $0.sourceID == dto.idMeal }) { return saved }
        let recipe = Recipe(name: dto.strMeal, source: "TheMealDB", sourceID: dto.idMeal,
                            sourceURL: dto.strSource ?? "https://www.themealdb.com/meal/\(dto.idMeal)",
                            imageURL: dto.strMealThumb, originalInstructions: dto.strInstructions ?? "")
        context.insert(recipe)
        for index in 0..<20 {
            let name = dto.ingredients[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let measure = dto.measures[index].trimmingCharacters(in: .whitespacesAndNewlines)
            let parsed = Quantity.parse(measure)
            context.insert(RecipeIngredient(recipeID: recipe.id, name: name, amount: parsed.0,
                                            unit: parsed.1, originalMeasure: measure, position: index))
        }
        let instructionText = dto.strInstructions ?? ""
        var paragraphs = instructionText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if paragraphs.isEmpty && !instructionText.isEmpty { paragraphs = [instructionText] }
        for (index, text) in paragraphs.enumerated() {
            context.insert(RecipeStep(recipeID: recipe.id, position: index, text: text))
        }
        try context.save()
        return recipe
    }
    @MainActor static func cacheImage(for recipe: Recipe) async {
        guard recipe.imageData == nil, let address = recipe.imageURL, let url = URL(string: address) else { return }
        guard let data = try? await load(url), data.count < 5_000_000 else { return }
        recipe.imageData = data
    }
}

struct USDASearchEnvelope: Decodable {
    let foods: [USDAFoodDTO]?
}
struct USDAFoodDTO: Decodable, Identifiable {
    let fdcId: Int
    let description: String
    let dataType: String?
    let servingSizeUnit: String?
    let foodNutrients: [USDANutrientDTO]?
    var id: Int { fdcId }
}
struct USDANutrientDTO: Decodable {
    let nutrientId: Int?
    let nutrientName: String?
    let value: Double?
    let unitName: String?
    let nutrient: USDANestedNutrient?
    let amount: Double?
}
struct USDANestedNutrient: Decodable {
    let id: Int?
    let name: String?
    let unitName: String?
}

protocol FoodCatalogService {
    func search(_ query: String, page: Int, baseURL: String) async throws -> [USDAFoodDTO]
    func details(id: Int, baseURL: String) async throws -> USDAFoodDTO
}
struct USDAProxyService: FoodCatalogService {
    private func endpoint(_ base: String, _ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard let root = URL(string: base), root.scheme == "http" || root.scheme == "https",
              let host = root.host, !host.isEmpty,
              var parts = URLComponents(url: root.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw NetworkIssue.invalidURL }
        parts.queryItems = query
        guard let url = parts.url else { throw NetworkIssue.invalidURL }
        return url
    }
    func search(_ query: String, page: Int, baseURL: String) async throws -> [USDAFoodDTO] {
        let url = try endpoint(baseURL, "foods/search", query: [.init(name: "q", value: query), .init(name: "page", value: String(page))])
        let data = try await load(url)
        return try JSONDecoder().decode(USDASearchEnvelope.self, from: data).foods ?? []
    }
    func details(id: Int, baseURL: String) async throws -> USDAFoodDTO {
        let data = try await load(endpoint(baseURL, "foods/\(id)"))
        return try JSONDecoder().decode(USDAFoodDTO.self, from: data)
    }
}

enum FoodMapper {
    static func confirm(_ food: USDAFoodDTO, for ingredient: Ingredient) {
        ingredient.fdcID = food.fdcId
        ingredient.fdcDescription = food.description
        ingredient.fdcDataType = food.dataType
        ingredient.nutrients = (food.foodNutrients ?? []).compactMap { nutrient in
            guard let id = nutrient.nutrientId ?? nutrient.nutrient?.id,
                  let name = nutrient.nutrientName ?? nutrient.nutrient?.name,
                  let amount = nutrient.value ?? nutrient.amount,
                  let unit = nutrient.unitName ?? nutrient.nutrient?.unitName else { return nil }
            let basis = food.dataType == "Branded" && food.servingSizeUnit?.uppercased() == "ML" ? "per 100 mL" : "per 100 g"
            return NutrientValue(id: id, name: name, amount: amount, unit: unit, basis: basis)
        }
    }
}

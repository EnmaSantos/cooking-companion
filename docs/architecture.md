# Architecture

```text
TheMealDB JSON → MealDTO → RecipeMapper → SwiftData Recipe
USDA JSON → FastAPI proxy → USDAFoodDTO → FoodMapper → Ingredient metadata
Recipe + pantry → Readiness → Shopping
Recipe → CookingSession snapshot → Usage review → InventoryTransaction → Pantry
```

The app owns recipe, ingredient, pantry, shopping, and cooking IDs. Provider IDs are optional references. Imported recipes are editable local copies with TheMealDB attribution and source links. A second save opens the same local record and does not replace user edits. TheMealDB's numbered ingredient fields and free-form measures are normalized on save; raw measures and instructions remain available for review.

All balances use grams, milliliters, or counts. Pounds, ounces, cups, and spoons convert within their dimension. Cross-dimension comparisons require an explicit grams-per-milliliter or grams-per-count value entered for that ingredient; otherwise the app marks them **Needs review**. Exact stock can be **Ready**; estimated or availability-only stock is **Likely**. Unknown quantities never become zeros.

The cooking session captures ingredients, steps, and manually linked step ingredients when it starts. Checklist changes save to the session but never deduct inventory. Confirmation writes usage records, signed transactions, and completion in one SwiftData save. Insufficient balance blocks the operation for correction, and completed sessions cannot post twice. Pantry balances are stored for fast display; the transaction history explains each purchase, consumption, correction, and discard.

Shopping generation tracks each recipe line or low-stock suggestion by a source key. Repeated generation is idempotent, compatible known amounts merge, and unknown amounts remain visible for review. Recording a purchase clears its source contributions so future shortages can generate new items.

The FastAPI server accepts only food search and details, adds the USDA key server-side, limits query size, times out, maps upstream failures to safe error messages, and caches at most 128 successful results for one hour. The iPhone can operate without the server except for new USDA searches. The app's local address is configured in Settings for Simulator or phone use.

## Portfolio demonstration

Start with a 5 lb flour pantry balance. Save or create a bread recipe using 500 g flour. The pantry check converts 5 lb to about 2268 g. Mark flour during cooking, review the 500 g proposal, and confirm. The inventory history shows a -500 g cooking transaction and about 1768 g remaining. This demonstrates the app's own state and unit logic independently of the recipe and food APIs.

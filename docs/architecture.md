# Architecture

```text
TheMealDB JSON → hosted FastAPI → MealDTO → RecipeMapper → SwiftData Recipe
USDA JSON → hosted FastAPI → USDAFoodDTO → FoodMapper → Ingredient metadata
Recipe + pantry → Readiness → Shopping
Recipe → CookingSession snapshot → Usage review → InventoryTransaction → Pantry
```

The app owns recipe, ingredient, pantry, shopping, and cooking IDs. Provider IDs are optional references. Imported recipes are editable local copies with TheMealDB attribution and source links. A second save opens the same local record and does not replace user edits. TheMealDB's numbered ingredient fields and free-form measures are normalized on save; raw measures and instructions remain available for review.

All balances use grams, milliliters, or counts. Pounds, ounces, cups, and spoons convert within their dimension. Cross-dimension comparisons require an explicit grams-per-milliliter or grams-per-count value entered for that ingredient; otherwise the app marks them **Needs review**. Exact stock can be **Ready**; estimated or availability-only stock is **Likely**. Unknown quantities never become zeros.

The cooking session captures ingredients, steps, and manually linked step ingredients when it starts. Checklist changes save to the session but never deduct inventory. Confirmation writes usage records, signed transactions, and completion in one SwiftData save. Insufficient balance blocks the operation for correction, and completed sessions cannot post twice. Pantry balances are stored for fast display; the transaction history explains each purchase, consumption, correction, and discard.

Shopping generation tracks each recipe line or low-stock suggestion by a source key. Repeated generation is idempotent, compatible known amounts merge, and unknown amounts remain visible for review. Recording a purchase clears its source contributions so future shortages can generate new items.

The FastAPI service accepts only bounded recipe discovery and food catalog requests. It loads the two provider keys from ignored `.env` values locally or hosting environment secrets in production, adds them server-side, times out, maps upstream failures to safe error messages, and caches at most 128 successful results for one hour in each process. Successful catalog responses also carry a one-hour CDN cache directive. The app's service URL is configured in Settings; provider keys are absent from the app and repository. New catalog requests need the service, while saved recipes, pantry, shopping, and cooking remain local and usable offline. A hosted public instance needs host-level rate limiting before broad use because an in-process cache is not a cross-instance abuse control.

## Portfolio demonstration

Start with a 5 lb flour pantry balance. Save or create a bread recipe using 500 g flour. The pantry check converts 5 lb to about 2268 g. Mark flour during cooking, review the 500 g proposal, and confirm. The inventory history shows a -500 g cooking transaction and about 1768 g remaining. This demonstrates the app's own state and unit logic independently of the recipe and food APIs.

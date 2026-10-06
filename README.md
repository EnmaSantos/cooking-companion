# Cooking Companion

Cooking Companion is a native iPhone app for the full kitchen loop: find a recipe, check what is on hand, shop for what is missing, cook, confirm what was used, and see the updated pantry. It uses **TheMealDB** for recipe discovery and **USDA FoodData Central** for optional food and nutrition details. Recipes, quantities, shopping items, and cooking history belong to the app and persist locally with SwiftData.

| My Recipes | Guided cooking | Pantry and history |
| --- | --- | --- |
| <img src="docs/screenshots/recipes.png" width="250" alt="Saved recipes with pantry readiness" /> | <img src="docs/screenshots/cooking.png" width="250" alt="Cooking steps and ingredient checklist" /> | <img src="docs/screenshots/pantry.png" width="250" alt="Pantry balances and inventory transactions" /> |

| Recipe check | Usage confirmation | Shopping |
| --- | --- | --- |
| <img src="docs/screenshots/recipe-detail.png" width="250" alt="Recipe ingredients and pantry check" /> | <img src="docs/screenshots/usage-review.png" width="250" alt="Editable usage review before stock changes" /> | <img src="docs/screenshots/shopping-detail.png" width="250" alt="Confirm a shopping purchase and search retailers" /> |

These are captures from the iPhone 18 Pro simulator using the included sample kitchen. The [Figma product and UX file](https://www.figma.com/design/2VrGZrTryO0BAjVjlaXqpQ) contains the flows, wireframes, components, light/dark exploration, and interactive prototype.

## What the app does

- **Find and own recipes.** Search TheMealDB by name, browse categories, or filter by one ingredient. Saving turns a remote result into a complete editable local recipe with its original measures, instructions, image, source link, and provider ID. Create recipes manually and mark favorites, too.
- **Check the pantry honestly.** Track an exact quantity, an estimate, or simply whether an item is available. Recipe ingredients show **Ready**, **Likely**, **Missing**, or **Needs Review**. Grams, milliliters, and counts are kept separate; cross-dimension conversions require a value you explicitly enter for that ingredient.
- **Cook without losing your place.** A cooking session snapshots the recipe and saves step and ingredient checklist progress. Checking an ingredient proposes usage; it does not reduce stock. Review and edit quantities before finishing. Confirmation records the consumption and inventory history once, and an unfinished session can be resumed.
- **Shop and replenish.** Add known recipe shortages, low-stock suggestions, or manual items. Compatible shortages merge without multiplying when generated again. Confirm the purchased quantity to add it to the pantry, or open Google and Walmart searches from the item detail.
- **Optionally enrich ingredients.** Search USDA foods, confirm a match, and cache the food ID and nutrient values with their units and measurement basis. Food matching is separate from the app's own ingredient identity.

Saved recipes, pantry, shopping, and cooking continue to work when the internet or Mac service is unavailable. New TheMealDB discovery needs internet access; new USDA searches need the Mac service.

## Where the API keys go

The two keys have different homes. **Do not put either key in `project.yml`, Swift source, screenshots, or GitHub.**

| Provider | Where to put your key | Used for |
| --- | --- | --- |
| TheMealDB | In the app: **Settings → TheMealDB V2 API key → Save TheMealDB key**. Paste the key alone, not the full URL. | Recipe discovery on this iPhone. The key is stored in this device's Keychain. The app changes its requests from `/api/json/v1/1/…` to `/api/json/v2/<your-key>/…`. |
| USDA FoodData Central | In a local `.env` file at the repository root as `FOODDATA_API_KEY=...`. | The Mac FastAPI service adds the key when calling USDA. The iPhone receives food data, never the USDA key. |

TheMealDB's [API instructions](https://www.themealdb.com/api.php) show the V2 URL format and endpoint names. Without a saved TheMealDB key, the app uses the V1 development key for this personal build. USDA's [API guide](https://fdc.nal.usda.gov/api-guide/) explains why its key should stay private.

<img src="docs/screenshots/settings.png" width="250" alt="Settings screen with a TheMealDB key field and Mac server address" />

To set up USDA on your Mac, open Terminal in this repository's folder and run **one command at a time**. First create the Python environment:

```sh
python3 -m venv .venv
```

Then install the backend packages into it:

```sh
.venv/bin/python -m pip install -r backend/requirements.txt
```

Copy the key template:

```sh
cp .env.example .env
```

Open `.env` in an editor and replace `replace_with_your_usda_key` with your USDA key. The line in that **file** should read `FOODDATA_API_KEY=your_actual_key`. This is file content, not a Terminal command or an argument to `venv`. Start the server with:

```sh
.venv/bin/uvicorn main:app --app-dir backend --host 0.0.0.0 --port 8000
```

`.env` is ignored by Git. The server loads it when it starts, so restart the server after changing the USDA key. In the iPhone Simulator, leave **Settings → Mac server URL** at `http://127.0.0.1:8000`. On a physical iPhone, enter your Mac's local Wi-Fi address, such as `http://192.168.1.20:8000`, and keep the phone and Mac on the same network. The local HTTP allowance is in the Debug configuration for personal device testing.

## Run the app

1. Open `CookingCompanion.xcodeproj` in Xcode and select the `CookingCompanion` scheme. The app targets iOS 17 or newer.
2. Run on an iPhone Simulator. In **Settings**, tap **Load sample kitchen** to add a pancake recipe, flour, eggs, and milk once.
3. Open **Recipes → Buttermilk Pancakes** to see the pantry check. Start cooking, check flour, review the proposed amount, and confirm. **Pantry** will show the new balance and a signed transaction.
4. To run on your iPhone, connect and unlock it, trust the Mac if prompted, select the device in Xcode, use your Apple Development team in **Signing & Capabilities**, and run. Free Personal Team provisioning may require a new build after seven days.

The generated Xcode project is committed. `project.yml` is its [XcodeGen](https://github.com/yonaskolb/XcodeGen) source if the project structure changes.

## Architecture and tests

TheMealDB responses map into local `Recipe` records. USDA responses pass through the small FastAPI service and enrich local `Ingredient` records after confirmation. SwiftData owns inventory transactions, shopping, and resumable cooking sessions. See the [architecture](docs/architecture.md) and [UX decisions](docs/design.md) for the data model and interaction choices.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CookingCompanion.xcodeproj -scheme CookingCompanion -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test
.venv/bin/python -m unittest discover -s backend -p 'test_*.py' -v
```

GitHub Actions runs the backend tests and Debug/Release iOS simulator builds on pushes to `main`.

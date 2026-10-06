# Cooking Companion

A SwiftUI cooking app that connects saved recipes, pantry awareness, cooking checklists, inventory history, and shopping. TheMealDB supplies recipe discovery; USDA FoodData Central optionally enriches pantry ingredients. Your recipes and kitchen data stay on the iPhone in SwiftData.

The [Figma product and UX file](https://www.figma.com/design/2VrGZrTryO0BAjVjlaXqpQ) includes the scenario, flows, wireframes, component library, linked prototype, and design decisions.

## Run the iPhone app

1. Open `CookingCompanion.xcodeproj` in Xcode 27 or newer. The project targets iOS 17 or newer.
2. Choose the `CookingCompanion` scheme and an iPhone Simulator. Build and run. In Settings, tap **Load sample kitchen** to try the complete local flow.
3. To install on your own iPhone, connect it, select it as the run destination, choose your Apple Personal Team in **Signing & Capabilities**, and run. Xcode may ask you to trust the developer certificate on the device. A free Personal Team may require reinstalling after seven days.

The repository includes the generated Xcode project and `project.yml`. If you change project structure, regenerate with [XcodeGen](https://github.com/yonaskolb/XcodeGen): `xcodegen generate`.

## Run USDA food search

The USDA key stays in a small local FastAPI server. Obtain a key from [FoodData Central](https://fdc.nal.usda.gov/api-key-signup/), then run:

```sh
python3 -m venv .venv
.venv/bin/pip install -r backend/requirements.txt
FOODDATA_API_KEY=your_key .venv/bin/uvicorn main:app --app-dir backend --host 0.0.0.0 --port 8000
```

In Simulator, the Settings URL is `http://127.0.0.1:8000`. On your phone, replace it with your Mac's local IP, for example `http://192.168.1.20:8000`, and keep both devices on the same trusted Wi-Fi network. No backend is needed to create recipes, use the pantry, cook, or shop. TheMealDB discovery needs internet access.

## Try the core loop

Load the sample kitchen, open **Buttermilk Pancakes**, and inspect the pantry check. Start cooking, mark ingredients and steps, then review and confirm usage. The pantry balance and history update. A second confirmation cannot deduct again. Change a pantry balance to simulate a purchase or correction. Use **Discover** to search TheMealDB and save a local editable recipe; use **Find a USDA food** from any pantry item to confirm a food match and inspect cached nutrients.

## Tests

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CookingCompanion.xcodeproj -scheme CookingCompanion -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test
.venv/bin/python -m unittest discover -s backend -p 'test_*.py' -v
```

See [architecture](docs/architecture.md) and [UX decisions](docs/design.md) for the data flow and design rationale.

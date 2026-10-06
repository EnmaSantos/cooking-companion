import XCTest

final class CookingCompanionUITests: XCTestCase {
    func testPortfolioScreenshots() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Settings"].tap()
        app.buttons["Load sample kitchen"].tap()
        capture("settings", app)

        app.tabBars.buttons["Recipes"].tap()
        XCTAssertTrue(app.staticTexts["Buttermilk Pancakes"].firstMatch.waitForExistence(timeout: 5))
        capture("recipes", app)

        app.staticTexts["Buttermilk Pancakes"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Start Cooking"].waitForExistence(timeout: 5))
        capture("recipe-detail", app)

        app.buttons["Start Cooking"].tap()
        XCTAssertTrue(app.buttons["Finish and review usage"].waitForExistence(timeout: 5))
        capture("cooking", app)

        app.buttons["Bread flour"].firstMatch.tap()
        app.buttons["Finish and review usage"].tap()
        XCTAssertTrue(app.buttons["Confirm and finish"].waitForExistence(timeout: 5))
        capture("usage-review", app)
        app.buttons["Confirm and finish"].tap()

        app.tabBars.buttons["Pantry"].tap()
        capture("pantry", app)

        app.tabBars.buttons["Shopping"].tap()
        if !app.staticTexts["Heavy cream"].firstMatch.exists {
            let entry = app.textFields["Ingredient"]
            entry.tap()
            entry.typeText("Heavy cream")
            app.buttons["Add"].tap()
        }
        app.staticTexts["Heavy cream"].firstMatch.tap()
        capture("shopping-detail", app)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        Thread.sleep(forTimeInterval: 0.8) // Let navigation and sheets settle before taking a portfolio image.
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSampleKitchenCookingLoop() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Load sample kitchen"].tap()
        app.tabBars.buttons["Recipes"].tap()
        let recipe = app.staticTexts["Buttermilk Pancakes"].firstMatch
        XCTAssertTrue(recipe.waitForExistence(timeout: 5))
        recipe.tap()
        let start = app.buttons["Start Cooking"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let flour = app.buttons["Bread flour"].firstMatch
        XCTAssertTrue(flour.waitForExistence(timeout: 5))
        flour.tap()
        app.buttons["Finish and review usage"].tap()
        let confirm = app.buttons["Confirm and finish"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        app.tabBars.buttons["Pantry"].tap()
        app.staticTexts["Bread flour"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Buttermilk Pancakes"].firstMatch.waitForExistence(timeout: 5))
    }
}

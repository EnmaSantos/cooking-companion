import XCTest

final class CookingCompanionUITests: XCTestCase {
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

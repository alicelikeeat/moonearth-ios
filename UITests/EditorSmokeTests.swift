import XCTest

final class EditorSmokeTests: XCTestCase {
    @MainActor
    func testTemplatePreviewApplyAndSave() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let create = app.buttons["new-world"]
        XCTAssertTrue(create.waitForExistence(timeout:15)); create.tap()
        let confirm = app.buttons["confirm-create"]
        XCTAssertTrue(confirm.waitForExistence(timeout:5)); confirm.tap()
        let assistant = app.buttons["design-assistant"]
        XCTAssertTrue(assistant.waitForExistence(timeout:20)); assistant.tap()
        let template = app.buttons["preview-template"]
        for _ in 0..<4 where !template.isHittable { app.swipeUp() }
        XCTAssertTrue(template.waitForExistence(timeout:5))
        template.tap()
        let apply = app.buttons["apply-preview"]
        XCTAssertTrue(apply.waitForExistence(timeout:15))
        let attachment = XCTAttachment(screenshot:app.screenshot()); attachment.name = "editable-template-preview"; attachment.lifetime = .keepAlways; add(attachment)
        apply.tap()
        XCTAssertFalse(apply.exists)
        let back = app.buttons["save-back"]
        XCTAssertTrue(back.waitForExistence(timeout:5)); back.tap()
        XCTAssertTrue(create.waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "1 栋建筑")).firstMatch.waitForExistence(timeout:10))
    }
}

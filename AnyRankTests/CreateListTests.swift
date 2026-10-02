import XCTest
@testable import AnyRank

/// The field names a Custom list is created with, from the rows as typed
/// on the create-list form.
final class CreateListTests: XCTestCase {

    func test_fieldNames_keepEveryTypedRow_withoutAnAddStep() {
        let drafts = [FieldDraft(name: "Region"), FieldDraft(name: "Vintage"), FieldDraft()]
        XCTAssertEqual(FieldDraft.fieldNames(from: drafts), ["Region", "Vintage"])
    }

    func test_fieldNames_trimDropBlanksAndCollapseDuplicates() {
        let drafts = [
            FieldDraft(name: "  Grape "),
            FieldDraft(name: "   "),
            FieldDraft(name: "Region"),
            FieldDraft(name: "grape"),
            FieldDraft(name: "Vintage"),
        ]
        XCTAssertEqual(FieldDraft.fieldNames(from: drafts), ["Grape", "Region", "Vintage"])
    }

    func test_fieldNames_emptyForm_hasNoFields() {
        XCTAssertEqual(FieldDraft.fieldNames(from: [FieldDraft()]), [])
    }
}

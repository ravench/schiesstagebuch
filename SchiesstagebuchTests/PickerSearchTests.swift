import XCTest
@testable import Schiesstagebuch

/// Fields that pick from more than ten choices open them under a search field (`SearchablePicker`).
final class PickerSearchTests: XCTestCase {
    private let choices = [
        PickerChoice(value: 1, title: "Sturmgewehr 90", subtitle: "A-123456"),
        PickerChoice(value: 2, title: "Karabiner 31", section: "Alt"),
        PickerChoice(value: 3, title: "Vetterli 1869", section: "Alt", searchOnly: true),
        PickerChoice(value: 4, title: "Zürcher Pistole"),
    ]

    private func found(_ query: String) -> [Int] { PickerSearch.results(choices, matching: query).map(\.value) }

    func testNoSearchListsAllButTheSearchOnlyChoices() {
        XCTAssertEqual(found(""), [1, 2, 4])
        XCTAssertEqual(found("  "), [1, 2, 4])
    }

    func testEveryWordMustBeInTitleOrSubtitle() {
        XCTAssertEqual(found("sturm"), [1])
        XCTAssertEqual(found("123"), [1], "the subtitle counts")
        XCTAssertEqual(found("90 sturm"), [1], "words in any order")
        XCTAssertEqual(found("sturm 31"), [])
    }

    func testCaseAndAccentsDoNotMatter() {
        XCTAssertEqual(found("zurcher"), [4])
        XCTAssertEqual(found("KARABINER"), [2])
    }

    func testSearchFindsTheSearchOnlyChoices() {
        XCTAssertEqual(found("vett"), [3])
    }

    func testAChoiceCanBringItsOwnComparison() {
        let para = PickerChoice(value: "9x19", title: "9x19 mm", matches: { $0 == "para" })
        XCTAssertEqual(PickerSearch.results([para], matching: "para").count, 1)
        XCTAssertEqual(PickerSearch.results([para], matching: "9x19").count, 0)
        XCTAssertEqual(PickerSearch.results([para], matching: "").count, 1)
    }

    /// The catalogue's calibres are found by their other names, the rare ones only by searching.
    func testCalibresAreFoundByTheirOtherNames() throws {
        let para = CaliberChoice(item: try XCTUnwrap(CaliberCatalog.item(id: "9x19 mm")))
        let choice = PickerChoice(value: para.name, title: para.name, matches: para.matches)
        XCTAssertEqual(PickerSearch.results([choice], matching: "parabellum").count, 1)
        XCTAssertEqual(PickerSearch.results([choice], matching: "vetterli").count, 0)
    }

    func testNeighboursWithTheSameSectionAreOneGroup() {
        let groups = PickerSearch.grouped(choices)
        XCTAssertEqual(groups.map(\.title), [nil, "Alt", nil])
        XCTAssertEqual(groups.map { $0.choices.map(\.value) }, [[1], [2, 3], [4]])
    }

    func testOptionalChoicesStartWithNoneAndKeepTheCurrentValue() {
        let all = PickerChoice.optional(["a", "b"], keeping: "z", title: { $0.uppercased() })
        XCTAssertEqual(all.map(\.value), [nil, "a", "b", "z"])
        XCTAssertEqual(all.map(\.title), ["–", "A", "B", "Z"])
        XCTAssertEqual(PickerChoice.optional(["a", "b"], keeping: "a", none: nil, title: { $0 }).map(\.value), ["a", "b"])
    }

    func testElevenChoicesAreTheFirstWithASearchField() {
        XCTAssertEqual(PickerSearch.limit, 10)
    }
}

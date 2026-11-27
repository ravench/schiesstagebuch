import XCTest
import SwiftData
@testable import Schiesstagebuch

/// Every other test opens the store without CloudKit, and the app falls back to a local store when the
/// CloudKit one cannot be opened: a model change CloudKit rejects would ship with sync switched off and
/// nothing would say so (review 2026-11-27). These are CloudKit's rules for a SwiftData model.
final class CloudKitSchemaTests: XCTestCase {
    func testSchemaFollowsCloudKitRules() {
        let entities = SchiesstagebuchApp.schema.entities
        XCTAssertEqual(entities.count, 12)
        for entity in entities {
            XCTAssertTrue(entity.uniquenessConstraints.isEmpty, "\(entity.name): no unique constraints")
            for attribute in entity.attributes {
                XCTAssertFalse(attribute.isUnique, "\(entity.name).\(attribute.name): no unique attributes")
                XCTAssertTrue(attribute.isOptional || attribute.defaultValue != nil,
                              "\(entity.name).\(attribute.name): optional or with a default value")
            }
            for relationship in entity.relationships {
                XCTAssertTrue(relationship.isOptional, "\(entity.name).\(relationship.name): relationships are optional")
                XCTAssertNotNil(relationship.inverseName, "\(entity.name).\(relationship.name): relationships have an inverse")
            }
        }
    }
}

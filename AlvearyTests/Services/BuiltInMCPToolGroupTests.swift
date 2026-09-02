import XCTest

@testable import Alveary

@MainActor
final class BuiltInMCPToolGroupTests: XCTestCase {
    /// The listing walks the feature catalogs to keep the grouping, while the server
    /// advertises the flattened `tools`; the two must name the same tools in the same order.
    func testTheGroupsMirrorTheAdvertisedCatalogInOrder() {
        let groups = BuiltInMCPToolGroup.all

        XCTAssertEqual(groups.flatMap(\.tools).map(\.name), AlvearyHostToolCatalog.tools.map(\.name))
        XCTAssertEqual(groups.map(\.id), AlvearyHostToolCatalog.featureCatalogs.map(\.featureID))
        XCTAssertEqual(groups.map(\.title), ["Scheduled tasks", "Threads", "Pull requests"])
        for group in groups {
            XCTAssertFalse(group.tools.isEmpty, group.id)
        }
    }

    func testEveryToolCarriesUserFacingCopy() {
        for tool in BuiltInMCPToolGroup.all.flatMap(\.tools) {
            XCTAssertFalse(tool.title.isEmpty, tool.name)
            XCTAssertNotEqual(tool.title, tool.name, "\(tool.name) has no title, so the pane would show its name twice")
            XCTAssertFalse(tool.description.isEmpty, tool.name)
        }
    }

    func testReadOnlyFollowsTheCatalogAnnotations() throws {
        let threads = try XCTUnwrap(BuiltInMCPToolGroup.all.first { $0.id == ThreadHostToolCatalog.featureID })
        let listThreads = try XCTUnwrap(threads.tools.first { $0.name == ThreadHostToolCatalog.listThreadsToolName })
        let createThread = try XCTUnwrap(threads.tools.first { $0.name == ThreadHostToolCatalog.createThreadToolName })

        XCTAssertTrue(listThreads.isReadOnly)
        XCTAssertFalse(createThread.isReadOnly)
    }
}

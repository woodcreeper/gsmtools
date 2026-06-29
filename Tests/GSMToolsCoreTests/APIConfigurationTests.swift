import Foundation
import XCTest
@testable import GSMToolsCore

final class APIConfigurationTests: XCTestCase {
    func testBaseURLWithVersionIsNotDoubleVersioned() {
        let config = APIConfiguration(baseURL: URL(string: "https://example.com/customerApi/v1")!)
        XCTAssertEqual(config.baseURL.absoluteString, "https://example.com/customerApi/v1")
    }

    func testBaseURLWithoutVersionAddsVersion() {
        let config = APIConfiguration(baseURL: URL(string: "https://example.com/customerApi")!)
        XCTAssertEqual(config.baseURL.absoluteString, "https://example.com/customerApi/v1")
    }
}

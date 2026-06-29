import Foundation
import XCTest
@testable import GSMToolsCore

final class CTTAPIClientTests: XCTestCase {
    override func tearDown() {
        PaginationURLProtocol.handler = nil
        super.tearDown()
    }

    func testPaginatedFetchRejectsNonAdvancingCursor() async throws {
        PaginationURLProtocol.handler = { request in
            let body = """
            {
              "data": [
                {
                  "projectId": "project",
                  "name": "Project",
                  "ownerId": "owner"
                }
              ],
              "pagination": {
                "nextCursor": "same-cursor",
                "hasMore": true
              }
            }
            """.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, body)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PaginationURLProtocol.self]
        let client = CTTAPIClient(
            configuration: APIConfiguration(baseURL: URL(string: "https://example.com/customerApi/v1")!),
            session: URLSession(configuration: configuration),
            tokenProvider: { "token" }
        )

        do {
            _ = try await client.allProjects(limit: 1)
            XCTFail("Expected non-advancing pagination to fail.")
        } catch let error as CTTAPIError {
            XCTAssertEqual(error.code, .invalidRequest)
            XCTAssertTrue(error.message.contains("Pagination"))
        }
    }
}

private final class PaginationURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

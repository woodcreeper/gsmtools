import Foundation
import XCTest
@testable import GSMToolsCore

final class APIModelDeploymentTests: XCTestCase {
    func testProjectDeviceDeploymentTimestampReadsNestedSnakeCaseAPIField() {
        let deployedAt = "2026-06-01T12:30:00Z"
        let device = ProjectDeviceListItem(
            imei: "351358812345678",
            deviceType: "flicker",
            deploymentInfo: .object(["deployed_at": .string(deployedAt)])
        )

        XCTAssertEqual(device.deploymentTimestamp, try TimestampNormalizer.parseISO8601(deployedAt))
    }

    func testDeviceProjectDeploymentTimestampReadsProjectScopedField() throws {
        let data = """
        {
          "imei": "351358812345678",
          "deviceType": "flicker",
          "deviceName": null,
          "iccid": null,
          "fw": {},
          "createdAt": "2026-01-01T00:00:00Z",
          "projectInfo": {
            "project-a": {
              "projectName": "Prairie Chickens",
              "alias": "PC-001",
              "deploymentDate": "2026-05-01T06:00:00Z"
            }
          }
        }
        """.data(using: .utf8)!

        let device = try JSONDecoder().decode(Device.self, from: data)

        XCTAssertEqual(
            device.projectInfo["project-a"]?.deploymentTimestamp,
            try TimestampNormalizer.parseISO8601("2026-05-01T06:00:00Z")
        )
    }

    func testDeviceDecodeAllowsMissingFirmwareProjectNameAndAlias() throws {
        let data = """
        {
          "imei": "351358812345678",
          "deviceType": "flicker",
          "projectInfo": {
            "project-a": {
              "deploymentDate": "2026-05-01T06:00:00Z"
            }
          }
        }
        """.data(using: .utf8)!

        let device = try JSONDecoder().decode(Device.self, from: data)

        XCTAssertNil(device.fw)
        XCTAssertNil(device.projectInfo["project-a"]?.projectName)
        XCTAssertNil(device.projectInfo["project-a"]?.alias)
        XCTAssertEqual(
            device.projectInfo["project-a"]?.deploymentTimestamp,
            try TimestampNormalizer.parseISO8601("2026-05-01T06:00:00Z")
        )
    }
}

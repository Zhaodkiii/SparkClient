import XCTest
@testable import SparkClient

final class AliyunOSSRuntimeConfigTests: XCTestCase {
    func testValidatedMatchingRegionEndpoint() throws {
        let response = OCRSTSCredentialsResponse(
            accessKeyID: "STS.AK",
            accessKeySecret: "secret",
            securityToken: "token",
            expiration: "1784869000",
            bucketName: "demo-bucket",
            region: "cn-beijing",
            endpoint: "https://oss-cn-beijing.aliyuncs.com",
            bucketRegion: "cn-beijing",
            objectKeyPrefix: "SparkClient/",
            configVersion: "oss-prod-v1",
            signatureVersion: "v4"
        )
        let cfg = try AliyunOSSRuntimeConfig.validated(from: response)
        XCTAssertEqual(cfg.region, "cn-beijing")
        XCTAssertEqual(cfg.bucketRegion, "cn-beijing")
        XCTAssertEqual(cfg.configVersion, "oss-prod-v1")
        XCTAssertEqual(cfg.objectKeyPrefix, "SparkClient/")
        XCTAssertTrue(cfg.isFresh(thresholdSeconds: 300))
    }

    func testShanghaiBeijingConflictRejected() {
        let response = OCRSTSCredentialsResponse(
            accessKeyID: "STS.AK",
            accessKeySecret: "secret",
            securityToken: "token",
            expiration: "1784869000",
            bucketName: "demo-bucket",
            region: "cn-shanghai",
            endpoint: "https://oss-cn-beijing.aliyuncs.com",
            bucketRegion: nil
        )
        XCTAssertThrowsError(try AliyunOSSRuntimeConfig.validated(from: response)) { error in
            guard let ossError = error as? SparkOSSConfigurationError else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertEqual(ossError, .configurationInvalid(reason: "endpointConfig"))
        }
        XCTAssertNil(AliyunOSSRuntimeConfig(response: response))
    }

    func testBucketRegionConflictRejected() {
        let response = OCRSTSCredentialsResponse(
            accessKeyID: "STS.AK",
            accessKeySecret: "secret",
            securityToken: nil,
            expiration: "1784869000",
            bucketName: "demo-bucket",
            region: "cn-beijing",
            endpoint: "https://oss-cn-beijing.aliyuncs.com",
            bucketRegion: "cn-shanghai"
        )
        XCTAssertThrowsError(try AliyunOSSRuntimeConfig.validated(from: response))
    }

    func testIncompleteRejected() {
        let response = OCRSTSCredentialsResponse(
            accessKeyID: "",
            accessKeySecret: "secret",
            securityToken: nil,
            expiration: nil,
            bucketName: "demo-bucket",
            region: "cn-beijing",
            endpoint: "https://oss-cn-beijing.aliyuncs.com"
        )
        XCTAssertThrowsError(try AliyunOSSRuntimeConfig.validated(from: response)) { error in
            XCTAssertEqual(error as? SparkOSSConfigurationError, .incompleteSTSResponse)
        }
    }

    func testSafeLogDetailOmitsSecrets() throws {
        let response = OCRSTSCredentialsResponse(
            accessKeyID: "STS.AK",
            accessKeySecret: "super-secret",
            securityToken: "tok",
            expiration: "1784869000",
            bucketName: "demo-bucket",
            region: "cn-beijing",
            endpoint: "https://oss-cn-beijing.aliyuncs.com",
            bucketRegion: "cn-beijing",
            configVersion: "oss-prod-v1"
        )
        let cfg = try AliyunOSSRuntimeConfig.validated(from: response)
        let detail = cfg.safeLogDetail
        XCTAssertFalse(detail.contains("super-secret"))
        XCTAssertFalse(detail.contains("demo-bucket"))
        XCTAssertTrue(detail.contains("configVersion=oss-prod-v1"))
        XCTAssertTrue(detail.contains("configuredRegionAlias=oss-cn-beijing"))
    }
}

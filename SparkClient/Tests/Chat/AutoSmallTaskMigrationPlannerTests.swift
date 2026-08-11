#if canImport(XCTest)
import Foundation
import XCTest

final class AutoSmallTaskMigrationPlannerTests: XCTestCase {
    private let planner = AutoSmallTaskMigrationPlanner()

    func testMissingRegistryInserts() {
        let decision = planner.plan(
            definition: makeDefinition(version: 1),
            registryRecord: nil,
            existingTask: nil,
            runtimeCapability: makeCapability()
        )

        XCTAssertEqual(decision, .insert)
    }

    func testMatchingVersionAndHashSkips() {
        let definition = makeDefinition(version: 1)
        let task = definition.makeSmallTask(id: 10)
        let record = makeRecord(definition: definition, taskID: task.id)

        let decision = planner.plan(
            definition: definition,
            registryRecord: record,
            existingTask: task,
            runtimeCapability: makeCapability()
        )

        XCTAssertEqual(decision, .skip)
    }

    func testLowerRegistryVersionUpgrades() {
        let oldDefinition = makeDefinition(version: 1)
        let newDefinition = makeDefinition(version: 2, prompt: "new prompt")
        let task = oldDefinition.makeSmallTask(id: 10)
        let record = makeRecord(definition: oldDefinition, taskID: task.id)

        let decision = planner.plan(
            definition: newDefinition,
            registryRecord: record,
            existingTask: task,
            runtimeCapability: makeCapability()
        )

        XCTAssertEqual(decision, .upgrade(fromVersion: 1, toVersion: 2))
    }

    func testLocalNewerVersionBlocks() {
        let bundleDefinition = makeDefinition(version: 2)
        let localDefinition = makeDefinition(version: 3)
        let task = localDefinition.makeSmallTask(id: 10)
        let record = makeRecord(definition: localDefinition, taskID: task.id)

        let decision = planner.plan(
            definition: bundleDefinition,
            registryRecord: record,
            existingTask: task,
            runtimeCapability: makeCapability()
        )

        XCTAssertEqual(decision, .blocked(reason: .localVersionNewerThanBundle))
    }

    func testSameVersionDifferentHashReportsHashConflict() {
        let oldDefinition = makeDefinition(version: 1, prompt: "old")
        let newDefinition = makeDefinition(version: 1, prompt: "new")
        let task = oldDefinition.makeSmallTask(id: 10)
        let record = makeRecord(definition: oldDefinition, taskID: task.id)

        let decision = planner.plan(
            definition: newDefinition,
            registryRecord: record,
            existingTask: task,
            runtimeCapability: makeCapability()
        )

        XCTAssertEqual(decision, .hashConflict)
    }

    func testRuntimeVersionTooLowBlocks() {
        let definition = makeDefinition(version: 1, minimumRuntimeVersion: 2)

        let decision = planner.plan(
            definition: definition,
            registryRecord: nil,
            existingTask: nil,
            runtimeCapability: makeCapability(runtimeVersion: 1)
        )

        XCTAssertEqual(decision, .blocked(reason: .runtimeVersionTooLow))
    }

    func testToolContractVersionTooLowBlocks() {
        let definition = makeDefinition(version: 1, toolContractVersion: 2)

        let decision = planner.plan(
            definition: definition,
            registryRecord: nil,
            existingTask: nil,
            runtimeCapability: makeCapability(toolContractVersion: 1)
        )

        XCTAssertEqual(decision, .blocked(reason: .toolContractVersionTooLow))
    }

    func testMissingRequiredToolsBlocks() {
        let definition = makeDefinition(version: 1, tools: ["generate_task", "missing_tool"])

        let decision = planner.plan(
            definition: definition,
            registryRecord: nil,
            existingTask: nil,
            runtimeCapability: makeCapability(availableTools: ["generate_task"])
        )

        XCTAssertEqual(decision, .blocked(reason: .missingRequiredTools))
    }

    private func makeDefinition(
        version: Int,
        prompt: String = "prompt",
        tools: [String] = ["generate_task"],
        minimumRuntimeVersion: Int = 1,
        toolContractVersion: Int = 1,
        migrationPolicy: AutoSmallTaskMigrationPolicy = .overwriteBuiltInOnly
    ) -> AutoSmallTaskDefinition {
        AutoSmallTaskDefinition(
            businessKey: .healthExamPlan,
            smallTaskCode: "Service_health_exam_plan_task",
            name: "生成体检计划",
            brief: "brief",
            prompt: prompt,
            icon: "stethoscope",
            toolList: tools,
            definitionVersion: version,
            minimumRuntimeVersion: minimumRuntimeVersion,
            toolContractVersion: toolContractVersion,
            migrationPolicy: migrationPolicy
        )
    }

    private func makeRecord(
        definition: AutoSmallTaskDefinition,
        taskID: Int
    ) -> AutoSmallTaskRegistryRecord {
        AutoSmallTaskRegistryRecord(
            userID: 1,
            businessKey: definition.businessKey,
            smallTaskCode: definition.smallTaskCode,
            localSmallTaskID: taskID,
            definitionVersion: definition.definitionVersion,
            minimumRuntimeVersion: definition.minimumRuntimeVersion,
            toolContractVersion: definition.toolContractVersion,
            payloadHash: definition.payloadHash,
            lastMigrationAction: .inserted,
            lastMigrationReason: "test",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeCapability(
        runtimeVersion: Int = 1,
        toolContractVersion: Int = 2,
        availableTools: Set<String> = Set(SparkToolName.all)
    ) -> AutoSmallTaskRuntimeCapability {
        AutoSmallTaskRuntimeCapability(
            runtimeVersion: runtimeVersion,
            toolContractVersion: toolContractVersion,
            availableToolNames: availableTools
        )
    }
}
#endif

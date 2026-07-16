import Foundation

enum TaskRuntimeSelfTest {
    static func run() -> Bool {
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        let now = Date()
        expect(
            TaskActivityClassifier.column(updatedAt: now.addingTimeInterval(-30 * 60), now: now) == .active,
            "recently active task should stay in the active column"
        )
        expect(
            TaskActivityClassifier.column(updatedAt: now.addingTimeInterval(-3 * 60 * 60), now: now) == .pending,
            "older task should move to the pending column"
        )
        expect(
            TaskActivityClassifier.column(updatedAt: nil, now: now) == .pending,
            "task without activity time should remain pending"
        )
        expect(
            TaskThreadVisibility.isSubagent(["threadSource": "subagent"]),
            "direct subagent source should be filtered"
        )
        expect(
            TaskThreadVisibility.isSubagent(["source": ["subAgent": ["depth": 1]]]),
            "structured subagent source should be filtered"
        )
        expect(
            !TaskThreadVisibility.isSubagent(["threadSource": "user"]),
            "user thread should remain visible"
        )

        var reducer = TaskRuntimeReducer()
        reducer.replaceThreads([
            [
                "id": "active-with-unknown-flag",
                "updatedAt": Int(now.timeIntervalSince1970),
                "status": ["type": "active", "activeFlags": ["unknownFlag"]]
            ],
            [
                "id": "input-thread",
                "updatedAt": Int(now.timeIntervalSince1970),
                "status": ["type": "active", "activeFlags": ["waitingOnUserInput"]]
            ],
            [
                "id": "running-thread",
                "updatedAt": Int(now.timeIntervalSince1970),
                "status": ["type": "active", "activeFlags": []]
            ],
            [
                "id": "record-thread",
                "updatedAt": Int(now.timeIntervalSince1970),
                "status": ["type": "notLoaded"]
            ],
            [
                "id": "hidden-subagent",
                "threadSource": "subagent",
                "updatedAt": Int(now.timeIntervalSince1970),
                "status": ["type": "active", "activeFlags": []]
            ]
        ], connectionMode: .isolated)

        var snapshot = reducer.snapshot(at: now)
        expect(
            snapshot.records["active-with-unknown-flag"]?.state == .running,
            "unknown flags should not create a distinct task state"
        )
        expect(snapshot.records["input-thread"]?.state == .waitingInput, "input flag should map to waitingInput")
        expect(snapshot.records["running-thread"]?.state == .running, "active without flags should map to running")
        expect(snapshot.records["record-thread"]?.state == .recorded, "notLoaded should remain recorded")
        expect(snapshot.records["record-thread"]?.isRealtime == false, "notLoaded should not be presented as realtime")
        expect(snapshot.records["hidden-subagent"] == nil, "subagent should not enter the live task snapshot")

        let recentItem = TaskItem(
            id: "record-thread-active",
            code: "COD-TEST",
            title: "Recent task",
            detail: "",
            chip: "Active",
            updatedAt: now,
            tokens: nil,
            kind: .active,
            threadID: "record-thread"
        )
        let baseBoard = TaskBoard(refreshedAt: now, columns: [
            TaskColumn(id: .active, title: "Active", count: 1, items: [recentItem]),
            TaskColumn(id: .pending, title: "Pending", count: 0, items: []),
            TaskColumn(id: .scheduled, title: "Scheduled", count: 0, items: []),
            TaskColumn(id: .done, title: "Done", count: 0, items: [])
        ])
        let recordedSnapshot = CodexTaskLiveSnapshot(
            connectionMode: .isolated,
            records: [
                "record-thread": TaskLiveRecord(
                    threadID: "record-thread",
                    name: nil,
                    state: .recorded,
                    updatedAt: now,
                    turnID: nil,
                    connectionMode: .isolated
                )
            ],
            refreshedAt: now
        )
        let mergedBoard = baseBoard.merging(recordedSnapshot, now: now)
        expect(
            mergedBoard.columns.first(where: { $0.id == .active })?.items.contains(where: { $0.threadID == "record-thread" }) == true,
            "notLoaded snapshot must not move a recently active task to pending"
        )

        reducer.disconnect()
        snapshot = reducer.snapshot(at: now)
        expect(snapshot.connectionMode == .disconnected, "disconnect should publish disconnected mode")
        expect(snapshot.records["running-thread"]?.state == .disconnected, "active task should become disconnected")
        expect(snapshot.records["input-thread"]?.state == .disconnected, "input task should become disconnected")

        let attention = TaskAttentionSelector.highestPriority([
            TaskAttentionItem(id: "update", kind: .update, runtimeScope: nil, threadID: nil, title: "Update", since: nil),
            TaskAttentionItem(id: "failure", kind: .failure, runtimeScope: .codex, threadID: "a", title: "Failure", since: now),
            TaskAttentionItem(id: "input", kind: .userInput, runtimeScope: .codex, threadID: "b", title: "Input", since: now.addingTimeInterval(-10))
        ])
        expect(attention?.id == "input", "user input must outrank failure and update")

        if failures.isEmpty {
            print("task runtime self-test passed")
            return true
        }
        for failure in failures {
            print("task runtime self-test failed: \(failure)")
        }
        return false
    }
}

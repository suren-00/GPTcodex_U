import Foundation

enum TaskRuntimeState: String, Equatable {
    case recorded
    case idle
    case running
    case waitingInput
    case failed
    case completed
    case interrupted
    case disconnected

    var attentionRank: Int? {
        switch self {
        case .waitingInput:
            return 0
        case .failed:
            return 1
        case .recorded, .idle, .running, .completed, .interrupted, .disconnected:
            return nil
        }
    }

    var columnKind: TaskColumnKind {
        switch self {
        case .running, .waitingInput:
            return .active
        case .completed:
            return .done
        case .recorded, .idle, .failed, .interrupted, .disconnected:
            return .pending
        }
    }
}

enum TaskConnectionMode: String, Equatable {
    case disconnected
    case sharedDaemon
    case isolated
}

enum TaskActivityClassifier {
    static let activeWindow: TimeInterval = 2 * 60 * 60

    static func column(updatedAt: Date?, now: Date) -> TaskColumnKind {
        guard let updatedAt else { return .pending }
        return updatedAt >= now.addingTimeInterval(-activeWindow) ? .active : .pending
    }
}

enum TaskThreadVisibility {
    static func isSubagent(_ thread: [String: Any]) -> Bool {
        let directSource = (thread["threadSource"] as? String)
            ?? (thread["thread_source"] as? String)
        if directSource?.lowercased() == "subagent" { return true }

        if let source = thread["source"] as? String {
            return source.lowercased() == "subagent"
        }
        if let source = thread["source"] as? [String: Any] {
            return source.keys.contains { $0.lowercased() == "subagent" }
        }
        return false
    }
}

struct TaskLiveRecord: Equatable {
    let threadID: String
    let name: String?
    let state: TaskRuntimeState
    let updatedAt: Date?
    let turnID: String?
    let connectionMode: TaskConnectionMode

    var isRealtime: Bool {
        connectionMode != .disconnected && state != .recorded && state != .disconnected
    }
}

struct CodexTaskLiveSnapshot: Equatable {
    let connectionMode: TaskConnectionMode
    let records: [String: TaskLiveRecord]
    let refreshedAt: Date

    static let disconnected = CodexTaskLiveSnapshot(
        connectionMode: .disconnected,
        records: [:],
        refreshedAt: .distantPast
    )
}

struct TaskRuntimeReducer {
    private(set) var connectionMode: TaskConnectionMode = .disconnected
    private var records: [String: TaskLiveRecord] = [:]

    mutating func replaceThreads(_ threads: [[String: Any]], connectionMode: TaskConnectionMode) {
        self.connectionMode = connectionMode
        var nextRecords: [String: TaskLiveRecord] = [:]

        for thread in threads {
            guard !TaskThreadVisibility.isSubagent(thread) else { continue }
            guard let threadID = thread["id"] as? String else { continue }
            let previous = records[threadID]
            let state = Self.runtimeState(from: thread["status"] as? [String: Any])
            let updatedAt = Self.dateFromSeconds(thread["updatedAt"])
            let rawName = (thread["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = rawName.flatMap { $0.isEmpty ? nil : $0 }

            nextRecords[threadID] = TaskLiveRecord(
                threadID: threadID,
                name: name ?? previous?.name,
                state: state,
                updatedAt: updatedAt ?? previous?.updatedAt,
                turnID: previous?.turnID,
                connectionMode: connectionMode
            )
        }

        records = nextRecords
    }

    @discardableResult
    mutating func applyNotification(method: String, params: [String: Any]) -> Bool {
        switch method {
        case "thread/status/changed":
            guard let threadID = params["threadId"] as? String else { return false }
            updateRecord(
                threadID: threadID,
                state: Self.runtimeState(from: params["status"] as? [String: Any]),
                updatedAt: Date()
            )
            return true

        case "turn/started":
            guard let threadID = params["threadId"] as? String else { return false }
            let turn = params["turn"] as? [String: Any]
            updateRecord(
                threadID: threadID,
                state: .running,
                updatedAt: Date(),
                turnID: turn?["id"] as? String
            )
            return true

        case "turn/completed":
            guard let threadID = params["threadId"] as? String,
                  let turn = params["turn"] as? [String: Any]
            else { return false }
            let state = Self.turnState(turn["status"] as? String)
            updateRecord(
                threadID: threadID,
                state: state,
                updatedAt: Date(),
                turnID: turn["id"] as? String
            )
            return true

        case "item/completed":
            guard let threadID = params["threadId"] as? String,
                  let item = params["item"] as? [String: Any]
            else { return false }
            let status = item["status"] as? String
            if status == "failed" {
                updateRecord(threadID: threadID, state: .failed, updatedAt: Date())
                return true
            }
            return false

        default:
            return false
        }
    }

    mutating func disconnect() {
        connectionMode = .disconnected
        records = records.mapValues { record in
            let disconnectedState: TaskRuntimeState
            switch record.state {
            case .running, .waitingInput:
                disconnectedState = .disconnected
            default:
                disconnectedState = record.state
            }
            return TaskLiveRecord(
                threadID: record.threadID,
                name: record.name,
                state: disconnectedState,
                updatedAt: record.updatedAt,
                turnID: record.turnID,
                connectionMode: .disconnected
            )
        }
    }

    func snapshot(at date: Date = Date()) -> CodexTaskLiveSnapshot {
        CodexTaskLiveSnapshot(
            connectionMode: connectionMode,
            records: records,
            refreshedAt: date
        )
    }

    private mutating func updateRecord(
        threadID: String,
        state: TaskRuntimeState,
        updatedAt: Date?,
        turnID: String? = nil
    ) {
        let previous = records[threadID]
        records[threadID] = TaskLiveRecord(
            threadID: threadID,
            name: previous?.name,
            state: state,
            updatedAt: updatedAt ?? previous?.updatedAt,
            turnID: turnID ?? previous?.turnID,
            connectionMode: connectionMode
        )
    }

    private static func runtimeState(from status: [String: Any]?) -> TaskRuntimeState {
        guard let type = status?["type"] as? String else { return .recorded }
        switch type {
        case "active":
            let flags = status?["activeFlags"] as? [String] ?? []
            if flags.contains("waitingOnUserInput") { return .waitingInput }
            return .running
        case "idle":
            return .idle
        case "systemError":
            return .failed
        default:
            return .recorded
        }
    }

    private static func turnState(_ status: String?) -> TaskRuntimeState {
        switch status {
        case "completed":
            return .completed
        case "interrupted":
            return .interrupted
        case "failed":
            return .failed
        case "inProgress":
            return .running
        default:
            return .recorded
        }
    }

    private static func dateFromSeconds(_ value: Any?) -> Date? {
        if let value = value as? Int { return Date(timeIntervalSince1970: TimeInterval(value)) }
        if let value = value as? Int64 { return Date(timeIntervalSince1970: TimeInterval(value)) }
        if let value = value as? NSNumber { return Date(timeIntervalSince1970: value.doubleValue) }
        return nil
    }

}

enum TaskAttentionKind: Int, Equatable {
    case userInput = 0
    case failure = 1
    case dataIssue = 2
    case update = 3
}

struct TaskAttentionItem: Identifiable, Equatable {
    let id: String
    let kind: TaskAttentionKind
    let runtimeScope: RuntimeScope?
    let threadID: String?
    let title: String
    let since: Date?
}

struct TaskFocusRequest: Equatable {
    let id: UUID
    let runtimeScope: RuntimeScope
    let threadID: String?
}

enum TaskAttentionSelector {
    static func highestPriority(_ items: [TaskAttentionItem]) -> TaskAttentionItem? {
        items.sorted { lhs, rhs in
            if lhs.kind.rawValue != rhs.kind.rawValue {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            switch (lhs.since, rhs.since) {
            case let (left?, right?) where left != right:
                return left < right
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                return lhs.id < rhs.id
            }
        }.first
    }
}

extension TaskItem {
    func applying(_ record: TaskLiveRecord) -> TaskItem {
        TaskItem(
            id: id,
            code: code,
            title: title,
            detail: detail,
            chip: chip,
            updatedAt: record.updatedAt ?? updatedAt,
            tokens: tokens,
            kind: record.state.columnKind,
            threadID: record.threadID,
            runtimeState: record.state,
            isRealtime: record.isRealtime
        )
    }
}

extension TaskBoard {
    func merging(_ live: CodexTaskLiveSnapshot, now: Date = Date()) -> TaskBoard {
        var itemsByThread: [String: TaskItem] = [:]
        var scheduledItems: [TaskItem] = []

        for column in columns {
            for item in column.items {
                if item.kind == .scheduled || item.threadID == nil {
                    scheduledItems.append(item)
                } else if let threadID = item.threadID {
                    itemsByThread[threadID] = item
                }
            }
        }

        for record in live.records.values where record.isRealtime {
            if let existing = itemsByThread[record.threadID] {
                itemsByThread[record.threadID] = existing.applying(record)
            } else if Calendar.current.isDate(record.updatedAt ?? now, inSameDayAs: now) {
                let compactID = record.threadID.replacingOccurrences(of: "-", with: "")
                let item = TaskItem(
                    id: "live-\(record.threadID)",
                    code: "COD-\(compactID.suffix(4).uppercased())",
                    title: record.name ?? "Codex task",
                    detail: "",
                    chip: "Live",
                    updatedAt: record.updatedAt,
                    tokens: nil,
                    kind: record.state.columnKind,
                    threadID: record.threadID,
                    runtimeState: record.state,
                    isRealtime: record.isRealtime
                )
                itemsByThread[record.threadID] = item
            }
        }

        let threadItems = Array(itemsByThread.values)
        func sorted(_ kind: TaskColumnKind) -> [TaskItem] {
            threadItems.filter { $0.kind == kind }.sorted { lhs, rhs in
                let leftRank = lhs.runtimeState.attentionRank ?? Int.max
                let rightRank = rhs.runtimeState.attentionRank ?? Int.max
                if leftRank != rightRank { return leftRank < rightRank }
                return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
            }
        }

        let titles = Dictionary(uniqueKeysWithValues: columns.map { ($0.id, $0.title) })
        let active = sorted(.active)
        let pending = sorted(.pending)
        let done = sorted(.done)
        let scheduled = scheduledItems.sorted { $0.title < $1.title }

        return TaskBoard(refreshedAt: now, columns: [
            TaskColumn(id: .active, title: titles[.active] ?? "Active", count: active.count, items: active),
            TaskColumn(id: .pending, title: titles[.pending] ?? "Pending", count: pending.count, items: pending),
            TaskColumn(id: .scheduled, title: titles[.scheduled] ?? "Scheduled", count: scheduled.count, items: scheduled),
            TaskColumn(id: .done, title: titles[.done] ?? "Done", count: done.count, items: done)
        ])
    }

    func attentionItems(scope: RuntimeScope) -> [TaskAttentionItem] {
        columns.flatMap(\.items).compactMap { item in
            let kind: TaskAttentionKind
            switch item.runtimeState {
            case .waitingInput:
                kind = .userInput
            case .failed:
                kind = .failure
            default:
                return nil
            }
            return TaskAttentionItem(
                id: "\(scope.runtimeId)-\(item.id)-\(kind.rawValue)",
                kind: kind,
                runtimeScope: scope,
                threadID: item.threadID,
                title: item.title,
                since: item.updatedAt
            )
        }
    }
}

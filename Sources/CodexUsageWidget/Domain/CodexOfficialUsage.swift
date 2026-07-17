import Foundation

struct CodexOfficialUsageSnapshot: Equatable {
    let lifetimeTokens: Int64
    let dailyTokens: [String: Int64]

    func tokens(on dayKey: String) -> Int64 {
        max(dailyTokens[dayKey] ?? 0, 0)
    }

    func total(for dayKeys: some Sequence<String>) -> Int64 {
        dayKeys.reduce(Int64(0)) { $0 + tokens(on: $1) }
    }
}

enum CodexOfficialUsageNormalizer {
    static func parse(_ result: [String: Any]) -> CodexOfficialUsageSnapshot? {
        guard let summary = result["summary"] as? [String: Any],
              let lifetimeTokens = int64(summary["lifetimeTokens"])
        else { return nil }

        var dailyTokens: [String: Int64] = [:]
        for bucket in result["dailyUsageBuckets"] as? [[String: Any]] ?? [] {
            guard let dayKey = bucket["startDate"] as? String,
                  !dayKey.isEmpty,
                  let tokens = int64(bucket["tokens"])
            else { continue }
            dailyTokens[dayKey] = max(tokens, 0)
        }

        return CodexOfficialUsageSnapshot(
            lifetimeTokens: max(lifetimeTokens, 0),
            dailyTokens: dailyTokens
        )
    }

    static func align(_ local: PricedTokenUsage?, to officialTotal: Int64) -> PricedTokenUsage {
        let total = max(officialTotal, 0)
        guard total > 0 else { return .zero }
        guard let local else {
            return PricedTokenUsage(
                tokens: TokenBreakdown(
                    inputTokens: 0,
                    cachedInputTokens: 0,
                    outputTokens: 0,
                    reasoningOutputTokens: 0,
                    totalTokens: total
                ),
                estimatedCostUSD: 0
            )
        }

        let localVisibleTotal = local.tokens.visibleTotalTokens
        let localSplitTotal = local.tokens.splitTotalTokens
        guard localVisibleTotal > 0, localSplitTotal > 0 else {
            return PricedTokenUsage(
                tokens: TokenBreakdown(
                    inputTokens: 0,
                    cachedInputTokens: 0,
                    outputTokens: 0,
                    reasoningOutputTokens: 0,
                    totalTokens: total
                ),
                estimatedCostUSD: 0
            )
        }

        let output = min(
            total,
            Int64((Double(total) * Double(max(local.tokens.outputTokens, 0)) / Double(localSplitTotal)).rounded())
        )
        let remainingAfterOutput = total - output
        let cached = min(
            remainingAfterOutput,
            Int64((Double(total) * Double(local.tokens.billableCachedInputTokens) / Double(localSplitTotal)).rounded())
        )
        let uncached = max(total - output - cached, 0)
        let scale = Double(total) / Double(localVisibleTotal)

        return PricedTokenUsage(
            tokens: TokenBreakdown(
                inputTokens: uncached + cached,
                cachedInputTokens: cached,
                outputTokens: output,
                reasoningOutputTokens: Int64((Double(max(local.tokens.reasoningOutputTokens, 0)) * scale).rounded()),
                totalTokens: total
            ),
            estimatedCostUSD: max(local.estimatedCostUSD * scale, 0)
        )
    }

    private static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let value as Int64:
            return value
        case let value as Int:
            return Int64(value)
        case let value as NSNumber:
            return value.int64Value
        case let value as String:
            return Int64(value)
        default:
            return nil
        }
    }
}

enum CodexOfficialUsageSelfTest {
    static func run() -> Bool {
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        let fixture: [String: Any] = [
            "summary": ["lifetimeTokens": 1_374_822_051],
            "dailyUsageBuckets": [
                ["startDate": "2026-07-15", "tokens": 62_930_566],
                ["startDate": "2026-07-16", "tokens": 44_290_804]
            ]
        ]
        let parsed = CodexOfficialUsageNormalizer.parse(fixture)
        expect(parsed?.lifetimeTokens == 1_374_822_051, "official lifetime total should be parsed exactly")
        expect(parsed?.tokens(on: "2026-07-16") == 44_290_804, "official daily total should be parsed exactly")
        expect(parsed?.tokens(on: "2026-07-17") == 0, "a missing official day should remain zero")

        let local = PricedTokenUsage(
            tokens: TokenBreakdown(
                inputTokens: 100,
                cachedInputTokens: 80,
                outputTokens: 20,
                reasoningOutputTokens: 10,
                totalTokens: 120
            ),
            estimatedCostUSD: 12
        )
        let aligned = CodexOfficialUsageNormalizer.align(local, to: 60)
        expect(aligned.tokens.visibleTotalTokens == 60, "aligned usage should preserve the official total")
        expect(aligned.tokens.splitTotalTokens == 60, "aligned token splits should add up to the official total")
        expect(aligned.estimatedCostUSD == 6, "aligned estimated cost should preserve the local price ratio")

        if failures.isEmpty {
            print("Codex official usage self-test passed")
            return true
        }
        failures.forEach { print("Codex official usage self-test failed: \($0)") }
        return false
    }
}

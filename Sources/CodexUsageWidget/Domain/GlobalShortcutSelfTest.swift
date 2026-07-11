import Carbon.HIToolbox
import Cocoa
import Foundation

enum GlobalShortcutSelfTest {
    private static let signature: OSType = 0x43535455 // CSTU
    private static let oldShortcut = GlobalShortcut(
        keyCode: UInt32(kVK_F11),
        carbonModifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey),
        keyLabel: "F11"
    )
    private static let occupiedShortcut = GlobalShortcut(
        keyCode: UInt32(kVK_F12),
        carbonModifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey),
        keyLabel: "F12"
    )

    static func run() -> Bool {
        _ = NSApplication.shared
        var failures: [String] = []
        checkValidationRules(failures: &failures)
        checkReplacementTransaction(failures: &failures)
        checkExclusiveConflictPreservesOldRegistration(failures: &failures)

        if failures.isEmpty {
            print("global shortcut self-test passed")
            return true
        }
        for failure in failures {
            print("global shortcut self-test failed: \(failure)")
        }
        return false
    }

    static func holdExclusiveShortcut(readyFile: String) -> Never {
        _ = NSApplication.shared
        var hotKeyRef: EventHotKeyRef?
        let status = registerExclusive(
            occupiedShortcut,
            id: 100,
            reference: &hotKeyRef
        )
        guard status == noErr, hotKeyRef != nil else {
            try? "error:\(status)".write(
                toFile: readyFile,
                atomically: true,
                encoding: .utf8
            )
            exit(2)
        }
        try? "ready".write(toFile: readyFile, atomically: true, encoding: .utf8)
        RunLoop.current.run(until: Date().addingTimeInterval(15))
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        exit(0)
    }

    private static func checkValidationRules(failures: inout [String]) {
        let cases: [(String, GlobalShortcut, GlobalShortcutValidationError?)] = [
            ("default command+U", .default, nil),
            ("shift+A", shortcut(kVK_ANSI_A, shiftKey, "A"), .tooFewModifiers),
            ("option+A", shortcut(kVK_ANSI_A, optionKey, "A"), .tooFewModifiers),
            ("command+Q", shortcut(kVK_ANSI_Q, cmdKey, "Q"), .tooFewModifiers),
            ("option+shift+A", shortcut(kVK_ANSI_A, optionKey | shiftKey, "A"), .requiresCommandOrControl),
            ("command+option+escape", shortcut(kVK_Escape, cmdKey | optionKey, "⎋"), .reservedSystemShortcut),
            ("command+control+Q", shortcut(kVK_ANSI_Q, cmdKey | controlKey, "Q"), .reservedSystemShortcut),
            ("command+shift+3", shortcut(kVK_ANSI_3, cmdKey | shiftKey, "3"), .reservedSystemShortcut),
            ("command+shift+U", shortcut(kVK_ANSI_U, cmdKey | shiftKey, "U"), nil),
            ("control+option+F8", shortcut(kVK_F8, controlKey | optionKey, "F8"), nil),
            ("command+shift+comma", shortcut(kVK_ANSI_Comma, cmdKey | shiftKey, ","), .unsupportedKey)
        ]

        for (name, shortcut, expected) in cases where shortcut.validationError != expected {
            failures.append("\(name) expected \(String(describing: expected)), got \(String(describing: shortcut.validationError))")
        }
    }

    private static func checkExclusiveConflictPreservesOldRegistration(
        failures: inout [String]
    ) {
        guard let executableURL = Bundle.main.executableURL else {
            failures.append("could not locate self-test executable")
            return
        }

        let readyFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexu-hotkey-self-test-\(UUID().uuidString)")
        let helper = Process()
        helper.executableURL = executableURL
        helper.arguments = ["--hold-exclusive-hotkey", readyFile.path]

        do {
            try helper.run()
        } catch {
            failures.append("could not launch conflict helper: \(error)")
            return
        }

        defer {
            if helper.isRunning { helper.terminate() }
            try? FileManager.default.removeItem(at: readyFile)
        }

        let deadline = Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath: readyFile.path), Date() < deadline {
            if !helper.isRunning { break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard FileManager.default.fileExists(atPath: readyFile.path) else {
            failures.append("conflict helper did not acquire the exclusive shortcut")
            return
        }
        let helperState = (try? String(contentsOf: readyFile, encoding: .utf8)) ?? ""
        guard helperState == "ready" else {
            failures.append("conflict helper registration failed: \(helperState)")
            return
        }

        var oldRef: EventHotKeyRef?
        let oldStatus = registerExclusive(oldShortcut, id: 1, reference: &oldRef)
        guard oldStatus == noErr, let oldRef else {
            failures.append("could not register the old shortcut, status=\(oldStatus)")
            return
        }

        var candidateRef: EventHotKeyRef?
        let candidateStatus = registerExclusive(
            occupiedShortcut,
            id: 2,
            reference: &candidateRef
        )
        if candidateStatus != eventHotKeyExistsErr {
            failures.append("exclusive conflict returned \(candidateStatus), expected \(eventHotKeyExistsErr)")
        }
        if let candidateRef {
            UnregisterEventHotKey(candidateRef)
            failures.append("exclusive conflict unexpectedly returned a candidate reference")
        }
        if UnregisterEventHotKey(oldRef) != noErr {
            failures.append("old shortcut was not retained after candidate conflict")
        }
    }

    private static func checkReplacementTransaction(failures: inout [String]) {
        var unregistered: [Int] = []
        let failed: Result<Int, GlobalShortcutRegistrationFailure> =
            GlobalShortcutRegistrationTransaction.replace(
                current: 1,
                registerCandidate: { .failure(.occupied) },
                unregister: { unregistered.append($0) }
            )
        guard failed == .failure(.occupied), unregistered.isEmpty else {
            failures.append("failed replacement unregistered the old shortcut")
            return
        }

        let succeeded: Result<Int, GlobalShortcutRegistrationFailure> =
            GlobalShortcutRegistrationTransaction.replace(
                current: 1,
                registerCandidate: { .success(2) },
                unregister: { unregistered.append($0) }
            )
        if succeeded != .success(2) || unregistered != [1] {
            failures.append("successful replacement did not swap registrations transactionally")
        }
    }

    private static func shortcut(
        _ keyCode: Int,
        _ modifiers: Int,
        _ label: String
    ) -> GlobalShortcut {
        GlobalShortcut(
            keyCode: UInt32(keyCode),
            carbonModifiers: UInt32(modifiers),
            keyLabel: label
        )
    }

    private static func registerExclusive(
        _ shortcut: GlobalShortcut,
        id: UInt32,
        reference: inout EventHotKeyRef?
    ) -> OSStatus {
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        return RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            UInt32(kEventHotKeyExclusive),
            &reference
        )
    }
}

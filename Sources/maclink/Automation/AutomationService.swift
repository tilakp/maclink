import Foundation
import AppKit

enum AutomationError: Error, Equatable {
    case permissionDenied
    case appNotRunning
    case timeout
    case scriptError(Int, String)
    case malformedResult
}

/// Owns every `NSAppleScript` call behind a single serialization point, per
/// spec §3.3/§4.3: `NSAppleScript` is not thread-safe, so all calls funnel
/// through one queue; each call additionally runs on its own throwaway
/// thread so a hung target app can be timed out from the caller's side
/// without blocking the queue for other (unrelated) automation forever.
/// (The in-flight Apple Event itself can't be cancelled. Only the wait can.)
/// `@unchecked` because `compiledCache` is only ever touched from within
/// `queue.async` closures, which the `DispatchQueue` serializes for us.
final class AutomationService: @unchecked Sendable {
    static let shared = AutomationService()

    private let queue = DispatchQueue(label: "com.maclink.automation")
    private var compiledCache: [String: NSAppleScript] = [:]

    private init() {}

    @discardableResult
    func run(_ source: String, timeout: TimeInterval = 3.0) async throws -> NSAppleEventDescriptor {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: self.runSync(source: source, timeout: timeout))
            }
        }
    }

    private func compiledScript(for source: String) -> Result<NSAppleScript, AutomationError> {
        if let cached = compiledCache[source] {
            return .success(cached)
        }
        guard let script = NSAppleScript(source: source) else {
            return .failure(.scriptError(-1, "could not allocate NSAppleScript"))
        }
        var errorDict: NSDictionary?
        // Compile eagerly so a syntax error surfaces here, not mid-execution.
        guard script.compileAndReturnError(&errorDict) else {
            return .failure(Self.mapError(errorDict))
        }
        compiledCache[source] = script
        return .success(script)
    }

    private func runSync(source: String, timeout: TimeInterval) -> Result<NSAppleEventDescriptor, Error> {
        switch compiledScript(for: source) {
        case .failure(let error):
            return .failure(error)
        case .success(let script):
            let semaphore = DispatchSemaphore(value: 0)
            var errorDict: NSDictionary?
            var resultDescriptor: NSAppleEventDescriptor?

            let thread = Thread {
                resultDescriptor = script.executeAndReturnError(&errorDict)
                semaphore.signal()
            }
            thread.stackSize = 1 << 20
            thread.start()

            if semaphore.wait(timeout: .now() + timeout) == .timedOut {
                Log.automation.error("automation call timed out after \(timeout, format: .fixed(precision: 1))s (may still complete in the background)")
                return .failure(AutomationError.timeout)
            }
            if let errorDict {
                let mapped = Self.mapError(errorDict)
                Log.automation.error("automation error: \(String(describing: mapped), privacy: .public)")
                return .failure(mapped)
            }
            guard let resultDescriptor else {
                return .failure(AutomationError.malformedResult)
            }
            return .success(resultDescriptor)
        }
    }

    private static func mapError(_ dict: NSDictionary?) -> AutomationError {
        guard let dict else { return .scriptError(-1, "unknown error") }
        let number = (dict["NSAppleScriptErrorNumber"] as? Int) ?? -1
        let message = (dict["NSAppleScriptErrorMessage"] as? String) ?? "unknown error"
        switch number {
        case -1743: return .permissionDenied
        case -600: return .appNotRunning
        default: return .scriptError(number, message)
        }
    }
}

// MARK: - AEDesc -> Swift value helpers

extension NSAppleEventDescriptor {
    /// A list-typed result's items as strings, skipping anything that isn't
    /// coercible. Used by capturers that return `{a, b, c}` from AppleScript.
    var stringListValue: [String] {
        guard descriptorType == typeAEList else {
            return stringValue.map { [$0] } ?? []
        }
        guard numberOfItems > 0 else { return [] }
        var result: [String] = []
        for i in 1...numberOfItems {
            if let item = atIndex(i)?.stringValue {
                result.append(item)
            }
        }
        return result
    }
}

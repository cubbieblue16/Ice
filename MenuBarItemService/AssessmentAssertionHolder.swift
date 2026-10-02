//
//  AssessmentAssertionHolder.swift
//  MenuBarItemService
//
//  Adapted from Barometer's MenuBarAssessmentAssertion.swift
//  (https://github.com/mackid1993/Barometer), itself adapted from Thaw's
//  PlatformRuntimeKit (https://github.com/thaw-app/Thaw). Both are licensed
//  under the GNU GPLv3, like Ice.
//

import Foundation
import OSLog
import XPC

/// Holds MenuBarAgent's assessment-mode assertions on Ice's behalf.
///
/// A configuration lists the numbered system items and the bundle identifiers
/// that stay on the bar. While an assertion is live, the bar removes every other
/// application's items, and the items of the process holding the assertion as
/// well, even when its bundle identifier is in the allowlist (measured on macOS
/// 27.0, 2026-10-01; signing makes no difference). Ice would lose its own icon
/// whenever it concealed anything, so this service holds the assertions instead.
///
/// Each live assertion is known to the app by an identifier and belongs to the
/// session that asked for it. When that session ends, its assertions are released.
///
/// All state, and every call into `MenuBarClientCore`, stays on a serial queue
/// that targets the main thread, where the app made those calls when it held the
/// assertions itself.
@available(macOS 27.0, *)
final class AssessmentAssertionHolder {
    enum Failure: Error, CustomStringConvertible {
        case unavailable
        case rejected(String)
        case timedOut

        var description: String {
            switch self {
            case .unavailable: "MenuBarClientCore is unavailable"
            case .rejected(let reason): "MenuBarAgent rejected the assertion: \(reason)"
            case .timedOut: "MenuBarAgent did not answer within 3 seconds"
            }
        }
    }

    /// An activation MenuBarAgent has not answered yet.
    private struct PendingActivation {
        let assertion: AnyObject
        let client: UUID
        let reply: (MenuBarItemService.Response) -> Void
    }

    /// The shared holder.
    static let shared = AssessmentAssertionHolder()

    private static let frameworkPath = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let configureSelector = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private static let activateSelector = NSSelectorFromString("activateWithConfiguration:completionHandler:")
    private static let invalidateSelector = NSSelectorFromString("invalidate")

    /// How long MenuBarAgent has to answer an activation.
    private static let timeout = DispatchTimeInterval.seconds(3)

    /// The system items Ice keeps on the bar.
    ///
    /// MenuBarAgent numbers them. On the macOS 27.0 machine first measured, 0 is the battery,
    /// 2 the clock, 6 Wi-Fi and 8 Control Centre, while 1, 3, 4, 5 and 7 draw nothing, and
    /// nothing there was numbered above 8. Other machines number items higher: with the range
    /// at 0...63, Screen Mirroring was silently concealed (field measurement in
    /// jordanbaird/Ice#954, by brentc22). MenuBarAgent ignores a number with no item behind it,
    /// so the full 0...255 is safe, and it keeps a system item numbered higher, or one added by
    /// a later build, from being concealed: Ice hides applications' items, not the system's.
    ///
    /// Control Centre's capture indicator — the green camera button, orange for the microphone,
    /// indigo for screen sharing — is not one of these numbers and cannot be kept. It is drawn
    /// while no assertion is live and gone while one is, whatever the allowlist holds: every
    /// number to 127, Control Centre's bundle identifier, the capturing application's own. The
    /// small green dot beside the clock is not an item and stays either way. Measured with
    /// `Scripts/macos27/system-item-probe.swift` on macOS 27.0 (2026-09-29).
    private static let systemItems = (0...255).map { NSNumber(value: $0) } as NSArray

    private static let classes: (configuration: AnyClass, assertion: AnyClass)? = {
        guard
            dlopen(frameworkPath, RTLD_NOW) != nil,
            let configuration = NSClassFromString("MBAssessmentModeConfiguration"),
            let assertion = NSClassFromString("MBAssessmentModeAssertion"),
            configuration.instancesRespond(to: configureSelector),
            assertion.instancesRespond(to: activateSelector),
            assertion.instancesRespond(to: invalidateSelector)
        else {
            return nil
        }
        return (configuration, assertion)
    }()

    /// Serializes the holder, on the main thread (see the type's documentation).
    private let queue = DispatchQueue(label: "AssessmentAssertionHolder.queue", target: .main)

    private let logger = Logger(category: "AssessmentAssertionHolder")

    /// The live assertions, by identifier.
    private var assertions = [UInt64: AnyObject]()

    /// The session that asked for each live assertion, by identifier.
    private var owners = [UInt64: UUID]()

    /// The activations MenuBarAgent has not answered yet, by the identifier each will have.
    ///
    /// Both the completion handler and the timeout end an activation, and only the first of
    /// them finds it here: removing the entry is what makes the answer one-shot. This takes
    /// the place of the lock-guarded `OneShot` the app used, as everything here runs on
    /// `queue`.
    private var pending = [UInt64: PendingActivation]()

    /// The identifier the next assertion gets.
    ///
    /// Identifiers only ever increase. They start at a random value, so an identifier the app
    /// kept from an earlier run of the service does not name a new assertion.
    private var nextID = UInt64.random(in: 1...(UInt64.max / 2))

    private init() { }

    /// Activates an assertion that keeps only the given applications' items on the bar.
    ///
    /// `reply` is called on the main thread, once MenuBarAgent has answered or the timeout has
    /// passed, with the identifier of the live assertion or with why there is none.
    func activate(
        allowedBundleIDs: [String],
        for client: UUID,
        reply: @escaping (MenuBarItemService.Response) -> Void
    ) {
        queue.asyncAndWait {
            startActivation(allowedBundleIDs: allowedBundleIDs, client: client, reply: reply)
        }
    }

    /// Releases the assertion with the given identifier if the given session holds it, and
    /// returns once it has been released.
    func invalidate(id: UInt64, for client: UUID) {
        queue.asyncAndWait {
            release(id: id, client: client)
        }
    }

    /// Releases every assertion the given session holds and abandons its activations.
    func sessionEnded(_ client: UUID) {
        queue.asyncAndWait {
            releaseAll(ownedBy: client)
        }
    }

    // MARK: Private

    private func startActivation(
        allowedBundleIDs: [String],
        client: UUID,
        reply: @escaping (MenuBarItemService.Response) -> Void
    ) {
        guard
            let classes = Self.classes,
            let configuration = (classes.configuration.alloc() as AnyObject)
                .perform(Self.configureSelector, with: Self.systemItems, with: allowedBundleIDs as NSArray)?
                .takeUnretainedValue(),
            let assertion = (classes.assertion.alloc() as AnyObject)
                .perform(NSSelectorFromString("init"))?
                .takeUnretainedValue()
        else {
            let failure = Failure.unavailable
            logger.error("Could not activate an assertion: \(failure, privacy: .public)")
            reply(.concealmentFailed(reason: failure.description))
            return
        }
        let id = nextID
        nextID += 1
        pending[id] = PendingActivation(assertion: assertion, client: client, reply: reply)
        // MenuBarAgent answers on a queue of its own choosing.
        let completion: @convention(block) (Any?) -> Void = { [self] error in
            let rejection = error.map { String(describing: $0) }
            queue.async {
                self.finishActivation(id: id, rejection: rejection)
            }
        }
        _ = assertion.perform(Self.activateSelector, with: configuration, with: completion)
        queue.asyncAfter(deadline: .now() + Self.timeout) { [self] in
            timeOutActivation(id: id)
        }
    }

    private func finishActivation(id: UInt64, rejection: String?) {
        guard let activation = pending.removeValue(forKey: id) else {
            // The timeout ended this activation first, or its session went away.
            logger.notice("MenuBarAgent answered activation \(id, privacy: .public) after it was abandoned")
            return
        }
        if let rejection {
            _ = activation.assertion.perform(Self.invalidateSelector)
            let failure = Failure.rejected(rejection)
            logger.error("Could not activate assertion \(id, privacy: .public): \(failure, privacy: .public)")
            activation.reply(.concealmentFailed(reason: failure.description))
            return
        }
        if assertions.isEmpty {
            // Keeps launchd from ending the service for being idle while it holds assertions.
            xpc_transaction_begin()
        }
        assertions[id] = activation.assertion
        owners[id] = activation.client
        logger.debug("Activated assertion \(id, privacy: .public), \(self.assertions.count, privacy: .public) live")
        activation.reply(.concealmentActivated(id: id))
    }

    private func timeOutActivation(id: UInt64) {
        guard let activation = pending.removeValue(forKey: id) else {
            return
        }
        _ = activation.assertion.perform(Self.invalidateSelector)
        let failure = Failure.timedOut
        logger.error("Could not activate assertion \(id, privacy: .public): \(failure, privacy: .public)")
        activation.reply(.concealmentFailed(reason: failure.description))
    }

    private func release(id: UInt64, client: UUID) {
        guard owners[id] == client, let assertion = assertions.removeValue(forKey: id) else {
            logger.notice("Asked to release assertion \(id, privacy: .public), which the session does not hold")
            return
        }
        owners[id] = nil
        _ = assertion.perform(Self.invalidateSelector)
        logger.debug("Released assertion \(id, privacy: .public), \(self.assertions.count, privacy: .public) live")
        if assertions.isEmpty {
            xpc_transaction_end()
        }
    }

    private func releaseAll(ownedBy client: UUID) {
        var abandoned = 0
        for (id, activation) in pending where activation.client == client {
            pending[id] = nil
            _ = activation.assertion.perform(Self.invalidateSelector)
            abandoned += 1
        }
        let owned = owners.filter { $0.value == client }.map(\.key)
        for id in owned {
            release(id: id, client: client)
        }
        logger.debug("Session ended: released \(owned.count, privacy: .public) assertions, abandoned \(abandoned, privacy: .public) activations")
    }
}

//
//  ServiceConcealmentBackend27.swift
//  Ice
//

import Foundation
import OSLog

/// Activates and releases assessment-mode assertions through the `MenuBarItemService` XPC
/// service, which holds them on Ice's behalf.
///
/// The service holds the assertions on Ice's behalf (`AssessmentAssertionHolder`). Measured on
/// macOS 27.0 (2026-10-02), a holder's own items are NOT dropped, so this is a structural
/// choice (assertions outlive Ice's main-thread stalls), not a requirement.
@available(macOS 27.0, *)
@MainActor
final class ServiceConcealmentBackend27: ConcealmentBackend27 {
    enum Failure: Error, CustomStringConvertible {
        /// The request did not reach the service, or its answer did not come back.
        case unavailable(String)
        /// The service could not activate the assertion, for the given reason.
        case rejected(String)
        /// The service did not answer in time.
        case timedOut
        /// The service answered with something other than an activation's outcome.
        case unexpectedResponse(String)

        var description: String {
            switch self {
            case .unavailable(let reason): "The item service is unavailable: \(reason)"
            case .rejected(let reason): reason
            case .timedOut: "The item service did not answer within 5 seconds"
            case .unexpectedResponse(let response): "The item service answered with \(response)"
            }
        }
    }

    /// An assertion the service holds.
    private final class Token: ConcealmentToken27 {
        /// The service's identifier for the assertion.
        let id: UInt64

        /// The number of the session the service holds the assertion for
        /// (see `MenuBarItemService.Connection.Reply.session`).
        let session: UInt64

        init(id: UInt64, session: UInt64) {
            self.id = id
            self.session = session
        }
    }

    /// How long the service has to answer an activation. The service gives MenuBarAgent
    /// 3 seconds, so this covers a service that is slow to launch or does not answer at all.
    private static let timeout = DispatchTimeInterval.seconds(5)

    private let logger = Logger(category: "ServiceConcealmentBackend27")

    /// The number of releases sent that the service has not answered yet.
    private var unansweredInvalidations = 0

    /// Callers waiting for every release to be answered (see `invalidationsAnswered(within:)`).
    private var invalidationWaiters = [UUID: CheckedContinuation<Void, Never>]()

    /// Whether the item service is part of the app.
    ///
    /// This checks that the service's bundle is in `Contents/XPCServices`, nothing more.
    /// Whether this build of macOS offers the private `MenuBarClientCore` assertions is known
    /// to the service alone: when it does not, the service answers each activation with the
    /// reason, and the failed activation is logged.
    static var isAvailable: Bool {
        let service = Bundle.main.bundleURL.appending(path: "Contents/XPCServices/MenuBarItemService.xpc")
        return FileManager.default.fileExists(atPath: service.path(percentEncoded: false))
    }

    /// The numbers of the item service's sessions that have been cancelled, after which the
    /// assertions held for them are gone (see `MenuBarItemService.Connection.sessionCancellations`).
    var serviceSessionCancellations: AsyncStream<UInt64> {
        MenuBarItemService.Connection.shared.sessionCancellations
    }

    func activate(allowedBundleIDs: [String]) async throws -> ConcealmentToken27 {
        let reply = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MenuBarItemService.Connection.Reply, any Error>) in
            // The reply and the timeout share the continuation, and only the first takes it.
            let pending = OSAllocatedUnfairLock<CheckedContinuation<MenuBarItemService.Connection.Reply, any Error>?>(
                initialState: continuation
            )
            let request = MenuBarItemService.Request.activateConcealment(allowedBundleIDs: allowedBundleIDs)
            MenuBarItemService.Connection.shared.send(request) { [logger] result in
                if let continuation = pending.withLock({ $0.take() }) {
                    continuation.resume(with: result.mapError { Failure.unavailable(String(describing: $0)) })
                    return
                }
                // The activation was given up for lost, so an assertion it produced after all is
                // released at once rather than left concealing items nobody tracks.
                guard case .success(let reply) = result, case .concealmentActivated(let id) = reply.response else {
                    return
                }
                logger.notice("The item service activated assertion \(id, privacy: .public) after the timeout; releasing it")
                MenuBarItemService.Connection.shared.send(.invalidateConcealment(id: id)) { result in
                    if case .failure(let error) = result {
                        logger.error("Could not release late assertion \(id, privacy: .public): \(error, privacy: .public)")
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) {
                pending.withLock { $0.take() }?.resume(throwing: Failure.timedOut)
            }
        }
        switch reply.response {
        case .concealmentActivated(let id):
            return Token(id: id, session: reply.session)
        case .concealmentFailed(let reason):
            throw Failure.rejected(reason)
        default:
            throw Failure.unexpectedResponse(String(describing: reply.response))
        }
    }

    /// Asks the service to release an assertion, without waiting for it to answer.
    ///
    /// ``invalidationsAnswered(within:)`` waits for the answers.
    func invalidate(_ token: ConcealmentToken27) {
        guard let token = token as? Token else {
            logger.fault("Asked to release an assertion the item service does not hold")
            return
        }
        let id = token.id
        unansweredInvalidations += 1
        MenuBarItemService.Connection.shared.send(.invalidateConcealment(id: id)) { [weak self, logger] result in
            switch result.map(\.response) {
            case .success(.concealmentInvalidated):
                break
            case .success(let response):
                logger.error("The item service answered the release of assertion \(id, privacy: .public) with \(String(describing: response), privacy: .public)")
            case .failure(let error):
                logger.error("Could not release assertion \(id, privacy: .public): \(error, privacy: .public)")
            }
            Task { @MainActor [weak self] in
                self?.invalidationAnswered()
            }
        }
    }

    /// Returns once the service has answered every release sent so far, which it does after
    /// releasing the assertion, or once `timeout` has passed.
    func invalidationsAnswered(within timeout: Duration) async {
        guard unansweredInvalidations > 0 else {
            return
        }
        let waiter = UUID()
        let timer = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                // Cancelled because every release was answered first.
                return
            }
            // Every release may have been answered while this woke up.
            guard let self, let continuation = invalidationWaiters.removeValue(forKey: waiter) else {
                return
            }
            logger.notice("The item service did not answer every release within \(timeout.description, privacy: .public)")
            continuation.resume()
        }
        await withCheckedContinuation { continuation in
            invalidationWaiters[waiter] = continuation
        }
        timer.cancel()
    }

    /// Whether the given assertion was held for the given cancelled session, or for an earlier
    /// one, and so went away with it.
    func isLost(_ token: ConcealmentToken27, cancelledSession: UInt64) -> Bool {
        guard let token = token as? Token else {
            return false
        }
        return token.session <= cancelledSession
    }

    // MARK: Private

    private func invalidationAnswered() {
        unansweredInvalidations -= 1
        guard unansweredInvalidations == 0 else {
            return
        }
        let waiters = Array(invalidationWaiters.values)
        invalidationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

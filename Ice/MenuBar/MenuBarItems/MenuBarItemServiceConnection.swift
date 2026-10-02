//
//  MenuBarItemServiceConnection.swift
//  Ice
//

import Foundation
import OSLog

// MARK: - MenuBarItemService.Connection

@available(macOS 26.0, *)
extension MenuBarItemService {
    /// A connection to the `MenuBarItemService` XPC service.
    final class Connection: Sendable {
        /// A response, with the session that carried it.
        struct Reply: Sendable {
            /// The service's response.
            let response: Response

            /// The number of the session that carried the response.
            ///
            /// The connection numbers its sessions from 1, in the order it creates them.
            let session: UInt64
        }

        /// The shared connection.
        static let shared = Connection()

        /// The numbers of the sessions that have been cancelled.
        ///
        /// A session is cancelled when the service exits or crashes, and whatever the service
        /// held for it is gone. The next request opens a new session with a higher number. The
        /// stream is meant for one consumer, and keeps only the latest number while nobody is
        /// waiting for one.
        let sessionCancellations: AsyncStream<UInt64>

        /// The connection's underlying session.
        private let session: Session

        /// The connection's target queue.
        private let queue: DispatchQueue

        /// The connection's logger.
        private let logger: Logger

        /// Creates a new connection.
        private init() {
            let queue = DispatchQueue.targetingGlobal(
                label: "MenuBarItemService.Connection.queue",
                qos: .userInteractive,
                attributes: .concurrent
            )
            let logger = Logger(category: "MenuBarItemService.Connection")
            let (cancellations, continuation) = AsyncStream.makeStream(
                of: UInt64.self,
                bufferingPolicy: .bufferingNewest(1)
            )
            self.session = Session(queue: queue, logger: logger) { number in
                continuation.yield(number)
            }
            self.sessionCancellations = cancellations
            self.queue = queue
            self.logger = logger
        }

        /// Starts the connection.
        func start() async {
            logger.debug("Starting MenuBarItemService connection")

            await withCheckedContinuation { continuation in
                guard let response = session.send(request: .start) else {
                    logger.error("Start request returned nil")
                    continuation.resume()
                    return
                }
                if case .start = response {
                    continuation.resume()
                } else {
                    logger.error("Start request returned invalid response \(String(describing: response))")
                    continuation.resume()
                }
            }
        }

        /// Returns the source process identifier for the given window.
        func sourcePID(for window: WindowInfo) async -> pid_t? {
            await withCheckedContinuation { continuation in
                guard let response = session.send(request: .sourcePID(window)) else {
                    logger.error("Source PID request returned nil")
                    continuation.resume(returning: nil)
                    return
                }
                if case .sourcePID(let pid) = response {
                    continuation.resume(returning: pid)
                } else {
                    logger.error("Source PID request returned invalid response \(String(describing: response))")
                    continuation.resume(returning: nil)
                }
            }
        }

        /// Sends the given request to the service and passes the response, or the error that
        /// kept it from arriving, to `replyHandler`.
        ///
        /// Unlike `start()` and `sourcePID(for:)`, this does not hold the session while the
        /// service works on the request, only while the request is handed over, so a request
        /// the service answers late does not hold up the others. `replyHandler` is called on
        /// the connection's queue, or before this returns if the request could not be sent.
        func send(_ request: Request, replyHandler: @escaping @Sendable (Result<Reply, any Error>) -> Void) {
            session.send(request, replyHandler: replyHandler)
        }
    }
}

// MARK: - MenuBarItemService.Session

@available(macOS 26.0, *)
extension MenuBarItemService {
    /// A wrapper around an XPC session.
    private final class Session: Sendable {
        /// A session's underlying storage.
        private final class Storage: @unchecked Sendable {
            private let name = MenuBarItemService.name
            private var session: XPCSession?
            /// The number of the latest session (see `Connection.Reply.session`).
            private var sessionNumber: UInt64 = 0
            private let queue: DispatchQueue
            private let logger: Logger
            /// Called with the number of each session that is cancelled.
            private let onCancel: @Sendable (UInt64) -> Void

            init(queue: DispatchQueue, logger: Logger, onCancel: @escaping @Sendable (UInt64) -> Void) {
                self.queue = queue
                self.logger = logger
                self.onCancel = onCancel
            }

            private func getOrCreateSession() throws -> XPCSession {
                if let session {
                    return session
                }
                sessionNumber += 1
                let number = sessionNumber
                let session = try XPCSession(xpcService: name, options: .inactive) { [weak self] error in
                    guard let self else {
                        return
                    }
                    logger.warning("Session was cancelled with error \(error.localizedDescription)")
                    self.session = nil
                    // After the session is cleared, so a request sent in response opens a new one.
                    onCancel(number)
                }
                session.setPeerRequirement(.isFromSameTeam())
                session.setTargetQueue(queue)
                try session.activate()
                self.session = session
                return session
            }

            func cancel(reason: String) {
                guard let session = session.take() else {
                    return
                }
                session.cancel(reason: reason)
            }

            func send(request: Request) -> Response? {
                do {
                    let session = try getOrCreateSession()
                    let reply = try session.sendSync(request)
                    return try reply.decode(as: Response.self)
                } catch {
                    logger.error("Session failed with error \(error)")
                    return nil
                }
            }

            func send(
                _ request: Request,
                replyHandler: @escaping @Sendable (Result<Connection.Reply, any Error>) -> Void
            ) throws {
                let session = try getOrCreateSession()
                let number = sessionNumber
                try session.send(request) { (result: Result<Response, any Error>) in
                    replyHandler(result.map { Connection.Reply(response: $0, session: number) })
                }
            }
        }

        /// Protected storage for the underlying XPC session.
        private let storage: OSAllocatedUnfairLock<Storage>

        /// The session's target queue.
        private let queue: DispatchQueue

        /// The session's logger.
        private let logger: Logger

        /// Creates a new session that calls `onCancel` with the number of each underlying
        /// session that is cancelled.
        init(queue: DispatchQueue, logger: Logger, onCancel: @escaping @Sendable (UInt64) -> Void) {
            self.storage = OSAllocatedUnfairLock(
                initialState: Storage(queue: queue, logger: logger, onCancel: onCancel)
            )
            self.queue = queue
            self.logger = logger
        }

        deinit {
            cancel(reason: "Session deinitialized")
        }

        /// Cancels the session.
        func cancel(reason: String) {
            storage.withLock { $0.cancel(reason: reason) }
        }

        /// Sends the given request to the service and returns the response.
        func send(request: Request) -> Response? {
            storage.withLock { $0.send(request: request) }
        }

        /// Sends the given request to the service, holding the lock only while it is handed
        /// over, and passes the response or the error to `replyHandler`.
        func send(
            _ request: Request,
            replyHandler: @escaping @Sendable (Result<Connection.Reply, any Error>) -> Void
        ) {
            do {
                try storage.withLock { try $0.send(request, replyHandler: replyHandler) }
            } catch {
                logger.error("Session failed with error \(error)")
                replyHandler(.failure(error))
            }
        }
    }
}

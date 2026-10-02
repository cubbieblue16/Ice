//
//  Listener.swift
//  MenuBarItemService
//

import Foundation
import OSLog
import XPC

/// A wrapper around an XPC listener object.
final class Listener {
    /// The shared listener.
    static let shared = Listener()

    /// The service name.
    private let name = MenuBarItemService.name

    /// The underlying XPC listener object.
    private var listener: XPCListener?

    /// Creates the shared listener.
    private init() { }

    deinit {
        cancel()
    }

    /// Handles a message received through the session identified by `client`.
    private func handleMessage(_ message: XPCReceivedMessage, from client: UUID) -> MenuBarItemService.Response? {
        do {
            let request = try message.decode(as: MenuBarItemService.Request.self)
            switch request {
            case .start:
                Logger.default.debug("Listener received start request")
                return .start
            case .sourcePID(let window):
                let pid = SourcePIDCache.shared.pid(for: window)
                return .sourcePID(pid)
            case .activateConcealment(let allowedBundleIDs):
                return activateConcealment(allowedBundleIDs: allowedBundleIDs, message: message, client: client)
            case .invalidateConcealment(let id):
                return invalidateConcealment(id: id, client: client)
            }
        } catch {
            Logger.default.error("Listener failed to handle message with error \(error)")
            return nil
        }
    }

    /// Activates an assessment-mode assertion for the session identified by `client`.
    ///
    /// MenuBarAgent answers an activation after this returns, so the reply is deferred: this
    /// returns nil, and the holder sends the reply later, on the main thread, with
    /// `XPCReceivedMessage.reply(_:)`. The XPC overlay documents this in
    /// `XPCSession.setIncomingMessageHandler(_:)`: if a reply is expected, the handler can
    /// return nil and send the reply asynchronously with `XPCReceivedMessage.reply()`, except
    /// for a synchronous message, which would need `handoffReply(to:_:)`. The app sends this
    /// request with `XPCSession.send(_:replyHandler:)`, so a synchronous one is refused.
    private func activateConcealment(
        allowedBundleIDs: [String],
        message: XPCReceivedMessage,
        client: UUID
    ) -> MenuBarItemService.Response? {
        guard #available(macOS 27.0, *) else {
            return .concealmentFailed(reason: Self.concealmentUnsupported)
        }
        guard !message.isSync else {
            Logger.default.error("Listener refused a synchronous concealment request")
            return .concealmentFailed(reason: "Concealment must be requested asynchronously")
        }
        guard message.expectsReply else {
            // Nobody would learn the assertion's identifier, so it could never be released.
            Logger.default.error("Listener ignored a concealment request that expects no reply")
            return nil
        }
        AssessmentAssertionHolder.shared.activate(allowedBundleIDs: allowedBundleIDs, for: client) { response in
            message.reply(response)
        }
        return nil
    }

    /// Releases an assertion the session identified by `client` holds.
    private func invalidateConcealment(id: UInt64, client: UUID) -> MenuBarItemService.Response {
        guard #available(macOS 27.0, *) else {
            return .concealmentFailed(reason: Self.concealmentUnsupported)
        }
        AssessmentAssertionHolder.shared.invalidate(id: id, for: client)
        return .concealmentInvalidated
    }

    /// Releases the assertions of the session identified by `client`, which has ended.
    private func sessionEnded(_ client: UUID) {
        if #available(macOS 27.0, *) {
            AssessmentAssertionHolder.shared.sessionEnded(client)
        }
    }

    /// Why concealment requests fail before macOS 27.
    private static let concealmentUnsupported = "Concealment needs macOS 27 or later"

    /// Activates the listener without checking if it is already active,
    /// with the requirement that session peers must be signed with the
    /// same team identifier as the service process.
    @available(macOS 26.0, *)
    private func uncheckedActivateWithSameTeamRequirement() throws {
        listener = try XPCListener(service: name, requirement: .isFromSameTeam()) { [weak self] request in
            let client = UUID()
            return request.accept { message in
                self?.handleMessage(message, from: client)
            } cancellationHandler: { _ in
                self?.sessionEnded(client)
            }
        }
    }

    /// Activates the listener without checking if it is already active.
    private func uncheckedActivate() throws {
        listener = try XPCListener(service: name) { [weak self] request in
            let client = UUID()
            return request.accept { message in
                self?.handleMessage(message, from: client)
            } cancellationHandler: { _ in
                self?.sessionEnded(client)
            }
        }
    }

    /// Activates the listener.
    func activate() {
        guard listener == nil else {
            Logger.default.notice("Listener is already active")
            return
        }

        Logger.default.debug("Activating listener")

        do {
            if #available(macOS 26.0, *) {
                try uncheckedActivateWithSameTeamRequirement()
            } else {
                try uncheckedActivate()
            }
        } catch {
            Logger.default.error("Failed to activate listener with error \(error)")
        }
    }

    /// Cancels the listener.
    func cancel() {
        Logger.default.debug("Canceling listener")
        listener.take()?.cancel()
    }
}

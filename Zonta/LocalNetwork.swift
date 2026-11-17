import Foundation
import Network

/// Local Network Privacy (TCC) hides a denied LAN socket as
/// NSURLErrorNotConnectedToInternet. A menu-bar app with no window often never
/// gets the prompt, and a Bonjour browse is what makes the system ask.
///
/// The browse exists only to register that grant once. Running it on every
/// launch makes every development build pop the same dialog again, so it is
/// gated by a UserDefaults flag. `requestAccessAgain()` is available in
/// Settings when the grant was denied or reset.
enum LocalNetwork {
    private static var browser: NWBrowser?
    private static let probeDoneKey = "zonta.localNetwork.probeDone"

    @MainActor
    static func requestAccess() {
        guard !UserDefaults.standard.bool(forKey: probeDoneKey) else { return }
        UserDefaults.standard.set(true, forKey: probeDoneKey)

        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_zonta._tcp", domain: nil), using: params)
        browser.stateUpdateHandler = { _ in }
        browser.browseResultsChangedHandler = { _, _ in }
        browser.start(queue: .main)
        self.browser = browser
        AppLog.shared.info("Requested Local Network access", subsystem: "Permissions")
    }

    /// Manual escape hatch: call from Settings if LAN access was denied.
    @MainActor
    static func requestAccessAgain() {
        UserDefaults.standard.set(false, forKey: probeDoneKey)
        requestAccess()
    }

    /// One throwaway connection so TCC records the bundle against the LAN.
    static func poke(host: String, port: UInt16) {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? 80,
            using: .tcp
        )
        connection.stateUpdateHandler = { state in
            if case .ready = state { connection.cancel() }
            if case .failed = state { connection.cancel() }
            if case .waiting = state { connection.cancel() }
        }
        connection.start(queue: .main)
    }
}

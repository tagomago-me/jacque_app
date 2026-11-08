import Foundation
import WatchConnectivity

/// Watch: envia bpm ao iPhone e recebe comandos de iniciar/encerrar.
final class WatchBridge: NSObject, WCSessionDelegate {
    var aoComando: ((String) -> Void)?

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func enviarBpm(_ bpm: Double, _ quando: Date) {
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        let m: [String: Any] = ["bpm": bpm, "t": quando.timeIntervalSince1970]
        if s.isReachable { s.sendMessage(m, replyHandler: nil, errorHandler: nil) }
        else { s.transferUserInfo(m) }
    }

    func session(_ s: WCSession, activationDidCompleteWith st: WCSessionActivationState, error: Error?) {}
    private func tratar(_ m: [String: Any]) {
        if let c = m["comando"] as? String { DispatchQueue.main.async { self.aoComando?(c) } }
    }
    func session(_ s: WCSession, didReceiveMessage m: [String: Any]) { tratar(m) }
    func session(_ s: WCSession, didReceiveUserInfo u: [String: Any] = [:]) { tratar(u) }
}

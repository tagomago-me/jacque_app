import Foundation
import WatchConnectivity
import Observation

/// iPhone: recebe bpm do Watch, envia ao gateway e repassa o comando de início/fim ao Watch.
@Observable
final class PhoneBridge: NSObject, WCSessionDelegate {
    var bpm: Int = 0
    var amostras = 0
    var ultimaAmostra: Date?
    var gateway = "—"
    var treinoAtivo = false
    var watchAlcancavel = false

    private var sessionId = UUID().uuidString
    private var ultimoComando = ""

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        Task { await laco() }
    }

    // MARK: Gateway
    private func requisicao(_ caminho: String, metodo: String = "GET", corpo: Data? = nil) -> URLRequest? {
        guard let url = URL(string: Secrets.gatewayBase + "/jacque/treino" + caminho) else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 10)
        r.httpMethod = metodo
        r.setValue("Bearer " + Secrets.watchToken, forHTTPHeaderField: "Authorization")
        if let corpo { r.httpBody = corpo; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return r
    }

    private func enviar(bpm: Double, quando: Date) async {
        let corpo = try? JSONSerialization.data(withJSONObject: [
            "sessionId": sessionId, "bpm": Int(bpm.rounded()),
            "t": ISO8601DateFormatter().string(from: quando), "estado": "serie",
        ])
        guard let r = requisicao("/bpm", metodo: "POST", corpo: corpo) else { return }
        do {
            let (_, resp) = try await URLSession.shared.data(for: r)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            await MainActor.run { self.gateway = code == 200 ? "ok" : "erro \(code)" }
        } catch {
            await MainActor.run { self.gateway = "sem rede" }
        }
    }

    /// Consulta o estado do modo treino a cada 15 s e comanda o Watch.
    private func laco() async {
        while true {
            if let r = requisicao("/estado") {
                if let (dados, _) = try? await URLSession.shared.data(for: r),
                   let j = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
                   let ativo = j["ativo"] as? Bool {
                    await MainActor.run { self.treinoAtivo = ativo }
                    let cmd = ativo ? "iniciar" : "fim"
                    if cmd != ultimoComando {
                        ultimoComando = cmd
                        if ativo { sessionId = UUID().uuidString }
                        mandarAoWatch(["comando": cmd])
                    }
                }
            }
            try? await Task.sleep(for: .seconds(15))
        }
    }

    func mandarAoWatch(_ msg: [String: Any]) {
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        if s.isReachable { s.sendMessage(msg, replyHandler: nil, errorHandler: nil) }
        else { s.transferUserInfo(msg) }
    }

    // MARK: WCSessionDelegate
    func session(_ s: WCSession, activationDidCompleteWith st: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.watchAlcancavel = s.isReachable }
    }
    func sessionReachabilityDidChange(_ s: WCSession) {
        DispatchQueue.main.async { self.watchAlcancavel = s.isReachable }
    }
    func sessionDidBecomeInactive(_ s: WCSession) {}
    func sessionDidDeactivate(_ s: WCSession) { s.activate() }

    private func tratar(_ m: [String: Any]) {
        guard let v = m["bpm"] as? Double else { return }
        let t = Date(timeIntervalSince1970: (m["t"] as? Double) ?? Date().timeIntervalSince1970)
        DispatchQueue.main.async {
            self.bpm = Int(v.rounded()); self.amostras += 1; self.ultimaAmostra = t
        }
        Task { await enviar(bpm: v, quando: t) }
    }
    func session(_ s: WCSession, didReceiveMessage m: [String: Any]) { tratar(m) }
    func session(_ s: WCSession, didReceiveUserInfo u: [String: Any] = [:]) { tratar(u) }
}

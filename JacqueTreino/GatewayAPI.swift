import Foundation

struct Coluna: Decodable, Hashable { let nome: String; let tipo: String; let anulavel: Bool? }

struct TabelaInfo: Decodable, Identifiable, Hashable {
    let schema: String; let tabela: String; let tipo: String
    let linhas: Int?; let pk: [String]; let colunas: [Coluna]
    var id: String { schema + "." + tabela }
}
struct SchemaResp: Decodable { let tabelas: [TabelaInfo] }

enum Valor: Decodable, CustomStringConvertible {
    case vazio, texto(String), numero(Double), booleano(Bool)
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if c.decodeNil() { self = .vazio }
        else if let b = try? c.decode(Bool.self) { self = .booleano(b) }
        else if let n = try? c.decode(Double.self) { self = .numero(n) }
        else { self = .texto((try? c.decode(String.self)) ?? "") }
    }
    var description: String {
        switch self {
        case .vazio: return "—"
        case .texto(let s): return s
        case .booleano(let b): return b ? "sim" : "não"
        case .numero(let n): return n == n.rounded() && abs(n) < 1e12 ? String(Int(n)) : String(format: "%.2f", n)
        }
    }
}

struct TabelaResp: Decodable { let tabela: String; let colunas: [Coluna]; let total: Int; let linhas: [[Valor]] }

struct Regra: Decodable, Identifiable {
    let id: String; let tabela: String; let descricao: String
    let problemas: Int?; let colunas: [String]?; let amostra: [[Valor]]?; let erro: String?
}
struct VerifResp: Decodable { let regras: [Regra] }

enum GatewayErro: LocalizedError {
    case http(Int, String)
    var errorDescription: String? { if case .http(let c, let m) = self { return "Gateway \(c): \(m)" }; return nil }
}

enum Gateway {
    static func get<T: Decodable>(_ caminho: String, _ query: [URLQueryItem] = []) async throws -> T {
        var c = URLComponents(string: Secrets.gatewayBase + caminho)!
        c.queryItems = query.isEmpty ? nil : query
        var r = URLRequest(url: c.url!)
        r.setValue("Bearer \(Secrets.watchToken)", forHTTPHeaderField: "Authorization")
        r.timeoutInterval = 40
        let (d, resp) = try await URLSession.shared.data(for: r)
        let codigo = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard codigo == 200 else { throw GatewayErro.http(codigo, String(data: d, encoding: .utf8)?.prefix(160).description ?? "") }
        return try JSONDecoder().decode(T.self, from: d)
    }
}

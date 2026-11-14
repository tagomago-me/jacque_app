import SwiftUI

struct BancoView: View {
    @State private var tabelas: [TabelaInfo] = []
    @State private var erro: String?
    @State private var busca = ""
    @State private var carregando = false

    private var filtradas: [TabelaInfo] {
        busca.isEmpty ? tabelas : tabelas.filter { $0.id.localizedCaseInsensitiveContains(busca) }
    }
    private var grupos: [(String, [TabelaInfo])] {
        Dictionary(grouping: filtradas, by: \.schema).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let erro { Text(erro).foregroundStyle(.red) }
                ForEach(grupos, id: \.0) { schema, itens in
                    Section(schema) {
                        ForEach(itens) { t in
                            NavigationLink(value: t) {
                                HStack {
                                    Image(systemName: t.tipo == "view" ? "eye" : "tablecells")
                                    Text(t.tabela)
                                    Spacer()
                                    if let n = t.linhas { Text("\(n)").foregroundStyle(.secondary).monospacedDigit() }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Banco")
            .navigationDestination(for: TabelaInfo.self) { TabelaView(info: $0) }
            .searchable(text: $busca, prompt: "Buscar tabela")
            .overlay { if carregando && tabelas.isEmpty { ProgressView() } }
            .refreshable { await carregar() }
            .task { if tabelas.isEmpty { await carregar() } }
        }
    }

    private func carregar() async {
        carregando = true; defer { carregando = false }
        do { tabelas = (try await Gateway.get("/jacque/db/schema") as SchemaResp).tabelas; erro = nil }
        catch { erro = error.localizedDescription }
    }
}

struct TabelaView: View {
    let info: TabelaInfo
    @State private var resp: TabelaResp?
    @State private var erro: String?
    @State private var offset = 0
    @State private var colFiltro: String?
    @State private var texto = ""
    @State private var ordem: String?
    private let pagina = 25

    var body: some View {
        List {
            Section {
                if info.pk.isEmpty == false { Text("Chave: " + info.pk.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Menu(colFiltro ?? "coluna") {
                        ForEach(info.colunas, id: \.nome) { c in Button(c.nome) { colFiltro = c.nome } }
                    }
                    TextField("contém…", text: $texto).textFieldStyle(.roundedBorder).submitLabel(.search)
                        .onSubmit { offset = 0; Task { await carregar() } }
                }
                Menu("Ordenar: " + (ordem ?? "padrão")) {
                    Button("padrão") { ordem = nil; offset = 0; Task { await carregar() } }
                    ForEach(info.colunas, id: \.nome) { c in
                        Button(c.nome + " ↑") { ordem = c.nome; offset = 0; Task { await carregar() } }
                        Button(c.nome + " ↓") { ordem = "-" + c.nome; offset = 0; Task { await carregar() } }
                    }
                }
            }
            if let erro { Text(erro).foregroundStyle(.red) }
            if let r = resp {
                Section("\(r.total) linhas · \(offset + 1)–\(min(offset + pagina, r.total))") {
                    ForEach(r.linhas.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(r.colunas.indices, id: \.self) { j in
                                HStack(alignment: .top) {
                                    Text(r.colunas[j].nome).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                                    Text(r.linhas[i][j].description).font(.callout).textSelection(.enabled)
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                }
                Section {
                    HStack {
                        Button("Anterior") { offset = max(0, offset - pagina); Task { await carregar() } }.disabled(offset == 0)
                        Spacer()
                        Button("Próxima") { offset += pagina; Task { await carregar() } }.disabled(offset + pagina >= r.total)
                    }
                }
            }
        }
        .navigationTitle(info.tabela)
        .navigationBarTitleDisplayMode(.inline)
        .task { await carregar() }
    }

    private func carregar() async {
        var q = [URLQueryItem(name: "nome", value: info.id), URLQueryItem(name: "limite", value: "\(pagina)"), URLQueryItem(name: "offset", value: "\(offset)")]
        if let o = ordem { q.append(URLQueryItem(name: "ordem", value: o)) }
        if let c = colFiltro, !texto.isEmpty,
           let d = try? JSONSerialization.data(withJSONObject: [["col": c, "op": "contem", "val": texto]]),
           let s = String(data: d, encoding: .utf8) { q.append(URLQueryItem(name: "filtros", value: s)) }
        do { resp = try await Gateway.get("/jacque/db/tabela", q); erro = nil }
        catch { erro = error.localizedDescription }
    }
}

struct VerificarView: View {
    @State private var regras: [Regra] = []
    @State private var erro: String?
    @State private var carregando = false

    var body: some View {
        NavigationStack {
            List {
                if let erro { Text(erro).foregroundStyle(.red) }
                ForEach(regras) { r in
                    NavigationLink(value: r.id) {
                        HStack {
                            Image(systemName: icone(r)).foregroundStyle(cor(r))
                            VStack(alignment: .leading) {
                                Text(r.descricao)
                                Text(r.tabela).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let n = r.problemas { Text("\(n)").monospacedDigit().bold().foregroundStyle(cor(r)) }
                        }
                    }
                }
            }
            .navigationTitle("Verificar")
            .navigationDestination(for: String.self) { id in
                if let r = regras.first(where: { $0.id == id }) { RegraView(regra: r) }
            }
            .overlay { if carregando && regras.isEmpty { ProgressView() } }
            .toolbar { Button("Rodar") { Task { await carregar() } } }
            .refreshable { await carregar() }
            .task { if regras.isEmpty { await carregar() } }
        }
    }

    private func icone(_ r: Regra) -> String { r.erro != nil ? "exclamationmark.triangle" : (r.problemas ?? 0) == 0 ? "checkmark.circle.fill" : "xmark.octagon.fill" }
    private func cor(_ r: Regra) -> Color { r.erro != nil ? .orange : (r.problemas ?? 0) == 0 ? .green : .red }

    private func carregar() async {
        carregando = true; defer { carregando = false }
        do { regras = (try await Gateway.get("/jacque/db/verificar") as VerifResp).regras; erro = nil }
        catch { erro = error.localizedDescription }
    }
}

struct RegraView: View {
    let regra: Regra
    var body: some View {
        List {
            Section { Text(regra.tabela).font(.caption).foregroundStyle(.secondary) }
            if let e = regra.erro { Text(e).foregroundStyle(.orange) }
            if let cols = regra.colunas, let linhas = regra.amostra {
                Section("\(regra.problemas ?? 0) problemas" + ((regra.problemas ?? 0) > linhas.count ? " (mostrando \(linhas.count))" : "")) {
                    ForEach(linhas.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(cols.indices, id: \.self) { j in
                                HStack(alignment: .top) {
                                    Text(cols[j]).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                                    Text(linhas[i][j].description).font(.callout).textSelection(.enabled)
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(regra.descricao)
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

struct SerieFeita: Decodable, Hashable { let carga: Double?; let reps: Double?; let rir: Double?; let bpm: Double? }
struct ExTreino: Decodable, Identifiable, Hashable {
    let nome: String; let series: Int; let maquina: String?; let assento: String?
    let ultima: String?; let alvo: String; let alvo_carga: Double?; let alvo_reps: Double?; let feito: [SerieFeita]
    var id: String { nome }
}
struct ForaTreino: Decodable, Hashable { let nome: String; let feito: String }
struct SessaoTreino: Decodable {
    let aberta: Bool; let id: String?; let inicio: String?; let grupo: String?; let motivo: String?
    let ultimo_treino: String?; let exercicios: [ExTreino]; let fora: [ForaTreino]; let proximo: String?; let hoje: [String]
}
struct RespTexto: Decodable { let ok: Bool?; let texto: String?; let erro: String? }
struct RespChat: Decodable { let ok: Bool?; let resposta: String?; let erro: String? }

extension Gateway {
    static func post<T: Decodable>(_ caminho: String, _ corpo: [String: Any] = [:], timeout: TimeInterval = 70) async throws -> T {
        var r = URLRequest(url: URL(string: Secrets.gatewayBase + caminho)!)
        r.httpMethod = "POST"
        r.setValue("Bearer \(Secrets.watchToken)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: corpo)
        r.timeoutInterval = timeout
        let (d, _) = try await URLSession.shared.data(for: r)
        return try JSONDecoder().decode(T.self, from: d)
    }
}

func num(_ v: Double?) -> String {
    guard let v else { return "—" }
    return v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
}

/// Treino ao vivo: o mesmo plano e as mesmas séries que a Jacque vê, lidos do plugin.
struct TreinoAoVivoView: View {
    let bpmAtual: Int
    @State private var sessao: SessaoTreino?
    @State private var erro: String?
    @State private var aviso: String?
    @State private var escolhido: ExTreino?
    @State private var ocupado = false

    var body: some View {
        Group {
            if let erro { Text(erro).font(.caption).foregroundStyle(.red) }
            if let s = sessao {
                Section(s.aberta ? "Treino aberto" : "Treino de hoje") {
                    if let g = s.grupo { Text(g).font(.headline) }
                    if let m = s.motivo { Text(m).font(.caption).foregroundStyle(.secondary) }
                    if let p = s.proximo { Label(p, systemImage: "arrow.right.circle").font(.callout) }
                    if let a = aviso { Text(a).font(.caption).foregroundStyle(.green) }
                }
                Section("Exercícios") {
                    ForEach(s.exercicios) { e in
                        Button { escolhido = e } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(e.nome).font(.body).foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(e.feito.count)/\(e.series)").monospacedDigit()
                                        .foregroundStyle(e.feito.count >= e.series ? .green : .secondary)
                                }
                                Text("Hoje: " + e.alvo).font(.caption).foregroundStyle(.secondary)
                                if let u = e.ultima { Text("Última: " + u).font(.caption2).foregroundStyle(.secondary) }
                                if !e.feito.isEmpty {
                                    Text("Feito: " + e.feito.map { num($0.carga) + " kg × " + num($0.reps) }.joined(separator: ", "))
                                        .font(.caption).foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    ForEach(s.fora, id: \.self) { f in
                        VStack(alignment: .leading) { Text(f.nome); Text(f.feito).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    Button("Desfazer última série") { Task { await acao("/jacque/treino/desfaz") } }.disabled(ocupado || !s.aberta)
                    Button("Encerrar treino", role: .destructive) { Task { await acao("/jacque/treino/fim") } }.disabled(ocupado || !s.aberta)
                }
            } else if erro == nil {
                ProgressView()
            }
        }
        .sheet(item: $escolhido) { e in
            SerieSheet(ex: e, bpmAtual: bpmAtual) { texto in aviso = texto; Task { await carregar() } }
        }
        .task {
            while !Task.isCancelled {
                await carregar()
                try? await Task.sleep(for: .seconds(12))
            }
        }
    }

    private func carregar() async {
        do { sessao = try await Gateway.get("/jacque/treino/sessao"); erro = nil }
        catch { erro = error.localizedDescription }
    }

    private func acao(_ caminho: String) async {
        ocupado = true; defer { ocupado = false }
        do {
            let r: RespTexto = try await Gateway.post(caminho)
            aviso = r.texto ?? r.erro
            await carregar()
        } catch { erro = error.localizedDescription }
    }
}

struct SerieSheet: View {
    let ex: ExTreino
    let bpmAtual: Int
    let feito: (String) -> Void
    @Environment(\.dismiss) private var fechar
    @State private var carga = ""
    @State private var reps = ""
    @State private var rir = 0
    @State private var aquecimento = false
    @State private var enviando = false
    @State private var erro: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(ex.nome) {
                    Text("Hoje: " + ex.alvo).font(.callout)
                    HStack { Text("Carga (kg)"); Spacer(); TextField("kg", text: $carga).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90) }
                    HStack { Text("Repetições"); Spacer(); TextField("reps", text: $reps).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90) }
                    Stepper("RIR \(rir)", value: $rir, in: 0...10)
                    Toggle("Aquecimento", isOn: $aquecimento)
                    if bpmAtual > 0 { Text("bpm do Watch: \(bpmAtual)").font(.caption).foregroundStyle(.secondary) }
                }
                if let erro { Text(erro).foregroundStyle(.red) }
            }
            .navigationTitle("Registrar série")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { fechar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Gravar") { Task { await gravar() } }.disabled(enviando || reps.isEmpty) }
            }
            .onAppear {
                let ult = ex.feito.last
                carga = num(ult?.carga ?? ex.alvo_carga).replacingOccurrences(of: "—", with: "")
                reps = ex.alvo_reps.map { num($0) } ?? ""
            }
        }
    }

    private func gravar() async {
        enviando = true; defer { enviando = false }
        var corpo: [String: Any] = ["exercicio": ex.nome, "reps": reps.replacingOccurrences(of: ",", with: "."), "aquecimento": aquecimento]
        if !carga.isEmpty { corpo["carga"] = carga.replacingOccurrences(of: ",", with: ".") }
        if !aquecimento { corpo["rir"] = rir; if bpmAtual > 0 { corpo["bpm"] = bpmAtual } }
        do {
            let r: RespTexto = try await Gateway.post("/jacque/treino/serie", corpo)
            if let e = r.erro { erro = e; return }
            feito(r.texto ?? "Gravado.")
            fechar()
        } catch { erro = error.localizedDescription }
    }
}

struct Fala: Identifiable { let id = UUID(); let minha: Bool; let texto: String }

/// Conversa com a Jacque pelo app, na sessão do treino aberto (ou na sessão do app, fora do treino).
struct ConversaView: View {
    @State private var falas: [Fala] = []
    @State private var texto = ""
    @State private var esperando = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { sv in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(falas) { f in
                                Text(f.texto)
                                    .padding(10)
                                    .background(f.minha ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                                    .frame(maxWidth: .infinity, alignment: f.minha ? .trailing : .leading)
                                    .id(f.id)
                            }
                            if esperando { ProgressView().frame(maxWidth: .infinity, alignment: .leading) }
                        }.padding()
                    }
                    .onChange(of: falas.count) { if let u = falas.last { withAnimation { sv.scrollTo(u.id, anchor: .bottom) } } }
                }
                HStack {
                    TextField("Fala com a Jacque", text: $texto, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...4)
                    Button { Task { await enviar() } } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .disabled(esperando || texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding()
            }
            .navigationTitle("Jacque")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func enviar() async {
        let msg = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        texto = ""; falas.append(Fala(minha: true, texto: msg)); esperando = true
        defer { esperando = false }
        do {
            let r: RespChat = try await Gateway.post("/jacque/treino/chat", ["texto": msg], timeout: 170)
            falas.append(Fala(minha: false, texto: r.resposta ?? r.erro ?? "Sem resposta."))
        } catch { falas.append(Fala(minha: false, texto: "Falhou: " + error.localizedDescription)) }
    }
}

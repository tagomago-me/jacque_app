import SwiftUI

struct ContentView: View {
    @State private var treino = WorkoutManager()
    @State private var ponte = WatchBridge()

    var body: some View {
        VStack(spacing: 8) {
            Text(treino.bpm > 0 ? "\(Int(treino.bpm.rounded()))" : "--")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("bpm · \(treino.amostras) amostras")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let e = treino.erro {
                Text(e).font(.caption2).foregroundStyle(.red)
            }
            Text("sessão: \(treino.estado) · \(treino.permissao)")
                .font(.caption2).foregroundStyle(.secondary)
            Button(treino.rodando ? "Encerrar" : "Iniciar treino") {
                if treino.rodando { treino.encerrar() }
                else { Task { await treino.pedirPermissao(); treino.iniciar() } }
            }
            .tint(treino.rodando ? .red : .green)
        }
        .task {
            await treino.pedirPermissao()
            treino.aoReceberBpm = { bpm, t in ponte.enviarBpm(bpm, t) }
            ponte.aoComando = { c in
                if c == "iniciar", !treino.rodando { treino.iniciar() }
                if c == "fim", treino.rodando { treino.encerrar() }
            }
        }
    }
}

#Preview { ContentView() }

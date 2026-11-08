import SwiftUI

struct ContentView: View {
    @State private var ponte = PhoneBridge()

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "heart.fill").font(.system(size: 40)).foregroundStyle(.red)
            Text(ponte.bpm > 0 ? "\(ponte.bpm)" : "--")
                .font(.system(size: 96, weight: .bold, design: .rounded)).monospacedDigit()
            Text("bpm").foregroundStyle(.secondary)
            Divider().padding(.horizontal, 40)
            linha("Treino", ponte.treinoAtivo ? "ativo" : "parado")
            linha("Watch", ponte.watchAlcancavel ? "conectado" : "fora de alcance")
            linha("Gateway", ponte.gateway)
            linha("Amostras", "\(ponte.amostras)")
            if let t = ponte.ultimaAmostra {
                linha("Última", t.formatted(date: .omitted, time: .standard))
            }
        }
        .padding()
    }

    private func linha(_ a: String, _ b: String) -> some View {
        HStack { Text(a).foregroundStyle(.secondary); Spacer(); Text(b) }
            .padding(.horizontal, 40)
    }
}

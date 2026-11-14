import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TreinoView().tabItem { Label("Treino", systemImage: "heart.fill") }
            ConversaView().tabItem { Label("Jacque", systemImage: "bubble.left.and.bubble.right") }
            BancoView().tabItem { Label("Banco", systemImage: "tablecells") }
            VerificarView().tabItem { Label("Verificar", systemImage: "checkmark.shield") }
        }
    }
}

struct TreinoView: View {
    @State private var ponte = PhoneBridge()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "heart.fill").foregroundStyle(.red)
                        Text(ponte.bpm > 0 ? "\(ponte.bpm)" : "--").font(.system(size: 54, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("bpm").foregroundStyle(.secondary)
                        Spacer()
                    }
                    linha("Watch", ponte.watchAlcancavel ? "conectado" : "fora de alcance")
                    linha("Gateway", ponte.gateway)
                    linha("Amostras", "\(ponte.amostras)")
                }
                TreinoAoVivoView(bpmAtual: ponte.bpm)
            }
            .navigationTitle("Treino")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func linha(_ a: String, _ b: String) -> some View {
        HStack { Text(a).foregroundStyle(.secondary); Spacer(); Text(b) }
    }
}

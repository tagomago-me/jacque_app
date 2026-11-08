import Foundation
import HealthKit
import Observation

/// Sessão de treino de força no Watch. Entrega bpm ao vivo pelo HKLiveWorkoutBuilder.
@Observable
final class WorkoutManager: NSObject {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    var bpm: Double = 0
    var rodando = false
    var amostras = 0
    var erro: String?
    var estado = "parado"
    var permissao = "?"

    /// Chamado a cada amostra nova de bpm (ponte para o iPhone no Marco 2).
    var aoReceberBpm: ((Double, Date) -> Void)?

    func pedirPermissao() async {
        let ler: Set<HKObjectType> = [HKQuantityType(.heartRate), HKObjectType.workoutType()]
        let escrever: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
        do {
            try await store.requestAuthorization(toShare: escrever, read: ler)
            let st = store.authorizationStatus(for: HKObjectType.workoutType())
            permissao = st == .sharingAuthorized ? "treino ok" : "treino negado"
        } catch { self.erro = "Permissão: \(error.localizedDescription)"; permissao = "erro" }
    }

    func iniciar() {
        let cfg = HKWorkoutConfiguration()
        cfg.activityType = .traditionalStrengthTraining
        cfg.locationType = .indoor
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: cfg)
            let b = s.associatedWorkoutBuilder()
            let fonte = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: cfg)
            fonte.enableCollection(for: HKQuantityType(.heartRate), predicate: nil)
            b.dataSource = fonte
            s.delegate = self
            b.delegate = self
            session = s
            builder = b
            let inicio = Date()
            s.startActivity(with: inicio)
            Task { try? await b.beginCollection(at: inicio) }
            amostras = 0
            erro = nil
            rodando = true
        } catch {
            self.erro = "Início: \(error.localizedDescription)"
        }
    }

    func encerrar() {
        session?.end()
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ s: HKWorkoutSession, didChangeTo to: HKWorkoutSessionState, from: HKWorkoutSessionState, date: Date) {
        let nome: String
        switch to {
        case .notStarted: nome = "não iniciada"
        case .prepared: nome = "preparada"
        case .running: nome = "rodando"
        case .paused: nome = "pausada"
        case .stopped: nome = "parada"
        case .ended: nome = "encerrada"
        @unknown default: nome = "?"
        }
        DispatchQueue.main.async { self.estado = nome }
        if to == .ended {
            builder?.endCollection(withEnd: date) { _, _ in
                self.builder?.finishWorkout { _, _ in
                    DispatchQueue.main.async { self.rodando = false }
                }
            }
        }
    }

    func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.erro = error.localizedDescription }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ b: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ b: HKLiveWorkoutBuilder, didCollectDataOf tipos: Set<HKSampleType>) {
        let hr = HKQuantityType(.heartRate)
        guard tipos.contains(hr), let est = b.statistics(for: hr),
              let q = est.mostRecentQuantity() else { return }
        let valor = q.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        let quando = est.mostRecentQuantityDateInterval()?.end ?? Date()
        DispatchQueue.main.async {
            self.bpm = valor
            self.amostras += 1
            self.aoReceberBpm?(valor, quando)
        }
    }
}

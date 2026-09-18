import ActivityKit
import AppIntents
import Foundation
import UserNotifications

/// "Serie fatta" premuto sulla schermata di blocco.
///
/// **Il file appartiene a due target.** `LiveActivityIntent` viene eseguito da
/// iOS nel processo dell'**app** (svegliata in background se serve): se il
/// tipo non è compilato anche dentro `Runner`, il sistema non lo trova lì e lo
/// esegue fuori processo (`WFIsolatedShortcutRunner`), dove
/// `Activity.activities` è vuoto — il tap sembra non fare niente. L'estensione
/// lo compila a sua volta perché è ciò che `Button(intent:)` referenzia.
///
/// Il processo è quello dell'app, ma non c'è nessun motore Dart vivo su cui
/// contare: l'app può essere sospesa e questo `perform` gira comunque. Quindi
/// niente Bloc, niente database — fa tre cose, in quest'ordine:
///
/// 1. lascia l'azione nella coda dell'App Group — è l'unica che non può
///    fallire senza perdere il lavoro dell'utente;
/// 2. aggiorna subito la Live Activity, così il tap ha un effetto visibile
///    anche se l'app dorme;
/// 3. programma la notifica di fine recupero, perché il beep lo darebbe l'app
///    e l'app non è sveglia.
///
/// L'app, al rientro in primo piano, drena la coda e registra la serie con
/// l'orario del tap; da quel momento torna lei a programmare i segnali.
@available(iOS 17.0, *)
struct CompleteSetIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Serie fatta"

  /// Non è una scorciatoia da offrire all'utente: esiste solo per il pulsante
  /// della Live Activity.
  static var isDiscoverable: Bool = false

  init() {}

  func perform() async throws -> some IntentResult {
    guard let activity = Activity<TaccaSessionAttributes>.activities.first else {
      return .result()
    }
    let attributes = activity.attributes
    let state = activity.content.state
    guard state.canCompleteSet else { return .result() }

    let now = Date()
    PendingActionStore.append(
      PendingLiveAction(
        id: UUID().uuidString,
        kind: "setCompleted",
        logId: attributes.logId,
        entryIndex: state.entryIndex,
        setNumber: state.setNumber,
        at: Int(now.timeIntervalSince1970 * 1000)
      )
    )

    var next = state
    if !state.advancesToNext && state.totalSets > 0 && state.setNumber < state.totalSets {
      // Restano serie di questo esercizio. Non in un blocco a giri, dove la
      // serie dopo è di un altro esercizio: lì `advancesToNext` manda
      // direttamente al ramo sotto.
      next.setNumber = state.setNumber + 1
    } else if let nextExercise = state.nextExerciseName {
      // Erano finite: si passa all'esercizio dopo, quello che l'app ha
      // mandato insieme allo stato.
      next.exerciseName = nextExercise
      next.entryIndex = state.nextEntryIndex
      next.setNumber = state.nextSetNumber
      next.totalSets = state.nextTotalSets
      next.restSecondsOnComplete = state.nextRestSecondsOnComplete
      next.canCompleteSet = state.nextSetNumber > 0
      next.advancesToNext = state.nextAdvancesToNext
      // Un passo solo: quale sia l'esercizio ancora dopo lo sa solo l'app.
      // Esaurite anche queste serie il pulsante sparisce fino alla
      // riapertura — è l'unico momento in cui serve davvero riaprirla.
      next.nextExerciseName = nil
      next.nextEntryIndex = 0
      next.nextSetNumber = 0
      next.nextTotalSets = 0
      next.nextRestSecondsOnComplete = 0
      next.nextAdvancesToNext = false
    } else {
      // Niente più da spuntare: il contatore resta sull'ultima serie fatta,
      // senza pulsante. Non si inventa una serie in più.
      next.canCompleteSet = false
    }

    if state.restSecondsOnComplete > 0 {
      let endsAt = now.addingTimeInterval(TimeInterval(state.restSecondsOnComplete))
      next.countdownStartsAt = now
      next.countdownEndsAt = endsAt
      next.countdownLabel = attributes.restLabel
      scheduleRestReminder(after: state.restSecondsOnComplete, attributes: attributes)
    } else {
      next.countdownStartsAt = nil
      next.countdownEndsAt = nil
      next.countdownLabel = nil
    }

    await activity.update(ActivityContent(state: next, staleDate: nil))
    return .result()
  }

  /// Beep di fine recupero. Id fisso: l'app lo annulla appena si risveglia,
  /// altrimenti suonerebbe due volte (il suo `SessionNotifier` programma già
  /// gli stessi segnali quando l'app va in background).
  private func scheduleRestReminder(
    after seconds: Int,
    attributes: TaccaSessionAttributes
  ) {
    let content = UNMutableNotificationContent()
    content.title = attributes.title
    content.body = attributes.restDoneLabel
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: LiveSessionShared.restReminderId,
      content: content,
      trigger: UNTimeIntervalNotificationTrigger(
        timeInterval: TimeInterval(seconds),
        repeats: false
      )
    )
    UNUserNotificationCenter.current().add(request)
  }
}

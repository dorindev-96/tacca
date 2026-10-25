import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

/// Identificatori condivisi fra l'app e l'estensione della Live Activity.
///
/// I due processi non si parlano: l'unico canale è l'App Group, quindi questi
/// valori devono restare identici da entrambe le parti (sono la stessa
/// costante compilata due volte, non due costanti uguali per caso).
enum LiveSessionShared {
  /// App Group condiviso. Va abilitato su **entrambi** i target in Xcode
  /// (Signing & Capabilities → App Groups) con esattamente questo nome.
  static let appGroupId = "group.com.tverdohleb.tacca"

  /// Chiave della coda delle azioni dentro gli `UserDefaults` dell'App Group.
  static let pendingActionsKey = "live_session.pending_actions"

  /// Notifica di fine recupero programmata dall'estensione quando la serie
  /// viene confermata a app spenta. Id fisso: l'app la annulla appena si
  /// risveglia e riprende in mano i timer.
  static let restReminderId = "live_session.rest_reminder"
}

/// Stato della sessione mostrato dalla Live Activity.
///
/// `ContentState` è la parte che cambia durante l'allenamento; gli attributi
/// veri e propri (etichette localizzate e id della sessione) restano fissi per
/// tutta la durata dell'attività.
///
/// "Esercizio" e "serie" sono i nomi storici dei campi: in un superset o in un
/// circuito lo stato mostra il **giro intero** (`completesRound`) — il nome è
/// quello degli esercizi del giro uniti da "+", la serie è il numero del giro.
/// Per il conteggio non cambia niente: i giri si contano come le serie.
@available(iOS 16.1, *)
struct TaccaSessionAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    /// Esercizio con la prossima serie da confermare.
    var exerciseName: String

    /// Posizione dell'esercizio nella sequenza del giorno.
    var entryIndex: Int

    /// Serie che il pulsante conferma.
    var setNumber: Int

    /// Serie previste; 0 se la scheda non le specifica.
    var totalSets: Int

    /// `false` quando non resta niente da spuntare: il pulsante sparisce
    /// invece di registrare una serie che non esiste.
    var canCompleteSet: Bool

    /// `true` quando la serie dopo questa è di un **altro** esercizio: si
    /// salta a `next*` invece di contare avanti qui.
    ///
    /// È il caso dei blocchi a giri: in un superset un giro è una serie di
    /// ciascun esercizio del gruppo, quindi dopo "Curl, giro 1" viene
    /// "Pushdown, giro 1". Contare avanti metterebbe in coda un giro che
    /// l'utente non ha fatto, e l'altro esercizio non arriverebbe mai qui.
    var advancesToNext: Bool = false

    /// Recupero da far partire alla conferma, in secondi. 0 = nessuno.
    var restSecondsOnComplete: Int

    /// `true` quando il pulsante chiude un giro intero di un superset o di un
    /// circuito: in coda va un `roundCompleted`, il pulsante dice "Giro fatto"
    /// e il conteggio "Giro 2/4". L'app spunta poi ogni esercizio del giro.
    var completesRound: Bool = false

    var countdownStartsAt: Date?
    var countdownEndsAt: Date?
    var countdownLabel: String?

    /// Esercizio su cui spostarsi quando le serie di questo finiscono, `nil`
    /// se non ne resta nessuno.
    ///
    /// È l'unico passo avanti che l'intent può fare senza l'app: con le serie
    /// esaurite e nessun esercizio dopo, il contatore resterebbe fermo su una
    /// serie inesistente ("4/3"). Il passo successivo lo ricalcola l'app.
    var nextExerciseName: String?

    /// Coordinate della prima serie da spuntare di `nextExerciseName`: finiscono
    /// nell'azione messa in coda, quindi sono quelle vere e non un "serie 1"
    /// dato per scontato.
    var nextEntryIndex: Int = 0
    var nextSetNumber: Int = 0
    var nextTotalSets: Int = 0

    /// Recupero da avviare confermando una serie di `nextExerciseName`.
    var nextRestSecondsOnComplete: Int = 0

    /// `advancesToNext` di `nextExerciseName`: senza, arrivati lì non si
    /// saprebbe se si può continuare a contare da soli (blocco normale) o se
    /// bisogna fermarsi e lasciar ricalcolare all'app (blocco a giri).
    var nextAdvancesToNext: Bool = false

    /// `completesRound` di `nextExerciseName`: arrivati lì, il pulsante deve
    /// sapere se conferma una serie o un giro (dopo un superset viene spesso un
    /// esercizio normale, e viceversa).
    var nextCompletesRound: Bool = false
  }

  /// Sessione a cui appartiene l'attività: un'azione rimasta in coda da un
  /// allenamento precedente viene scartata dall'app.
  var logId: Int

  // Etichette già localizzate: gli ARB dell'app qui non si possono leggere.
  var title: String
  var setsLabel: String
  var completeAction: String
  var restLabel: String
  var restDoneLabel: String

  /// Parola per i giri ("Giro") e pulsante che chiude un giro intero ("Giro
  /// fatto"): le controparti di `setsLabel` e `completeAction`.
  var roundsLabel: String = ""
  var completeRoundAction: String = ""

  /// Etichette dello stato mostrato: quelle dei giri quando il pulsante ne
  /// chiude uno intero.
  func unitLabel(_ state: ContentState) -> String {
    state.completesRound && !roundsLabel.isEmpty ? roundsLabel : setsLabel
  }

  func actionLabel(_ state: ContentState) -> String {
    state.completesRound && !completeRoundAction.isEmpty
      ? completeRoundAction
      : completeAction
  }
}

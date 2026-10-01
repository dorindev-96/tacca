import ActivityKit
import SwiftUI
import WidgetKit

/// Tinte del design ("Gym full figma"), le stesse dell'app.
///
/// Sono ricopiate a mano perché l'estensione non compila il Dart: se cambiano
/// in `lib/core/design/app_colors.dart` vanno cambiate anche qui.
enum TaccaColors {
  /// Inchiostro #192126.
  static let ink = Color(red: 0.098, green: 0.129, blue: 0.149)

  /// Lime #BBF246: sopra ci va sempre l'inchiostro, mai il bianco.
  static let lime = Color(red: 0.733, green: 0.949, blue: 0.275)

  /// Secondario #8C9092.
  static let muted = Color(red: 0.549, green: 0.565, blue: 0.573)
}

/// La sessione sulla schermata di blocco e nella Dynamic Island.
///
/// Il countdown lo disegna il sistema a partire dall'istante di fine
/// (`Text(timerInterval:)`): scorre anche a telefono bloccato e ad app spenta,
/// senza un solo aggiornamento da parte nostra.
///
/// Da iOS 18 la stessa attività va anche sull'Apple Watch (watchOS 11), nello
/// Smart Stack. Senza la famiglia `.small` dichiarata il Watch la mostrerebbe
/// lo stesso, ma ricomponendola da `compactLeading`/`compactTrailing`: icona e
/// countdown, nessun pulsante. Dichiarandola disegna `WatchSessionView`, che
/// il pulsante ce l'ha: il tap esegue `CompleteSetIntent` **sull'iPhone**,
/// esattamente come dalla schermata di blocco (stessa coda, stesso drenaggio,
/// stesso orario del tap). Non c'è codice watchOS: è l'iPhone a spedire la
/// vista al Watch.
struct SessionLiveActivity: Widget {
  var body: some WidgetConfiguration {
    Self.withWatchFamily()
  }

  /// Aggiunge la famiglia del Watch dove esiste (iOS 18).
  ///
  /// I due rami restituiscono tipi diversi dietro lo stesso `some`: è lecito
  /// solo in una funzione con `return` espliciti e con l'`if #available` in
  /// cima seguito dal `return` del caso vecchio (SE-0360, Swift 5.7). Non va
  /// riscritta come `if/else` dentro un result builder: né
  /// `WidgetConfigurationBuilder` né `WidgetBundleBuilder` sanno costruire un
  /// `else`, ed è anche per questo che non esistono due widget separati.
  private static func withWatchFamily() -> some WidgetConfiguration {
    if #available(iOS 18.0, *) {
      return configuration().supplementalActivityFamilies([.small])
    }
    return configuration()
  }

  /// La configurazione vera, uguale nei due rami.
  private static func configuration() -> some WidgetConfiguration {
    ActivityConfiguration(for: TaccaSessionAttributes.self) { context in
      SessionContentView(attributes: context.attributes, state: context.state)
        .activityBackgroundTint(TaccaColors.ink)
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          VStack(alignment: .leading, spacing: 2) {
            Text(context.state.exerciseName)
              .font(.headline)
              .foregroundStyle(.white)
              .lineLimit(1)
            Text(SessionLiveActivity.setsText(context.attributes, context.state))
              .font(.caption)
              .foregroundStyle(TaccaColors.muted)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          CountdownView(attributes: context.attributes, state: context.state, compact: true)
        }
        DynamicIslandExpandedRegion(.bottom) {
          CompleteSetButton(attributes: context.attributes, state: context.state)
        }
      } compactLeading: {
        Image(systemName: "figure.strengthtraining.traditional")
          .foregroundStyle(TaccaColors.lime)
      } compactTrailing: {
        CountdownView(attributes: context.attributes, state: context.state, compact: true)
      } minimal: {
        Image(systemName: "figure.strengthtraining.traditional")
          .foregroundStyle(TaccaColors.lime)
      }
      .keylineTint(TaccaColors.lime)
    }
  }

  /// "Serie 2/4", o "Serie 2" quando la scheda non prescrive quante.
  static func setsText(
    _ attributes: TaccaSessionAttributes,
    _ state: TaccaSessionAttributes.ContentState
  ) -> String {
    guard state.setNumber > 0 else { return attributes.title }
    if state.totalSets > 0 {
      return "\(attributes.setsLabel) \(state.setNumber)/\(state.totalSets)"
    }
    return "\(attributes.setsLabel) \(state.setNumber)"
  }
}

/// Smista fra il banner del telefono e la card del Watch.
///
/// `activityFamily` esiste solo da iOS 18: sotto, l'unica famiglia è quella
/// della schermata di blocco.
struct SessionContentView: View {
  let attributes: TaccaSessionAttributes
  let state: TaccaSessionAttributes.ContentState

  var body: some View {
    if #available(iOS 18.0, *) {
      FamilyAwareContentView(attributes: attributes, state: state)
    } else {
      LockScreenView(attributes: attributes, state: state)
    }
  }
}

@available(iOS 18.0, *)
private struct FamilyAwareContentView: View {
  let attributes: TaccaSessionAttributes
  let state: TaccaSessionAttributes.ContentState

  @Environment(\.activityFamily) private var family

  var body: some View {
    switch family {
    case .small:
      WatchSessionView(attributes: attributes, state: state)
    case .medium:
      LockScreenView(attributes: attributes, state: state)
    @unknown default:
      LockScreenView(attributes: attributes, state: state)
    }
  }
}

/// La card nello Smart Stack del Watch.
///
/// Lo spazio è quello di una card dello Smart Stack: niente titolo della
/// scheda, l'esercizio su una riga sola, e il pulsante a tutta larghezza
/// perché al polso, a mani sudate, è l'unica cosa che conta centrare.
/// La famiglia `.small` la usano anche altre superfici di sistema (CarPlay da
/// iOS 26): la vista non presuppone di stare su un Watch.
struct WatchSessionView: View {
  let attributes: TaccaSessionAttributes
  let state: TaccaSessionAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(state.exerciseName)
          .font(.headline)
          .foregroundStyle(.white)
          .lineLimit(1)
        Spacer(minLength: 4)
        CountdownView(attributes: attributes, state: state, compact: true)
      }
      Text(SessionLiveActivity.setsText(attributes, state))
        .font(.caption2)
        .foregroundStyle(TaccaColors.muted)
        .lineLimit(1)
      CompleteSetButton(attributes: attributes, state: state, fullWidth: true)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
  }
}

/// Il banner della schermata di blocco.
struct LockScreenView: View {
  let attributes: TaccaSessionAttributes
  let state: TaccaSessionAttributes.ContentState

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(attributes.title)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(TaccaColors.muted)
        Text(state.exerciseName)
          .font(.headline)
          .foregroundStyle(.white)
          .lineLimit(2)
        Text(SessionLiveActivity.setsText(attributes, state))
          .font(.subheadline)
          .foregroundStyle(TaccaColors.muted)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 10) {
        CountdownView(attributes: attributes, state: state, compact: false)
        CompleteSetButton(attributes: attributes, state: state)
      }
    }
    .padding(16)
  }
}

/// Countdown del recupero. Fuori da un timer non disegna niente.
struct CountdownView: View {
  let attributes: TaccaSessionAttributes
  let state: TaccaSessionAttributes.ContentState
  let compact: Bool

  var body: some View {
    if let endsAt = state.countdownEndsAt {
      VStack(alignment: .trailing, spacing: 0) {
        if !compact, let label = state.countdownLabel {
          Text(label)
            .font(.caption2)
            .foregroundStyle(TaccaColors.muted)
        }
        Text(timerInterval: range(until: endsAt), countsDown: true, showsHours: false)
          .font(compact ? .caption.weight(.semibold) : .system(size: 30, weight: .bold))
          .monospacedDigit()
          .multilineTextAlignment(.trailing)
          .foregroundStyle(.white)
          .frame(maxWidth: compact ? 44 : 92)
      }
    } else if !compact, let label = state.countdownLabel {
      // Recupero finito: resta la scritta, senza numeri che scorrono.
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(TaccaColors.lime)
    }
  }

  /// `Text(timerInterval:)` pretende un intervallo valido: un countdown già
  /// scaduto arriverebbe con l'inizio dopo la fine.
  private func range(until endsAt: Date) -> ClosedRange<Date> {
    let start = state.countdownStartsAt ?? Date()
    return start <= endsAt ? start...endsAt : endsAt...endsAt
  }
}

/// Il pulsante che conferma la serie senza aprire l'app.
///
/// Richiede iOS 17: prima di allora i widget non possono eseguire intent. Su
/// 16.2 il banner resta comunque utile — esercizio corrente e countdown — solo
/// senza pulsante.
///
/// `fullWidth` è per il Watch: lì il pulsante occupa tutta la card e si alza
/// un poco, perché il bersaglio è piccolo e lo si preme in movimento.
///
/// Con il Watch in Always On (polso abbassato) il sistema riduce la
/// luminosità e chiede di spegnere gli elementi accesi: il lime pieno diventa
/// un contorno, stesso ingombro, così la card non salta al risveglio. Sul
/// telefono `isLuminanceReduced` resta `false` e non cambia niente.
struct CompleteSetButton: View {
  let attributes: TaccaSessionAttributes
  let state: TaccaSessionAttributes.ContentState
  var fullWidth: Bool = false

  @Environment(\.isLuminanceReduced) private var isLuminanceReduced

  var body: some View {
    if #available(iOS 17.0, *) {
      if state.canCompleteSet {
        Button(intent: CompleteSetIntent()) {
          Text(attributes.completeAction)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(isLuminanceReduced ? TaccaColors.lime : TaccaColors.ink)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, fullWidth ? 10 : 8)
            .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(.plain)
        .background {
          if isLuminanceReduced {
            Capsule().strokeBorder(TaccaColors.lime, lineWidth: 1.5)
          } else {
            Capsule().fill(TaccaColors.lime)
          }
        }
      }
    }
  }
}

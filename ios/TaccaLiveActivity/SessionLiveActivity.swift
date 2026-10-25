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
struct SessionLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: TaccaSessionAttributes.self) { context in
      LockScreenView(attributes: context.attributes, state: context.state)
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

  /// "Serie 2/4", o "Serie 2" quando la scheda non prescrive quante. In un
  /// superset "Giro 2/4".
  static func setsText(
    _ attributes: TaccaSessionAttributes,
    _ state: TaccaSessionAttributes.ContentState
  ) -> String {
    guard state.setNumber > 0 else { return attributes.title }
    let unit = attributes.unitLabel(state)
    if state.totalSets > 0 {
      return "\(unit) \(state.setNumber)/\(state.totalSets)"
    }
    return "\(unit) \(state.setNumber)"
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

/// Il pulsante che conferma la serie — o il giro intero di un superset —
/// senza aprire l'app.
///
/// Richiede iOS 17: prima di allora i widget non possono eseguire intent. Su
/// 16.2 il banner resta comunque utile — esercizio corrente e countdown — solo
/// senza pulsante.
struct CompleteSetButton: View {
  let attributes: TaccaSessionAttributes
  let state: TaccaSessionAttributes.ContentState

  var body: some View {
    if #available(iOS 17.0, *) {
      if state.canCompleteSet {
        Button(intent: CompleteSetIntent()) {
          Text(attributes.actionLabel(state))
            .font(.subheadline.weight(.bold))
            .foregroundStyle(TaccaColors.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(TaccaColors.lime, in: Capsule())
      }
    }
  }
}

import SwiftUI
import WidgetKit

/// Estensione widget che ospita la Live Activity della sessione.
///
/// Non contiene widget della home: serve solo alla schermata di blocco, alla
/// Dynamic Island e, da iOS 18, allo Smart Stack dell'Apple Watch.
@main
struct TaccaLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    SessionLiveActivity()
  }
}

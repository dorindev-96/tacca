import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/app_spacing.dart';
import '../design/theme_context.dart';
import 'home_tab_bar.dart';
import 'square_icon_button.dart';

/// L'impaginato di ogni schermata del restyling.
///
/// Non c'è `AppBar`: nel design la testata è una riga di pulsanti icona
/// quadrati e il titolo è un blocco Lato Black da 24 dentro il contenuto,
/// alla stessa distanza dal bordo di tutto il resto (24). Un'`AppBar`
/// riporterebbe il titolo alla tipografia e alle altezze di Material.
///
/// L'azione principale non è un FAB ma una **pillola agganciata in basso**
/// ([dock]), sopra la quale galleggia — nelle tre schermate della shell — la
/// tab bar. Le liste devono quindi lasciare in fondo
/// [AppSpacing.dockClearance] (con tab bar) o [AppSpacing.actionClearance].
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.body,
    this.leading,
    this.actions = const <Widget>[],
    this.title,
    this.header,
    this.dock,
    this.aboveTabBar = false,
    this.topSpacing = AppSpacing.card,
    super.key,
  });

  /// Contenuto scorrevole della schermata. Occupa tutto lo spazio rimasto.
  final Widget body;

  /// Pulsante a sinistra della testata (di norma [AppBackButton]).
  final Widget? leading;

  /// Pulsanti a destra della testata.
  final List<Widget> actions;

  /// Titolo della schermata. Null quando il titolo è dentro il contenuto
  /// perché deve scorrere via (dettaglio scheda).
  final String? title;

  /// Contenuto fisso sotto il titolo: campo di ricerca, avanzamento, timer.
  final Widget? header;

  /// Contenuto agganciato in fondo: la pillola dell'azione principale.
  final Widget? dock;

  /// True per le schermate della shell: il [dock] sale di quanto serve a
  /// lasciare libera la tab bar flottante, che è disegnata dalla shell e non
  /// dalla pagina.
  final bool aboveTabBar;

  final double topSpacing;

  bool get _hasBar => leading != null || actions.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.chrome.systemOverlay,
      child: Scaffold(
        backgroundColor: context.colors.background,
        // Il dock è disegnato dentro lo Stack, non da `bottomNavigationBar`:
        // deve galleggiare *sopra* la lista, che gli scorre sotto.
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_hasBar)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.card,
                        topSpacing,
                        AppSpacing.card,
                        AppSpacing.lg,
                      ),
                      child: Row(
                        children: [
                          if (leading != null) leading!,
                          const Spacer(),
                          ...actions,
                        ],
                      ),
                    ),
                  if (title != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        _hasBar ? 0 : topSpacing,
                        AppSpacing.xl,
                        AppSpacing.card,
                      ),
                      child: Text(title!, style: context.type.screenTitle),
                    ),
                  if (header != null) header!,
                  Expanded(child: body),
                ],
              ),
            ),
            if (dock != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AppDock(aboveTabBar: aboveTabBar, child: dock!),
              ),
          ],
        ),
      ),
    );
  }
}

/// Aggancio in basso: rispetta l'indicatore home e non intercetta i tocchi
/// fuori dai propri figli, così la lista sottostante resta scorrevole ai
/// lati della pillola.
class AppDock extends StatelessWidget {
  const AppDock({required this.child, this.aboveTabBar = false, super.key});

  final Widget child;

  /// True quando sotto c'è la tab bar flottante della shell.
  final bool aboveTabBar;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final tabBar = aboveTabBar ? HomeTabBar.height + AppSpacing.md : 0.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        math.max(bottomInset, AppSpacing.lg) + tabBar,
      ),
      child: child,
    );
  }
}

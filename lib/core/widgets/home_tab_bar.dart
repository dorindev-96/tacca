import 'package:flutter/material.dart';

import '../design/app_radius.dart';
import '../design/app_spacing.dart';
import '../design/linear_icons.dart';
import '../design/theme_context.dart';
import 'linear_icon.dart';

/// Una destinazione della [HomeTabBar].
class HomeTab {
  const HomeTab({required this.icon, required this.label});

  final LinearIconData icon;
  final String label;
}

/// Tab bar flottante: 340×56, raggio 32, fondo pieno, con la destinazione
/// attiva in una pillola lime che porta anche l'etichetta.
///
/// Solo la tab attiva è etichettata: è quello che rende leggibile una barra
/// alta 56 senza schiacciarci dentro tre testi. Le altre restano icone, e
/// l'etichetta arriva comunque all'accessibilità via [Semantics].
///
/// La barra è il motivo per cui `inkSurface` non si schiarisce nel tema
/// scuro: la pillola attiva è lime, e il lime su un fondo quasi bianco non si
/// distingue più (1,1:1). Vedi [AppPalette].
class HomeTabBar extends StatelessWidget {
  const HomeTabBar({
    required this.tabs,
    required this.currentIndex,
    required this.onSelected,
    super.key,
  });

  final List<HomeTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  static const double _width = 340;

  /// Altezza della barra: le pagine della shell la sommano allo spazio che
  /// lasciano in fondo alle liste.
  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    // Una larghezza fissa sotto `Center` si stringe da sé a quella
    // disponibile: sugli schermi più stretti di 340 la barra li riempie.
    return Center(
      child: Container(
        width: _width,
        height: height,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm + 2,
          0,
          AppSpacing.xl + AppSpacing.xs,
          0,
        ),
        decoration: BoxDecoration(
          color: context.colors.inkSurface,
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.xl)),
          boxShadow: context.chrome.floating,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < tabs.length; i++)
              // Solo la tab attiva porta l'etichetta, quindi solo lei può
              // diventare troppo larga: è l'unica flessibile.
              if (i == currentIndex) Flexible(child: _tab(i)) else _tab(i),
          ],
        ),
      ),
    );
  }

  Widget _tab(int i) => _Tab(
    key: ValueKey('home-tab-${tabs[i].label}'),
    tab: tabs[i],
    selected: i == currentIndex,
    onTap: () => onSelected(i),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.tab,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final HomeTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final content = selected
        ? Container(
            height: 36,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.card - 1,
              0,
            ),
            decoration: BoxDecoration(
              color: context.colors.lime,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearIcon(tab.icon, color: context.colors.onLime),
                const SizedBox(width: AppSpacing.lg),
                Flexible(
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.meta.copyWith(
                      color: context.colors.onLime,
                    ),
                  ),
                ),
              ],
            ),
          )
        : LinearIcon(tab.icon, color: context.colors.onInkSurface);

    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      // Niente velo dei tocchi: il `Material` più vicino è quello della
      // shell, che disegna l'inchiostro *sotto* il fondo pieno della barra.
      // Sarebbe un'animazione a ogni tocco che nessuno vede; la risposta al
      // tocco è la pillola lime che si sposta.
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        child: SizedBox(
          height: HomeTabBar.height,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: selected ? 0 : AppSpacing.sm,
            ),
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}

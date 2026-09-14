import 'package:flutter/material.dart';

import '../design/app_spacing.dart';
import '../design/theme_context.dart';

/// Etichetta di sezione ("In uso", "Schede", "Archiviate", "Descrizione").
///
/// Nel restyling non è un titolo: è una riga grigia da 16 in peso normale,
/// staccata di 12 dal gruppo che introduce e di 24 dal gruppo precedente. Il
/// contrasto lo fa il contenuto sotto — bianco su grigio — non l'etichetta.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.label,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: AppSpacing.md),
    super.key,
  });

  final String label;

  /// Contenuto allineato a destra: tipicamente un conteggio o un'azione.
  final Widget? trailing;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.type.sectionLabel)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Sezione completa: etichetta + contenuto, con lo stacco di 24 dal gruppo
/// precedente già applicato. È la struttura che si ripete in ogni schermata
/// del restyling.
class Section extends StatelessWidget {
  const Section({
    required this.child,
    this.label,
    this.trailing,
    this.topSpacing = AppSpacing.xl,
    super.key,
  });

  final Widget child;
  final String? label;
  final Widget? trailing;
  final double topSpacing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null) SectionHeader(label: label!, trailing: trailing),
          child,
        ],
      ),
    );
  }
}

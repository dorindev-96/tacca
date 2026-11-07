import 'package:flutter/material.dart';

import '../design/app_spacing.dart';
import '../design/theme_context.dart';

/// Sezione completa: etichetta + contenuto, con lo stacco di 24 dal gruppo
/// precedente già applicato. È la struttura che si ripete in ogni schermata
/// del restyling.
///
/// L'etichetta ("In uso", "Schede", "Archiviate", "Descrizione") nel
/// restyling non è un titolo: è una riga grigia da 16 in peso normale,
/// staccata di 12 dal gruppo che introduce. Il contrasto lo fa il contenuto
/// sotto — bianco su grigio — non l'etichetta.
class Section extends StatelessWidget {
  const Section({required this.child, this.label, super.key});

  final Widget child;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(label!, style: context.type.sectionLabel),
            ),
          child,
        ],
      ),
    );
  }
}

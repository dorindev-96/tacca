import 'package:flutter/material.dart';

import '../../../core/design/app_palette.dart';
import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/extensions/log_set_format.dart';
import '../../../core/widgets/linear_icon.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../data/entities/log_set.dart';
import '../../../data/repositories/workout_log_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../bloc/session_item.dart';

/// I colori di una card di sessione. L'esercizio corrente è lime, tutti gli
/// altri hanno il colore delle card: un solo esercizio in evidenza, quello che
/// si sta facendo.
class _CardPalette {
  const _CardPalette({
    required this.background,
    required this.secondary,
    required this.inset,
    required this.marker,
    required this.ring,
  });

  /// Card corrente: lime, con i toni ricavati per trasparenza dall'inchiostro
  /// — così restano leggibili sopra l'accento.
  ///
  /// Non dipende dal tema, e non è una dimenticanza: il lime è lo stesso al
  /// chiaro e al buio, quindi anche quello che ci sta sopra deve esserlo. È
  /// per questo che parte da [AppPalette.onLime] e non da `ink`.
  factory _CardPalette.current(AppPalette colors) => _CardPalette(
    background: colors.lime,
    secondary: colors.onLime.withValues(alpha: 0.72),
    inset: colors.onLime.withValues(alpha: 0.10),
    marker: colors.onLime.withValues(alpha: 0.16),
    ring: colors.onLime.withValues(alpha: 0.40),
  );

  factory _CardPalette.normal(AppPalette colors) => _CardPalette(
    background: colors.surface,
    secondary: colors.muted,
    inset: colors.fill,
    marker: colors.fill,
    ring: colors.stroke,
  );

  final Color background;
  final Color secondary;

  /// Fondo delle righe delle serie e degli altri riquadri interni.
  final Color inset;

  final Color marker;

  /// Contorno della spunta non ancora fatta.
  final Color ring;
}

/// Card di un esercizio in sessione (RF-06): esercizio corrente evidenziato,
/// spunta per serie e log rapido a portata di pollice.
class SessionExerciseCard extends StatelessWidget {
  const SessionExerciseCard({
    required this.item,
    required this.isCurrent,
    required this.lastPerformance,
    required this.onToggleSet,
    required this.onEditSet,
    required this.onFocus,
    this.onStartRest,
    this.groupMarker,
    super.key,
  });

  final SessionItem item;
  final bool isCurrent;
  final LastPerformance? lastPerformance;

  /// Posizione dentro un gruppo a giri ("A", "B", …): rende visibile a colpo
  /// d'occhio quali esercizi si alternano nello stesso giro. Null fuori dai
  /// superset e dai circuiti.
  final String? groupMarker;

  /// Spunta/despunta la serie.
  final void Function(int setNumber) onToggleSet;

  /// Apre il log rapido della serie.
  final void Function(int setNumber) onEditSet;

  final VoidCallback onFocus;

  /// Null quando l'esercizio non ha un recupero configurato.
  final VoidCallback? onStartRest;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = isCurrent
        ? _CardPalette.current(context.colors)
        : _CardPalette.normal(context.colors);
    final sets = item.displayedSets;

    // Nei blocchi a giri una "serie" è un giro del gruppo: chiamarla col suo
    // nome è ciò che rende leggibile un superset durante l'allenamento.
    final rounds = item.isRoundBased;
    String setLabel(int number) =>
        rounds ? l10n.workoutRoundLabel(number) : l10n.workoutSetLabel(number);

    final counter = rounds
        ? l10n.workoutRoundsDone(item.completedSets.length, sets)
        : l10n.workoutSetsDone(item.completedSets.length, sets);

    return SurfaceCard(
      color: palette.background,
      onTap: onFocus,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (groupMarker != null) ...[
                _GroupMarker(label: groupMarker!, background: palette.marker),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Text(
                  item.name,
                  style: isCurrent
                      ? context.type.subtitle
                      : context.type.cardTitle,
                ),
              ),
              if (sets > 0) ...[
                const SizedBox(width: AppSpacing.md),
                _CountChip(
                  label: counter,
                  background: palette.marker,
                  strong: isCurrent,
                ),
              ],
            ],
          ),
          if (_prescription.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(_prescription, style: context.type.row),
          ],
          if ((item.exercise?.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              item.exercise!.notes!,
              style: context.type.paragraphSmall.copyWith(
                color: palette.secondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _LastTimeLine(last: lastPerformance, color: palette.secondary),
          const SizedBox(height: AppSpacing.md),
          if (sets == 0)
            _SetRow(
              // Senza serie prescritte si registra comunque la prima.
              label: setLabel(1),
              set: item.setNumbered(1),
              palette: palette,
              onToggle: () => onToggleSet(1),
              onEdit: () => onEditSet(1),
            )
          else
            for (var number = 1; number <= sets; number++) ...[
              if (number > 1) const SizedBox(height: AppSpacing.sm),
              _SetRow(
                label: setLabel(number),
                set: item.setNumbered(number),
                palette: palette,
                onToggle: () => onToggleSet(number),
                onEdit: () => onEditSet(number),
              ),
            ],
          if (onStartRest != null) ...[
            const SizedBox(height: AppSpacing.md),
            PillButton.compact(
              label: rounds
                  ? l10n.workoutStartRoundRest
                  : l10n.workoutStartRestTimer,
              icon: AppIcons.play,
              iconColor: isCurrent ? context.colors.lime : null,
              expand: true,
              tone: isCurrent ? PillTone.primary : PillTone.outline,
              onPressed: onStartRest,
            ),
          ],
        ],
      ),
    );
  }

  String get _prescription {
    final exercise = item.exercise;
    if (exercise == null) return '';
    final parts = <String>[
      if (exercise.sets != null)
        '${exercise.sets}×${exercise.reps ?? '?'}'
      else if (exercise.reps != null)
        exercise.reps!,
      if ((exercise.load ?? '').isNotEmpty) exercise.load!,
      if (exercise.restSeconds != null) 'rec ${exercise.restSeconds}s',
      if (exercise.durationSeconds != null) '${exercise.durationSeconds}s',
    ];
    return parts.join(' · ');
  }
}

/// Lettera dell'esercizio dentro un gruppo a giri: la stessa notazione della
/// scheda ("A ss B"), così l'abbinamento si legge senza spiegazioni.
class _GroupMarker extends StatelessWidget {
  const _GroupMarker({required this.label, required this.background});

  final String label;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      width: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(label, style: context.type.buttonSmall.copyWith(height: 1)),
    );
  }
}

/// "2/4 serie": il conteggio di avanzamento dell'esercizio.
class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.background,
    required this.strong,
  });

  final String label;
  final Color background;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        label,
        style: strong ? context.type.chipStrong : context.type.chip,
      ),
    );
  }
}

class _LastTimeLine extends StatelessWidget {
  const _LastTimeLine({required this.last, required this.color});

  final LastPerformance? last;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = context.type.caption.copyWith(color: color);

    final performance = last;
    if (performance == null) {
      return Text(l10n.workoutLastTimeNever, style: style);
    }

    final summary = performance.sets.map((set) => set.summary).join(' · ');
    return Text(
      '${l10n.workoutLastTime(performance.performedAt)}: $summary',
      style: style,
    );
  }
}

/// Riga di una serie: spunta a sinistra (l'azione più frequente, sotto il
/// pollice), valori a destra, il resto della riga apre il log rapido.
class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.label,
    required this.set,
    required this.palette,
    required this.onToggle,
    required this.onEdit,
  });

  /// "Serie 2" oppure "Giro 2": lo decide il tipo di blocco.
  final String label;
  final LogSet? set;
  final _CardPalette palette;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final done = set != null;

    return Container(
      height: 56,
      padding: const EdgeInsets.only(left: AppSpacing.sm, right: AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.inset,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          _SetToggle(
            // Chiave stabile: è il bersaglio più toccato della sessione e i
            // test lo cercano da qui.
            key: ValueKey('set-toggle-$label'),
            done: done,
            ring: palette.ring,
            label: label,
            onToggle: onToggle,
          ),
          Expanded(
            child: InkWell(
              onTap: onEdit,
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: context.type.row.copyWith(
                          color: palette.secondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      done ? set!.summary : '—',
                      style: context.type.numeric,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    LinearIcon(
                      AppIcons.pencil,
                      size: 16,
                      color: palette.secondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La spunta: disco inchiostro con il segno lime quando è fatta, anello
/// vuoto quando non lo è. È il bersaglio più toccato della sessione, quindi
/// occupa 44×44 anche se il disegno ne misura 30.
class _SetToggle extends StatelessWidget {
  const _SetToggle({
    required this.done,
    required this.ring,
    required this.label,
    required this.onToggle,
    super.key,
  });

  final bool done;
  final Color ring;
  final String label;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: done,
      label: label,
      child: InkResponse(
        onTap: onToggle,
        radius: 24,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: Container(
              height: 30,
              width: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? context.colors.inkSurface : null,
                border: done ? null : Border.all(color: ring, width: 2),
              ),
              child: done
                  ? Center(
                      child: LinearIcon(
                        AppIcons.check,
                        size: 18,
                        color: context.colors.lime,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

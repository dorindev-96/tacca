import 'package:flutter/material.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/extensions/duration_format.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/timer/timer_engine.dart';

/// Barra del timer attivo: numeri enormi, leggibili con il telefono
/// appoggiato a distanza (RNF-04).
///
/// È l'unica superficie piena della sessione: quando c'è un timer in corso
/// deve essere la prima cosa che si vede entrando nella schermata. Dentro, il
/// lime torna a fare quello che fa ovunque — indicare la cosa viva.
class TimerBar extends StatelessWidget {
  const TimerBar({required this.timer, required this.onStop, super.key});

  final TimerState timer;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final finished = timer.isFinished;

    // Nel countdown conta il tempo che manca; nel cronometro senza time cap
    // conta quello trascorso.
    final display = timer.spec.isCountUp
        ? timer.elapsed
        : (timer.remaining ?? Duration.zero);

    return SurfaceCard(
      color: context.colors.inkSurface,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _caption(l10n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.meta.copyWith(color: context.colors.lime),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  finished ? l10n.workoutTimerFinished : display.clock,
                  style: context.type.clock,
                ),
                if (!timer.spec.isCountUp) ...[
                  const SizedBox(height: AppSpacing.md),
                  ProgressLine(
                    value: timer.progress,
                    color: context.colors.lime,
                    track: context.colors.onInkSurface.withValues(alpha: 0.24),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          PillButton.compact(
            label: l10n.workoutStopTimer,
            tone: PillTone.accent,
            onPressed: onStop,
            leading: Container(
              height: 12,
              width: 12,
              decoration: BoxDecoration(
                color: context.colors.inkSurface,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _caption(AppLocalizations l10n) {
    final parts = <String>[
      if ((timer.spec.label ?? '').isNotEmpty) timer.spec.label!,
      if (timer.totalRounds > 1)
        l10n.workoutTimerRound(timer.round, timer.totalRounds),
      if (timer.spec.kind == TimerKind.tabata)
        timer.phase == TimerPhase.work
            ? l10n.workoutTimerWork
            : l10n.workoutTimerRest
      else if (timer.spec.kind == TimerKind.rest)
        l10n.workoutTimerRest,
    ];
    return parts.join(' · ');
  }
}

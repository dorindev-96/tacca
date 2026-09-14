import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/widgets/linear_icon.dart';
import '../../../core/widgets/meta_chip.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../data/entities/workout_log.dart';
import '../../../l10n/app_localizations.dart';
import '../cubit/active_session_cubit.dart';

/// La sessione rimasta aperta, in cima all'archivio schede: si tocca e si
/// torna dentro all'allenamento (RF-06).
///
/// Sta nella testata e non nella lista perché è un'uscita di sicurezza: se
/// scorresse via con le schede, ritrovare il proprio allenamento tornerebbe a
/// dipendere da dove si è fermato lo scroll.
///
/// Non è lime: l'accento della schermata è già della scheda in uso, e due
/// evidenze insieme non ne fanno nessuna. A dire che qui c'è qualcosa di vivo
/// bastano il disco con il triangolo e il posto che occupa.
class ActiveSessionCard extends StatelessWidget {
  const ActiveSessionCard({
    required this.log,
    required this.onResume,
    super.key,
  });

  final WorkoutLog log;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final day = log.dayLabelSnapshot.trim();

    return SurfaceCard(
      onTap: onResume,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.card,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.fill,
            ),
            child: Center(
              child: LinearIcon(
                AppIcons.play,
                size: 20,
                color: context.colors.ink,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.workoutActiveSessionLabel, style: context.type.meta),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  log.planNameSnapshot,
                  style: context.type.rowStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    if (day.isNotEmpty) MetaChip(label: day),
                    MetaChip(
                      icon: AppIcons.calendar,
                      label: l10n.workoutActiveSessionStartedAt(log.startedAt),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          LinearIcon(
            AppIcons.chevronRight,
            size: 20,
            color: context.colors.muted,
          ),
        ],
      ),
    );
  }
}

/// La [ActiveSessionCard] attaccata a [ActiveSessionCubit]: si disegna da sé
/// solo quando una sessione è aperta, e sparisce appena viene chiusa.
///
/// È un widget a parte perché così a ridisegnarsi a ogni autosave della
/// sessione è la card, non l'intera schermata che la ospita.
class ActiveSessionBanner extends StatelessWidget {
  const ActiveSessionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final log = context.watch<ActiveSessionCubit>().state.log;
    if (log == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: ActiveSessionCard(
        log: log,
        onResume: () => context.push('/workout/${log.id}'),
      ),
    );
  }
}

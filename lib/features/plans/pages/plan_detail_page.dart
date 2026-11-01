import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart' hide Block;

import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/extensions/share_origin.dart';
import '../../../core/widgets/app_menu.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/linear_icon.dart';
import '../../../core/widgets/meta_chip.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/square_icon_button.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../data/entities/workout_plan.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/share/image_share_service.dart';
import '../../workout/cubit/active_session_cubit.dart';
import '../../workout/widgets/active_session_sheet.dart';
import '../../workout/widgets/day_picker_sheet.dart';
import '../cubit/plans_cubit.dart';
import '../widgets/plan_day_view.dart';
import '../widgets/plan_list_tile.dart';
import '../widgets/plan_share_image.dart';

/// Consultazione di una scheda (RF-01): sola lettura, con azioni di lista
/// disponibili anche da qui. Legge da [PlansCubit] (già in memoria, niente
/// nuovo Cubit dedicato: vedi nota in `app/di.dart`).
///
/// Il titolo sta nel contenuto e non nella testata: è lungo, va a capo, e
/// mentre si scorre la scheda serve lo spazio, non il promemoria del nome.
class PlanDetailPage extends StatelessWidget {
  const PlanDetailPage({required this.planId, super.key});

  final int planId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final plan = context.watch<PlansCubit>().state.planById(planId);

    if (plan == null) {
      return AppScaffold(
        leading: const AppBackButton(),
        body: EmptyState(
          icon: AppIcons.search,
          message: l10n.planEditorPlanNotFound,
        ),
      );
    }

    final cubit = context.read<PlansCubit>();
    final showDayLabels = plan.days.length > 1;

    return AppScaffold(
      leading: const AppBackButton(),
      actions: [
        SquareIconButton(
          icon: AppIcons.pencil,
          tooltip: l10n.planDetailEditAction,
          onPressed: () => context.push('/plans/${plan.id}/edit'),
        ),
        AppMenuButton<PlanAction>(
          onSelected: (action) => _handle(context, cubit, plan, action, l10n),
          // La modifica qui non sta nel menu: è il pulsante accanto.
          itemBuilder: (context) => planMenuItems(l10n, plan, share: true),
        ),
      ],
      dock: plan.days.isEmpty
          ? null
          : PillButton(
              label: l10n.workoutStartAction,
              icon: AppIcons.play,
              onPressed: () => _startWorkout(context, plan),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.actionClearance,
        ),
        children: [
          Text(plan.name, style: context.type.screenTitle),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              MetaChip(
                icon: AppIcons.calendar,
                label: l10n.plansDaysCount(plan.days.length),
                tone: ChipTone.onBackground,
                small: false,
              ),
              if (plan.isActive)
                MetaChip(
                  icon: AppIcons.check,
                  label: l10n.plansInUseBadge,
                  tone: ChipTone.accent,
                  small: false,
                ),
              if (plan.isArchived)
                MetaChip(
                  label: l10n.plansSectionArchived,
                  tone: ChipTone.onBackground,
                  small: false,
                ),
            ],
          ),
          if ((plan.description ?? '').isNotEmpty)
            Section(
              label: l10n.planDetailDescriptionLabel,
              child: ProseCard(plan.description!),
            ),
          if ((plan.notes ?? '').isNotEmpty)
            Section(
              label: l10n.planDetailNotesLabel,
              child: ProseCard(plan.notes!),
            ),
          if (plan.imagePaths.isNotEmpty)
            Section(
              // Immagini originali dell'import AI, riapribili in qualsiasi
              // momento (RF-03).
              child: SurfaceCard(
                onTap: () =>
                    context.push('/plan-images', extra: plan.imagePaths),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.card,
                  vertical: AppSpacing.lg,
                ),
                child: Row(
                  children: [
                    LinearIcon(
                      AppIcons.gallery,
                      size: 20,
                      color: context.colors.muted,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        l10n.planDetailImagesLabel(plan.imagePaths.length),
                        style: context.type.row,
                      ),
                    ),
                    LinearIcon(
                      AppIcons.chevronRight,
                      size: 20,
                      color: context.colors.muted,
                    ),
                  ],
                ),
              ),
            ),
          for (final day in plan.days)
            PlanDaySection(day: day, showLabel: showDayLabels),
        ],
      ),
    );
  }

  /// Avvia la sessione (RF-06). La scelta del giorno compare solo sulle schede
  /// multi-giorno: quella a giorno singolo ne ha uno implicito (§5.1).
  ///
  /// Un allenamento per volta: se ce n'è già uno aperto si decide prima cosa
  /// farne, e lo si decide **qui**, prima di scegliere il giorno — non ha
  /// senso far scegliere un giorno per una sessione che potrebbe non
  /// nascere. A chiudere quello vecchio è poi `startSession`, cioè solo se e
  /// quando la nuova parte: rinunciare da questo pannello non tocca niente.
  Future<void> _startWorkout(BuildContext context, WorkoutPlan plan) async {
    final active = context.read<ActiveSessionCubit>().currentSession();
    if (active != null) {
      final choice = await showActiveSessionSheet(context, active: active);
      if (choice == null || !context.mounted) return;
      if (choice == ActiveSessionChoice.resume) {
        context.push('/workout/${active.id}');
        return;
      }
    }

    final days = plan.days.toList();
    var dayId = days.first.id;
    if (days.length > 1) {
      final chosen = await showDayPickerSheet(context, days: days);
      if (chosen == null || !context.mounted) return;
      dayId = chosen;
    }
    if (!context.mounted) return;
    context.push('/workout/new?planId=${plan.id}&dayId=$dayId');
  }

  /// Esporta la scheda **intera** come immagine e la passa al foglio di
  /// condivisione (RF-01): è il modo in cui una scheda esce dall'app verso chi
  /// non ce l'ha installata — una chat, non un formato da reimportare.
  ///
  /// L'immagine non è uno screenshot: la pagina è più alta dello schermo e di
  /// un `ListView` esiste solo la parte visibile. Viene ridisegnata da capo
  /// fuori dall'albero ([PlanShareImage]), a larghezza fissa; se è lunga si
  /// divide in più pagine, che partono tutte insieme.
  ///
  /// Il rettangolo passato al servizio è quello della pagina: su iPad il
  /// foglio di condivisione è un popover e senza un'ancora compare dove
  /// capita.
  Future<void> _shareAsImage(
    BuildContext context,
    WorkoutPlan plan,
    AppLocalizations l10n,
  ) async {
    final sharer = context.read<ImageShareService>();
    final messenger = ScaffoldMessenger.of(context);
    final poster = PlanShareImage(
      plan: plan,
      locale: Localizations.localeOf(context),
      brightness: Theme.of(context).brightness,
    );
    final origin = context.shareOrigin;

    try {
      await sharer.sharePagedImage(
        image: poster,
        fileName: _imageFileName(plan.name, l10n),
        text: plan.name,
        originRect: origin,
      );
    } on Exception {
      messenger.showMessage(l10n.planShareFailed);
    }
  }

  /// Nome del file che vedrà chi riceve l'immagine, senza estensione: il
  /// nome della scheda ridotto ai caratteri che sopravvivono a un file system
  /// e a una chat. Estensione e numero di pagina li aggiunge il servizio.
  String _imageFileName(String planName, AppLocalizations l10n) {
    final slug = planName
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp('^-+|-+\$'), '');
    final name = slug.isEmpty ? l10n.planShareFileNameFallback : slug;
    return name.length <= 60 ? name : name.substring(0, 60);
  }

  Future<void> _handle(
    BuildContext context,
    PlansCubit cubit,
    WorkoutPlan plan,
    PlanAction action,
    AppLocalizations l10n,
  ) async {
    switch (action) {
      case PlanAction.setActive:
        cubit.setActivePlan(plan.id);
      case PlanAction.edit:
        context.push('/plans/${plan.id}/edit');
      case PlanAction.duplicate:
        cubit.duplicatePlan(plan.id);
      case PlanAction.archiveToggle:
        cubit.setArchived(plan.id, archived: !plan.isArchived);
      case PlanAction.share:
        await _shareAsImage(context, plan, l10n);
      case PlanAction.delete:
        if (await confirmPlanDelete(context, plan) && context.mounted) {
          cubit.deletePlan(plan.id);
          Navigator.of(context).pop();
        }
    }
  }
}

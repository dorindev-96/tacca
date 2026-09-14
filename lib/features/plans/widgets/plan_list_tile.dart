import 'package:flutter/material.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/widgets/app_field.dart';
import '../../../core/widgets/app_menu.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/linear_icon.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../data/entities/workout_plan.dart';
import '../../../l10n/app_localizations.dart';

enum _PlanAction { setActive, edit, duplicate, archiveToggle, delete }

/// Riga dell'archivio schede (RF-01): apertura al tap, azioni nel menu.
///
/// La scheda in uso è l'unica lime della lista — e dell'intera schermata: un
/// solo elemento in evidenza, altrimenti non è più in evidenza nulla. Porta
/// anche un disco bianco con la spunta e il nome in peso forte, così si
/// riconosce anche a colori spenti.
class PlanListTile extends StatelessWidget {
  const PlanListTile({
    required this.plan,
    required this.onOpen,
    required this.onEdit,
    required this.onDuplicate,
    required this.onArchiveToggle,
    required this.onDelete,
    this.onSetActive,
    this.highlighted = false,
    super.key,
  });

  final WorkoutPlan plan;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onArchiveToggle;
  final VoidCallback onDelete;

  /// Null quando l'azione non ha senso (già in uso, oppure scheda archiviata).
  final VoidCallback? onSetActive;

  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final days = l10n.plansDaysCount(plan.days.length);

    final menu = AppMenuButton<_PlanAction>(
      shape: MenuButtonShape.ghost,
      onSelected: (action) => _handle(context, action),
      itemBuilder: (context) => [
        if (onSetActive != null)
          appMenuItem(
            value: _PlanAction.setActive,
            label: l10n.plansActionSetActive,
          ),
        appMenuItem(value: _PlanAction.edit, label: l10n.plansActionEdit),
        appMenuItem(
          value: _PlanAction.duplicate,
          label: l10n.plansActionDuplicate,
        ),
        appMenuItem(
          value: _PlanAction.archiveToggle,
          label: plan.isArchived
              ? l10n.plansActionRestore
              : l10n.plansActionArchive,
        ),
        appMenuItem(
          value: _PlanAction.delete,
          label: l10n.plansActionDelete,
          icon: AppIcons.trash,
          destructive: true,
        ),
      ],
    );

    if (highlighted) {
      return SurfaceCard(
        color: context.colors.lime,
        onTap: onOpen,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.card,
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
        ),
        child: Row(
          children: [
            Container(
              height: 32,
              width: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Il pallino sta sul lime, e il lime è uguale nei due temi:
                // resta chiaro anche al buio, o la stessa card sembrerebbe
                // due card diverse.
                color: context.colors.onLimeSurface,
              ),
              child: Center(
                child: LinearIcon(
                  AppIcons.check,
                  size: 20,
                  color: context.colors.onLime,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.name,
                    style: context.type.rowStrong.copyWith(
                      color: context.colors.onLime,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    days,
                    style: context.type.chip.copyWith(
                      color: context.colors.onLime,
                    ),
                  ),
                ],
              ),
            ),
            menu,
          ],
        ),
      );
    }

    final row = SurfaceCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.card,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          children: [
            Expanded(
              child: Text(
                plan.name,
                style: context.type.row,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(days, style: context.type.meta),
            menu,
          ],
        ),
      ),
    );

    // Le archiviate restano leggibili ma spente: sono lì per essere
    // ritrovate, non per essere usate.
    return plan.isArchived ? Opacity(opacity: 0.72, child: row) : row;
  }

  Future<void> _handle(BuildContext context, _PlanAction action) async {
    switch (action) {
      case _PlanAction.setActive:
        onSetActive?.call();
      case _PlanAction.edit:
        onEdit();
      case _PlanAction.duplicate:
        onDuplicate();
      case _PlanAction.archiveToggle:
        onArchiveToggle();
      case _PlanAction.delete:
        await _confirmDelete(context);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.plansDeleteConfirmTitle,
      message: l10n.plansDeleteConfirmBody(plan.name),
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (confirmed) onDelete();
  }
}

/// Campo di ricerca dell'archivio: pillola bianca alta 48 con la lente in
/// testa, senza contorno.
class PlanSearchField extends StatelessWidget {
  const PlanSearchField({required this.onChanged, super.key});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return TextField(
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: context.type.row,
      decoration: AppField.onBackground(
        context,
        hintText: l10n.plansSearchHint,
        prefixIcon: LinearIcon(
          AppIcons.search,
          size: 20,
          color: context.colors.muted,
        ),
      ),
    );
  }
}

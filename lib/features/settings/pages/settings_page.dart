import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/l10n/language_names.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/linear_icon.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../l10n/app_localizations.dart';
import '../cubit/locale_cubit.dart';

/// Impostazioni (RF-08): punto d'ingresso della configurazione AI.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selected = context.watch<LocaleCubit>().state;

    return AppScaffold(
      title: l10n.settingsTitle,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.tabBarClearance,
        ),
        children: [
          SettingsTile(
            // Il set "Linear Icons" del design non ha un mappamondo: finché
            // non arriva, la lingua la segna il glifo del testo.
            icon: AppIcons.lines,
            title: l10n.settingsLanguageTile,
            subtitle: selected == null
                ? l10n.settingsLanguageSystem
                : languageNameOf(selected),
            onTap: () => _chooseLanguage(context, selected),
          ),
          const SizedBox(height: AppSpacing.sm),
          SettingsTile(
            icon: AppIcons.cpu,
            title: l10n.settingsAiTile,
            subtitle: l10n.settingsAiTileSubtitle,
            onTap: () => context.push('/settings/ai'),
          ),
          const SizedBox(height: AppSpacing.sm),
          SettingsTile(
            icon: AppIcons.shield,
            title: l10n.settingsLegalTile,
            subtitle: l10n.settingsLegalTileSubtitle,
            onTap: () => context.push('/settings/legal'),
          ),
        ],
      ),
    );
  }

  /// Pannello di scelta della lingua: "come il sistema" in cima e poi le
  /// lingue tradotte, ciascuna scritta nella propria lingua.
  ///
  /// L'elenco è quello generato dagli ARB, non una copia a mano: una
  /// traduzione nuova compare qui da sola.
  Future<void> _chooseLanguage(BuildContext context, Locale? selected) async {
    final cubit = context.read<LocaleCubit>();
    final l10n = AppLocalizations.of(context);

    final choice = await showAppSheet<_LanguageChoice>(
      context,
      builder: (sheetContext) => AppSheet(
        title: l10n.settingsLanguageSheetTitle,
        scrollable: true,
        children: [
          _LanguageTile(
            title: l10n.settingsLanguageSystem,
            subtitle: l10n.settingsLanguageSystemSubtitle,
            selected: selected == null,
            onTap: () =>
                Navigator.of(sheetContext).pop(const _LanguageChoice(null)),
          ),
          for (final locale in AppLocalizations.supportedLocales)
            _LanguageTile(
              title: languageNameOf(locale),
              selected: selected?.languageCode == locale.languageCode,
              onTap: () =>
                  Navigator.of(sheetContext).pop(_LanguageChoice(locale)),
            ),
        ],
      ),
    );

    if (choice != null) await cubit.select(choice.locale);
  }
}

/// Esito del pannello. Serve un involucro perché `null` è una scelta valida
/// ("come il sistema") e non si distinguerebbe dal pannello chiuso con la X.
class _LanguageChoice {
  const _LanguageChoice(this.locale);

  final Locale? locale;
}

/// Riga del pannello delle lingue: `SheetOption` con la spunta al posto
/// dell'icona sulla lingua attiva.
///
/// Il lime marca la scelta corrente, ed è l'unico del pannello: dentro uno
/// sheet "cosa è vivo adesso" è la riga selezionata.
class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SheetOption(
        icon: selected ? AppIcons.check : AppIcons.lines,
        title: title,
        subtitle: subtitle,
        highlighted: selected,
        onTap: onTap,
      ),
    );
  }
}

/// Riga delle impostazioni: quadratino con l'icona, titolo, spiegazione e la
/// freccia che dice che porta da qualche parte.
///
/// Il quadratino è **neutro**, non lime: in questa schermata il lime ce l'ha
/// già la tab attiva, e da quando le righe sono più di una un accento per
/// riga si annullerebbe da solo (regola del design: un solo lime per
/// schermata).
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    super.key,
  });

  final LinearIconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.card,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: AppColors.fill,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Center(child: LinearIcon(icon, color: AppColors.ink)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.rowStrong),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle!, style: AppTypography.paragraphSmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const LinearIcon(
            AppIcons.chevronRight,
            size: 20,
            color: AppColors.muted,
          ),
        ],
      ),
    );
  }
}

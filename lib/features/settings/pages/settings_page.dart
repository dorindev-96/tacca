import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/l10n/language_names.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/linear_icon.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../l10n/app_localizations.dart';
import '../cubit/locale_cubit.dart';
import '../cubit/theme_mode_cubit.dart';

/// Impostazioni (RF-08): punto d'ingresso della configurazione AI.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selected = context.watch<LocaleCubit>().state;
    final themeMode = context.watch<ThemeModeCubit>().state;

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
            // Nemmeno un sole o una luna: come per la lingua, finché il glifo
            // non arriva dal file di design si usa quello che c'è, invece di
            // infilare un'icona Material fra queste forme.
            icon: AppIcons.eye,
            title: l10n.settingsThemeTile,
            subtitle: _themeLabel(l10n, themeMode),
            onTap: () => _chooseTheme(context, themeMode),
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
          _ChoiceTile(
            icon: AppIcons.lines,
            title: l10n.settingsLanguageSystem,
            subtitle: l10n.settingsLanguageSystemSubtitle,
            selected: selected == null,
            onTap: () =>
                Navigator.of(sheetContext).pop(const _LanguageChoice(null)),
          ),
          for (final locale in AppLocalizations.supportedLocales)
            _ChoiceTile(
              icon: AppIcons.lines,
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

  /// Pannello di scelta del tema: "come il sistema" in cima, poi chiaro e
  /// scuro.
  ///
  /// Qui non serve l'involucro che serve alla lingua: "come il sistema" ha un
  /// nome suo ([ThemeMode.system]), quindi si distingue da sé dal pannello
  /// chiuso con la X, che torna `null`.
  Future<void> _chooseTheme(BuildContext context, ThemeMode selected) async {
    final cubit = context.read<ThemeModeCubit>();
    final l10n = AppLocalizations.of(context);

    final choice = await showAppSheet<ThemeMode>(
      context,
      builder: (sheetContext) => AppSheet(
        title: l10n.settingsThemeSheetTitle,
        children: [
          for (final mode in ThemeMode.values)
            _ChoiceTile(
              icon: AppIcons.eye,
              title: _themeLabel(l10n, mode),
              subtitle: mode == ThemeMode.system
                  ? l10n.settingsThemeSystemSubtitle
                  : null,
              selected: mode == selected,
              onTap: () => Navigator.of(sheetContext).pop(mode),
            ),
        ],
      ),
    );

    if (choice != null) await cubit.select(choice);
  }

  /// Il nome di un [ThemeMode] nella lingua dell'interfaccia. Sta qui e non in
  /// `core/` perché sono tre stringhe ARB, non un elenco di dati come gli
  /// endonimi delle lingue.
  static String _themeLabel(AppLocalizations l10n, ThemeMode mode) =>
      switch (mode) {
        ThemeMode.system => l10n.settingsThemeSystem,
        ThemeMode.light => l10n.settingsThemeLight,
        ThemeMode.dark => l10n.settingsThemeDark,
      };
}

/// Esito del pannello. Serve un involucro perché `null` è una scelta valida
/// ("come il sistema") e non si distinguerebbe dal pannello chiuso con la X.
class _LanguageChoice {
  const _LanguageChoice(this.locale);

  final Locale? locale;
}

/// Riga di un pannello di scelta (lingua, tema): `SheetOption` con la spunta
/// al posto dell'icona sulla voce attiva.
///
/// Il lime marca la scelta corrente, ed è l'unico del pannello: dentro uno
/// sheet "cosa è vivo adesso" è la riga selezionata.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  /// Il glifo delle voci non scelte: quella scelta porta la spunta.
  final LinearIconData icon;

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SheetOption(
        icon: selected ? AppIcons.check : icon,
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
              color: context.colors.fill,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Center(child: LinearIcon(icon, color: context.colors.ink)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.type.rowStrong),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle!, style: context.type.paragraphSmall),
                ],
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

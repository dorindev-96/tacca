import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/widgets/app_field.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/linear_icon.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/square_icon_button.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/ai/ai_provider.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';

/// Configurazione AI (RF-08): provider, API key, modello — entrambi dal
/// catalogo JSON — test connessione e avviso privacy.
///
/// Provider e modello sono due tendine sole: l'elenco viene da
/// `assets/ai/models.json`, la pagina non sa quali provider esistano.
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final _keyController = TextEditingController();

  /// Mostra il campo key anche quando una key è già salvata ("Sostituisci").
  bool _editingKey = false;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AppScaffold(
      leading: const AppBackButton(),
      title: l10n.aiSettingsTitle,
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final cubit = context.read<SettingsCubit>();
          final catalog = cubit.catalog;
          final provider = cubit.selectedProvider;
          final selectedModel = state.selectedModelId == null
              ? null
              : provider.byId(state.selectedModelId!);

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.xxl,
            ),
            children: [
              // Avviso esplicito richiesto da RF-08: i contenuti inviati
              // all'AI lasciano il dispositivo, e verso chi.
              InfoBanner(message: l10n.aiSettingsPrivacyNotice(provider.label)),
              if (!state.hasApiKey) ...[
                const SizedBox(height: AppSpacing.sm),
                InfoBanner(
                  icon: AppIcons.lock,
                  tone: InfoBannerTone.alert,
                  message: l10n.aiSettingsDisabledBanner,
                ),
              ],
              Section(
                label: l10n.aiSettingsProviderLabel,
                child: _Dropdown<AiProviderId>(
                  value: provider.id,
                  icon: AppIcons.cpu,
                  items: {
                    for (final option in catalog.providers)
                      option.id: option.label,
                  },
                  onChanged: cubit.selectProvider,
                ),
              ),
              Section(
                label: l10n.aiSettingsKeyLabel(provider.label),
                child: state.hasApiKey && !_editingKey
                    ? _SavedKeyTile(
                        onReplace: () => setState(() => _editingKey = true),
                        onRemove: () => _confirmRemoveKey(context),
                      )
                    : _KeyEditor(
                        controller: _keyController,
                        hintText: provider.keyHint ?? l10n.aiSettingsKeyHint,
                        onSave: () async {
                          await cubit.saveApiKey(_keyController.text);
                          _keyController.clear();
                          if (mounted) setState(() => _editingKey = false);
                        },
                      ),
              ),
              Section(
                label: l10n.aiSettingsModelLabel,
                child: _Dropdown<String>(
                  value: selectedModel?.id,
                  items: {
                    for (final model in provider.models) model.id: model.label,
                  },
                  onChanged: cubit.selectModel,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _TestConnectionSection(state: state),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmRemoveKey(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<SettingsCubit>();
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.aiSettingsKeyRemoveConfirmTitle,
      message: l10n.aiSettingsKeyRemoveConfirmBody,
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (confirmed) await cubit.removeApiKey();
  }
}

class _SavedKeyTile extends StatelessWidget {
  const _SavedKeyTile({required this.onReplace, required this.onRemove});

  final VoidCallback onReplace;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                height: 32,
                width: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.lime,
                ),
                child: Center(
                  child: LinearIcon(
                    AppIcons.check,
                    size: 18,
                    color: context.colors.onLime,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  l10n.aiSettingsKeySaved,
                  style: context.type.paragraph,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: PillButton.compact(
                  label: l10n.aiSettingsKeyReplace,
                  tone: PillTone.outline,
                  expand: true,
                  onPressed: onReplace,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: PillButton.compact(
                  label: l10n.commonDelete,
                  tone: PillTone.danger,
                  expand: true,
                  onPressed: onRemove,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Inserimento della key: nascosta di default, con l'occhio per rileggerla
/// prima di salvare (si incolla, e un carattere di troppo non si vede).
class _KeyEditor extends StatefulWidget {
  const _KeyEditor({
    required this.controller,
    required this.hintText,
    required this.onSave,
  });

  final TextEditingController controller;

  /// Placeholder che mostra la forma della key del provider scelto
  /// (`sk-or-…`, `sk-ant-…`): viene dal catalogo, non dalle traduzioni.
  final String hintText;

  final VoidCallback onSave;

  @override
  State<_KeyEditor> createState() => _KeyEditorState();
}

class _KeyEditorState extends State<_KeyEditor> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          obscureText: _obscured,
          autocorrect: false,
          enableSuggestions: false,
          style: context.type.row,
          decoration: AppField.onBackground(
            context,
            hintText: widget.hintText,
            prefixIcon: LinearIcon(
              AppIcons.lock,
              size: 20,
              color: context.colors.muted,
            ),
            suffixIcon: GhostIconButton(
              icon: AppIcons.eye,
              foreground: context.colors.muted,
              tooltip: l10n.aiSettingsKeyReveal,
              onPressed: () => setState(() => _obscured = !_obscured),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        PillButton(label: l10n.commonSave, onPressed: widget.onSave),
      ],
    );
  }
}

class _TestConnectionSection extends StatelessWidget {
  const _TestConnectionSection({required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final testing = state.testStatus == AiConnectionTestStatus.testing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PillButton(
          label: l10n.aiSettingsTestConnection,
          icon: AppIcons.shield,
          tone: PillTone.outline,
          onPressed: state.hasApiKey && !testing
              ? () => context.read<SettingsCubit>().testConnection()
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        switch (state.testStatus) {
          AiConnectionTestStatus.testing => const Center(
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          AiConnectionTestStatus.success => Row(
            children: [
              LinearIcon(AppIcons.check, size: 20, color: context.colors.ink),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.aiSettingsTestSuccess,
                  style: context.type.paragraph,
                ),
              ),
            ],
          ),
          AiConnectionTestStatus.failure => InfoBanner(
            tone: InfoBannerTone.alert,
            message: state.testErrorMessage ?? '',
          ),
          _ => const SizedBox.shrink(),
        },
      ],
    );
  }
}

/// L'unica forma di tendina della pagina: provider e modello si scelgono
/// così. Gli stili vengono dal tema (design system), qui si passa solo il
/// contenuto.
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    this.icon,
  });

  final T? value;

  /// Valore → etichetta mostrata, nell'ordine del catalogo.
  final Map<T, String> items;

  final ValueChanged<T> onChanged;

  /// Icona a sinistra del campo (facoltativa).
  final LinearIconData? icon;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      style: context.type.row,
      borderRadius: BorderRadius.circular(AppSpacing.card),
      icon: LinearIcon(
        AppIcons.chevronDown,
        size: 20,
        color: context.colors.muted,
      ),
      decoration: AppField.onBackground(
        context,
        prefixIcon: switch (icon) {
          final glyph? => LinearIcon(
            glyph,
            size: 20,
            color: context.colors.muted,
          ),
          null => null,
        },
      ),
      items: [
        for (final entry in items.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text(entry.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../design/app_radius.dart';
import '../design/app_spacing.dart';
import '../design/linear_icons.dart';
import '../design/theme_context.dart';
import 'linear_icon.dart';

/// Le due forme di campo del restyling.
///
/// Non ce ne sono altre, e nessuna delle due ha un contorno: la forma la fa
/// il colore del riempimento. Riempimento, spaziatura interna e stile del
/// suggerimento vengono da `inputDecorationTheme`: qui c'è solo ciò in cui le
/// due forme se ne staccano.
abstract final class AppField {
  /// Campo che sta **sul fondo pagina**: pillola al colore delle card, raggio
  /// 26, come il campo di ricerca dell'archivio.
  ///
  /// Prende il [context] perché i suoi colori vengono dal tema: è una
  /// decorazione, non un widget, quindi non ha un `build` da cui leggerli.
  static InputDecoration onBackground(
    BuildContext context, {
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      isDense: true,
      fillColor: context.colors.surface,
      prefixIcon: prefixIcon == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.card,
                right: AppSpacing.sm,
              ),
              child: prefixIcon,
            ),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      suffixIcon: suffixIcon,
      border: _border(AppRadius.lg),
      enabledBorder: _border(AppRadius.lg),
      focusedBorder: _border(AppRadius.lg),
    );
  }

  /// Campo "scavato" **dentro una superficie**: riempimento dell'incavo,
  /// raggio 20. È la forma dei campi degli sheet.
  static InputDecoration inset(
    BuildContext context, {
    String? hintText,
    String? labelText,
    EdgeInsetsGeometry? contentPadding,
  }) {
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      fillColor: context.colors.fill,
      contentPadding: contentPadding,
      border: _border(AppRadius.md),
      enabledBorder: _border(AppRadius.md),
      focusedBorder: _border(AppRadius.md),
      errorBorder: _border(AppRadius.md, color: context.colors.danger),
      focusedErrorBorder: _border(AppRadius.md, color: context.colors.danger),
    );
  }

  static OutlineInputBorder _border(double radius, {Color? color}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: color == null ? BorderSide.none : BorderSide(color: color),
    );
  }
}

/// L'unica forma di tendina dell'app: testo da riga, freccia lineare, menu
/// col raggio dei campi. Il campo intorno è una delle due forme di [AppField]
/// e lo sceglie chi la usa ([decoration]).
///
/// Flutter non ha un tema per `DropdownButtonFormField`: senza questo widget
/// freccia, stile e raggio del menu andrebbero ripetuti a ogni tendina.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.decoration,
    super.key,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final InputDecoration decoration;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      style: context.type.row,
      borderRadius: BorderRadius.circular(AppRadius.md),
      icon: LinearIcon(
        AppIcons.chevronDown,
        size: 20,
        color: context.colors.muted,
      ),
      decoration: decoration,
      items: items,
      onChanged: onChanged,
    );
  }
}

/// Etichetta sopra un campo: nel restyling i campi non hanno label
/// flottante, il nome sta fuori in grigio da 14.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(text, style: context.type.fieldLabel),
    );
  }
}

/// Campo con la propria etichetta sopra, nella forma "scavata".
class LabeledField extends StatelessWidget {
  const LabeledField({required this.label, required this.child, super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [FieldLabel(label), child],
    );
  }
}

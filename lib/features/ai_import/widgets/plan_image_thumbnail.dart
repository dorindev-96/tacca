import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/widgets/linear_icon.dart';
import '../../../l10n/app_localizations.dart';

/// Una foto scelta per l'import, con la X per toglierla.
///
/// La usano entrambe le strade dell'import (RF-03): quella che manda le
/// immagini al modello e quella che le fa leggere all'OCR del telefono.
class PlanImageThumbnail extends StatelessWidget {
  const PlanImageThumbnail({
    required this.bytes,
    required this.onRemove,
    super.key,
  });

  final Uint8List bytes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Image.memory(
            bytes,
            width: 104,
            height: 104,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: Material(
            color: context.colors.surface.withValues(alpha: 0.9),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onRemove,
              child: Tooltip(
                message: l10n.aiImportRemoveImage,
                child: SizedBox.square(
                  dimension: 32,
                  child: Center(
                    child: LinearIcon(
                      AppIcons.close,
                      size: 16,
                      color: context.colors.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

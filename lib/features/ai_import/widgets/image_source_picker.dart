import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../l10n/app_localizations.dart';
import 'plan_image_thumbnail.dart';

/// Le foto dell'import e i due modi di aggiungerne (fotocamera, galleria):
/// lo stesso primo passo per entrambe le strade dell'import (RF-03).
class ImageSourcePicker extends StatelessWidget {
  const ImageSourcePicker({
    required this.images,
    required this.onRemove,
    required this.onCamera,
    required this.onGallery,
    this.enabled = true,
    super.key,
  });

  final List<Uint8List> images;
  final ValueChanged<int> onRemove;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  /// Spento mentre le foto appena aggiunte sono ancora in lettura.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (images.isNotEmpty) ...[
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (var i = 0; i < images.length; i++)
                PlanImageThumbnail(
                  bytes: images[i],
                  onRemove: () => onRemove(i),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        Row(
          children: [
            Expanded(
              child: PillButton(
                label: l10n.aiImportSourceCamera,
                icon: AppIcons.camera,
                tone: PillTone.outline,
                onPressed: enabled ? onCamera : null,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: PillButton(
                label: l10n.aiImportSourceGallery,
                icon: AppIcons.gallery,
                tone: PillTone.outline,
                onPressed: enabled ? onGallery : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

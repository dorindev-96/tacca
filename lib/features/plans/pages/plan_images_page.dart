import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/square_icon_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/images/plan_image_store.dart';

/// Visualizzazione delle immagini originali allegate a una scheda (RF-03:
/// "dalla scheda salvata è possibile riaprire l'immagine originale").
class PlanImagesPage extends StatelessWidget {
  const PlanImagesPage({required this.imagePaths, super.key});

  /// Path relativi come salvati in `WorkoutPlan.imagePaths`.
  final List<String> imagePaths;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final imageStore = context.read<PlanImageStore>();

    return AppScaffold(
      leading: const AppBackButton(),
      title: l10n.planImagesTitle,
      body: PageView.builder(
        itemCount: imagePaths.length,
        itemBuilder: (context, index) => FutureBuilder<File>(
          future: imageStore.fileForRelativePath(imagePaths[index]),
          builder: (context, snapshot) {
            final file = snapshot.data;
            if (file == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return InteractiveViewer(
              maxScale: 6,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: Image.file(
                    file,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Text(
                        l10n.planImagesMissing,
                        style: context.type.sectionLabel,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

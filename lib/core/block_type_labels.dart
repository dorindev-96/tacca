import '../data/entities/block.dart';
import '../l10n/app_localizations.dart';

/// Etichetta localizzata per un [BlockType], condivisa tra editor e dettaglio.
String blockTypeLabel(AppLocalizations l10n, BlockType type) => switch (type) {
  BlockType.standard => l10n.blockTypeStandard,
  BlockType.superset => l10n.blockTypeSuperset,
  BlockType.circuit => l10n.blockTypeCircuit,
  BlockType.emom => l10n.blockTypeEmom,
  BlockType.amrap => l10n.blockTypeAmrap,
  BlockType.tabata => l10n.blockTypeTabata,
  BlockType.forTime => l10n.blockTypeForTime,
  BlockType.freeText => l10n.blockTypeFreeText,
};

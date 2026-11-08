import '../data/entities/block.dart';
import '../l10n/app_localizations.dart';

/// I parametri numerici dei blocchi, descritti **una volta sola**.
///
/// Sul [Block] sono campi piatti e nullable (§4); qui ciascuno porta tutto ciò
/// che serve a chi li tocca: come leggerlo e scriverlo, l'etichetta del campo
/// nell'editor, il testo con cui si legge nel dettaglio, nell'immagine
/// condivisa e in sessione, e il default per tipo. Quali parametri ha un tipo,
/// e in che ordine, lo dice [BlockParam.of].
///
/// Prima erano sei `switch` separati che dovevano restare d'accordo a mano, e
/// avevano già divergito: il dettaglio scriveva "Round: 3" con l'etichetta del
/// campo, la sessione "3 giri". Un parametro nuovo si aggiunge qui, e gli
/// `switch` esaustivi dicono al compilatore cosa manca.
///
/// Il testo libero del blocco `freeText` non è un parametro: non è un numero
/// e ha un campo suo.
enum BlockParam {
  rounds('rounds'),
  restBetweenRounds('restRounds'),
  interval('interval'),
  totalMinutes('totalMin'),
  duration('duration'),
  work('work'),
  rest('rest'),
  timeCap('timeCap');

  const BlockParam(this.fieldTag);

  /// Pezzo della key del campo nell'editor (`blk-<tag>-…`): stabile, perché
  /// cambiarla ricrea il campo e ne perde il cursore.
  final String fieldTag;

  /// I parametri di [type], nell'ordine in cui si scrivono e si leggono.
  static List<BlockParam> of(BlockType type) => switch (type) {
    BlockType.standard || BlockType.freeText => const [],
    BlockType.superset ||
    BlockType.circuit => const [rounds, restBetweenRounds],
    BlockType.emom => const [interval, totalMinutes],
    BlockType.amrap => const [duration],
    BlockType.tabata => const [work, rest, rounds],
    BlockType.forTime => const [timeCap],
  };

  int? read(Block block) => switch (this) {
    rounds => block.rounds,
    restBetweenRounds => block.restBetweenRoundsSeconds,
    interval => block.intervalSeconds,
    totalMinutes => block.totalMinutes,
    duration => block.durationSeconds,
    work => block.workSeconds,
    rest => block.restSeconds,
    timeCap => block.timeCapSeconds,
  };

  void write(Block block, int? value) {
    switch (this) {
      case rounds:
        block.rounds = value;
      case restBetweenRounds:
        block.restBetweenRoundsSeconds = value;
      case interval:
        block.intervalSeconds = value;
      case totalMinutes:
        block.totalMinutes = value;
      case duration:
        block.durationSeconds = value;
      case work:
        block.workSeconds = value;
      case rest:
        block.restSeconds = value;
      case timeCap:
        block.timeCapSeconds = value;
    }
  }

  /// Il valore con cui il parametro nasce in un blocco nuovo di [type]
  /// (§5.2). `null` dove è opzionale: il time cap di un For Time.
  int? defaultFor(BlockType type) => switch ((this, type)) {
    (rounds, BlockType.superset || BlockType.circuit) => 3,
    (restBetweenRounds, BlockType.superset || BlockType.circuit) => 60,
    (interval, BlockType.emom) => 60,
    (totalMinutes, BlockType.emom) => 10,
    (duration, BlockType.amrap) => 900,
    (work, BlockType.tabata) => 20,
    (rest, BlockType.tabata) => 10,
    (rounds, BlockType.tabata) => 8,
    _ => null,
  };

  /// Etichetta del campo nell'editor, con l'unità in cui si scrive.
  String fieldLabel(AppLocalizations l10n) => switch (this) {
    rounds => l10n.planEditorParamRounds,
    restBetweenRounds => l10n.planEditorParamRestBetweenRounds,
    interval => l10n.planEditorParamIntervalSeconds,
    totalMinutes => l10n.planEditorParamTotalMinutes,
    duration => l10n.planEditorParamDurationSeconds,
    work => l10n.planEditorParamWorkSeconds,
    rest => l10n.planEditorParamRestSeconds,
    timeCap => l10n.planEditorParamTimeCapSeconds,
  };

  /// Il parametro come si legge, con il suo [value]: "3 giri", "60s tra i
  /// giri". È la stessa frase nel dettaglio, nell'immagine e in sessione.
  String display(AppLocalizations l10n, int value) => switch (this) {
    rounds => l10n.blockParamRounds(value),
    restBetweenRounds => l10n.blockParamRestBetweenRounds(value),
    interval => l10n.blockParamInterval(value),
    totalMinutes => l10n.blockParamTotalMinutes(value),
    duration => l10n.blockParamDuration(value),
    work => l10n.blockParamWork(value),
    rest => l10n.blockParamRest(value),
    timeCap => l10n.blockParamTimeCap(value),
  };
}

/// I parametri di [block] da mostrare, già scritti e nell'ordine del tipo.
/// Quelli assenti o a zero non si mostrano: "0 giri" non dice niente.
List<String> blockParamTexts(AppLocalizations l10n, Block block) => [
  for (final param in BlockParam.of(block.type))
    if (param.read(block) case final value? when value > 0)
      param.display(l10n, value),
];

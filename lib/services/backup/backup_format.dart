import 'dart:convert';
import 'dart:typed_data';

import '../../core/errors/app_exception.dart';
import '../../data/entities/block.dart';
import '../../data/entities/exercise.dart';
import '../../data/entities/log_entry.dart';
import '../../data/entities/log_set.dart';
import '../../data/entities/workout_day.dart';
import '../../data/entities/workout_log.dart';
import '../../data/entities/workout_plan.dart';
import '../../data/repositories/backup_repository.dart';

/// Il formato del file di backup.
///
/// È **JSON Lines compresso con gzip**: una riga per record, ogni riga un
/// oggetto JSON. La prima è l'intestazione (marchio, versione, data e quanti
/// record seguono), poi una riga per scheda, una per allenamento e una per
/// immagine. Righe e non un unico documento JSON perché un backup con le foto
/// delle schede importate pesa decine di MB: così si scrive e si rilegge un
/// record alla volta, e la memoria non dipende da quanto è grande l'archivio.
/// gzip si riprende quasi tutto il terzo in più che le immagini pagano a
/// essere scritte in base64, e i dati delle schede si comprimono di parecchie
/// volte.
///
/// Gli id del database non viaggiano come id: sono solo riferimenti interni
/// al file (`ref`), che servono a collegare un allenamento alla sua scheda e
/// una scheda alle sue immagini. Al ripristino ogni oggetto ne prende uno
/// nuovo.
///
/// Le date sono ISO-8601 in UTC. I campi null non si scrivono.
abstract final class BackupFormat {
  /// Il marchio dell'intestazione: un file senza non è un backup di Tacca,
  /// qualunque estensione abbia.
  static const String id = 'tacca-backup';

  /// La versione del formato. Si alza solo quando una versione vecchia
  /// dell'app non saprebbe più leggere i backup nuovi: quella vecchia rifiuta
  /// allora il file con un messaggio chiaro invece di ripristinarne metà.
  static const int version = 1;

  /// L'estensione dei file. Non `.json`, perché il contenuto è compresso, e
  /// non `.gz`, perché le app che gestiscono file propongono di decomprimere
  /// un archivio appena lo si tocca: il backup deve restare un file solo, da
  /// riportare all'app così com'è.
  static const String extension = 'tacca';

  /// Il tipo dichiarato al foglio di condivisione: generico, perché le app
  /// che salvano file (Drive, File, la posta) accettano qualunque cosa sia
  /// dichiarata così, e nessuna prova ad aprire il backup al posto nostro.
  static const String mimeType = 'application/octet-stream';

  /// Il nome del file di un backup fatto a [time]: data e ora, così due
  /// backup della stessa giornata non si sovrascrivono.
  static String fileNameFor(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    final date = '${time.year}-${two(time.month)}-${two(time.day)}';
    return 'tacca-backup-$date-${two(time.hour)}${two(time.minute)}.$extension';
  }
}

/// Perché un file non si può ripristinare. Alla UI basta questo: il dettaglio
/// sta nel messaggio dell'eccezione, per chi legge i log.
enum BackupProblem {
  /// Non è un backup di Tacca: una foto, un PDF, un altro file qualsiasi.
  notABackup,

  /// È un backup fatto da una versione più recente dell'app, in un formato
  /// che questa non sa leggere.
  newerVersion,

  /// È un backup, ma rotto o incompleto: troncato da un download a metà,
  /// modificato a mano, rovinato per strada.
  damaged,
}

class BackupFormatException extends AppException {
  const BackupFormatException(this.problem, super.message);

  final BackupProblem problem;
}

/// L'intestazione di un backup: quando è stato fatto e quanti record lo
/// seguono. I conteggi non sono decorativi: un file troncato esattamente fra
/// due righe sarebbe ancora JSON valido, e solo il confronto con questi
/// numeri dice che manca qualcosa.
class BackupHeader {
  const BackupHeader({
    required this.createdAt,
    required this.plans,
    required this.logs,
    required this.images,
  });

  final DateTime createdAt;
  final int plans;
  final int logs;
  final int images;
}

/// Un'immagine letta dal backup: i byte da scrivere su disco e il
/// riferimento con cui le schede la nominano.
typedef BackupImage = ({int ref, Uint8List bytes});

/// Il contenuto di un backup letto e verificato, pronto per il ripristino.
class DecodedBackup {
  const DecodedBackup({
    required this.header,
    required this.data,
    required this.planImages,
  });

  final BackupHeader header;

  /// Schede e allenamenti, oggetti nuovi (id 0) già collegati fra loro.
  final BackupData data;

  /// Per ogni scheda di [data], i riferimenti delle sue immagini, in ordine.
  /// Le schede sono chiavi per identità: non hanno ancora un id.
  final Map<WorkoutPlan, List<int>> planImages;
}

/// Scrive i record di un backup, una riga JSON ciascuno (senza `\n`).
abstract final class BackupEncoder {
  static String header(BackupHeader header) => jsonEncode({
    'format': BackupFormat.id,
    'version': BackupFormat.version,
    'createdAt': _date(header.createdAt),
    'plans': header.plans,
    'logs': header.logs,
    'images': header.images,
  });

  /// Una scheda con tutto il suo albero. [images] sono i riferimenti delle
  /// sue immagini nel backup: solo quelle che ci sono finite davvero.
  static String plan(WorkoutPlan plan, {required List<int> images}) =>
      jsonEncode(
        _compact({
          'type': _planType,
          'ref': plan.id,
          'name': plan.name,
          'description': plan.description,
          'notes': plan.notes,
          'createdAt': _date(plan.createdAt),
          'updatedAt': _date(plan.updatedAt),
          'isArchived': plan.isArchived,
          'isActive': plan.isActive,
          'images': images,
          'days': [for (final day in plan.days) _day(day)],
        }),
      );

  /// Un allenamento. [planRef] e [dayRef] sono la scheda e il giorno a cui
  /// si riferisce, se ci sono ancora; altrimenti restano gli snapshot dei
  /// nomi, come nel database.
  static String log(WorkoutLog log, {int? planRef, int? dayRef}) => jsonEncode(
    _compact({
      'type': _logType,
      'plan': planRef,
      'day': dayRef,
      'startedAt': _date(log.startedAt),
      'finishedAt': log.finishedAt == null ? null : _date(log.finishedAt!),
      'status': log.dbStatus,
      'notes': log.notes,
      'planNameSnapshot': log.planNameSnapshot,
      'dayLabelSnapshot': log.dayLabelSnapshot,
      'entries': [
        for (final entry in log.entries)
          _compact({
            'exerciseNameSnapshot': entry.exerciseNameSnapshot,
            'sortOrder': entry.sortOrder,
            'sets': [
              for (final set in entry.sets)
                _compact({
                  'setNumber': set.setNumber,
                  'reps': set.reps,
                  'weightKg': set.weightKg,
                  'notes': set.notes,
                  'completedAt': _date(set.completedAt),
                }),
            ],
          }),
      ],
    }),
  );

  static String image(int ref, List<int> bytes) =>
      jsonEncode({'type': _imageType, 'ref': ref, 'data': base64Encode(bytes)});

  static Map<String, Object?> _day(WorkoutDay day) => _compact({
    'ref': day.id,
    'label': day.label,
    'notes': day.notes,
    'sortOrder': day.sortOrder,
    'blocks': [for (final block in day.blocks) _block(block)],
  });

  static Map<String, Object?> _block(Block block) => _compact({
    'type': block.dbType,
    'sortOrder': block.sortOrder,
    'notes': block.notes,
    'intervalSeconds': block.intervalSeconds,
    'totalMinutes': block.totalMinutes,
    'durationSeconds': block.durationSeconds,
    'workSeconds': block.workSeconds,
    'restSeconds': block.restSeconds,
    'rounds': block.rounds,
    'restBetweenRoundsSeconds': block.restBetweenRoundsSeconds,
    'timeCapSeconds': block.timeCapSeconds,
    'freeTextContent': block.freeTextContent,
    'exercises': [
      for (final exercise in block.exercises)
        _compact({
          'name': exercise.name,
          'sets': exercise.sets,
          'reps': exercise.reps,
          'load': exercise.load,
          'restSeconds': exercise.restSeconds,
          'durationSeconds': exercise.durationSeconds,
          'notes': exercise.notes,
          'sortOrder': exercise.sortOrder,
        }),
    ],
  });

  static Map<String, Object?> _compact(Map<String, Object?> map) => {
    for (final entry in map.entries)
      if (entry.value != null) entry.key: entry.value,
  };

  static String _date(DateTime value) => value.toUtc().toIso8601String();
}

const _planType = 'plan';
const _logType = 'log';
const _imageType = 'image';

/// Rilegge un backup riga per riga e alla fine ne restituisce il contenuto
/// verificato ([finish]).
///
/// È severo sulla struttura e accomodante sul resto: un campo obbligatorio
/// che manca, un tipo sbagliato, un riferimento a un'immagine che non c'è o
/// un conteggio che non torna rendono il backup `damaged` — il ripristino
/// sostituisce tutto, e deve sapere di avere davanti un archivio intero. Un
/// campo facoltativo assente vale null, come nel database.
///
/// Le immagini non restano qui: [add] le restituisce a chi legge, che le
/// scrive su disco subito, e si tiene solo il loro riferimento.
class BackupDecoder {
  BackupDecoder(this.header);

  final BackupHeader header;

  final _plans = <WorkoutPlan>[];
  final _planImages = Map<WorkoutPlan, List<int>>.identity();
  final _plansByRef = <int, WorkoutPlan>{};
  final _daysByRef = <int, WorkoutDay>{};
  final _logs = <({WorkoutLog log, int? planRef, int? dayRef})>[];
  final _imageRefs = <int>{};
  var _line = 1;

  /// Legge la prima riga di un file e dice se è l'intestazione di un backup
  /// che questa versione dell'app sa ripristinare.
  static BackupHeader readHeader(String line) {
    final Object? json;
    try {
      json = jsonDecode(line);
    } on FormatException {
      throw const BackupFormatException(
        BackupProblem.notABackup,
        'La prima riga non è JSON.',
      );
    }
    if (json is! Map<String, Object?> || json['format'] != BackupFormat.id) {
      throw const BackupFormatException(
        BackupProblem.notABackup,
        'Manca il marchio del backup.',
      );
    }

    final reader = _Reader(json, 'intestazione');
    final version = reader.integer('version');
    if (version > BackupFormat.version) {
      throw BackupFormatException(
        BackupProblem.newerVersion,
        'Formato $version, questa versione legge fino al '
        '${BackupFormat.version}.',
      );
    }
    return BackupHeader(
      createdAt: reader.date('createdAt'),
      plans: reader.count('plans'),
      logs: reader.count('logs'),
      images: reader.count('images'),
    );
  }

  /// Legge una riga dopo l'intestazione. Se è un'immagine ne restituisce i
  /// byte, da scrivere su disco; altrimenti null.
  BackupImage? add(String line) {
    _line++;
    final Object? json;
    try {
      json = jsonDecode(line);
    } on FormatException {
      throw BackupFormatException(
        BackupProblem.damaged,
        'Riga $_line: non è JSON.',
      );
    }
    if (json is! Map<String, Object?>) {
      throw BackupFormatException(
        BackupProblem.damaged,
        'Riga $_line: non è un oggetto.',
      );
    }

    final reader = _Reader(json, 'riga $_line');
    switch (reader.text('type')) {
      case _planType:
        _addPlan(reader);
        return null;
      case _logType:
        _addLog(reader);
        return null;
      case _imageType:
        return _addImage(reader);
      case final type:
        throw BackupFormatException(
          BackupProblem.damaged,
          'Riga $_line: tipo di record sconosciuto "$type".',
        );
    }
  }

  /// Verifica che il backup sia intero e coerente, e ne restituisce il
  /// contenuto.
  ///
  /// Qui si rimettono a posto anche le due regole che il database dà per
  /// scontate, nel caso un file modificato a mano le violi: una sola scheda
  /// in uso (e mai archiviata), un solo allenamento aperto.
  DecodedBackup finish() {
    if (_plans.length != header.plans ||
        _logs.length != header.logs ||
        _imageRefs.length != header.images) {
      throw BackupFormatException(
        BackupProblem.damaged,
        'Backup incompleto: ${_plans.length}/${header.plans} schede, '
        '${_logs.length}/${header.logs} allenamenti, '
        '${_imageRefs.length}/${header.images} immagini.',
      );
    }
    for (final refs in _planImages.values) {
      for (final ref in refs) {
        if (!_imageRefs.contains(ref)) {
          throw BackupFormatException(
            BackupProblem.damaged,
            'Una scheda nomina l\'immagine $ref, che nel backup non c\'è.',
          );
        }
      }
    }

    final logs = [
      for (final (:log, :planRef, :dayRef) in _logs)
        log
          ..plan.target = planRef == null ? null : _plansByRef[planRef]
          ..day.target = dayRef == null ? null : _daysByRef[dayRef],
    ];
    _keepOneActivePlan();
    _keepOneOpenSession(logs);

    return DecodedBackup(
      header: header,
      data: BackupData(plans: List.unmodifiable(_plans), logs: logs),
      planImages: _planImages,
    );
  }

  void _addPlan(_Reader reader) {
    final ref = reader.integer('ref');
    if (_plansByRef.containsKey(ref)) {
      throw BackupFormatException(
        BackupProblem.damaged,
        '${reader.where}: scheda $ref ripetuta.',
      );
    }

    final plan = WorkoutPlan(
      name: reader.text('name'),
      description: reader.optionalText('description'),
      notes: reader.optionalText('notes'),
      createdAt: reader.date('createdAt'),
      updatedAt: reader.date('updatedAt'),
      isArchived: reader.flag('isArchived'),
      isActive: reader.flag('isActive'),
    );
    for (final (index, day) in reader.objects('days').indexed) {
      plan.days.add(_day(day, index));
    }

    _plans.add(plan);
    _plansByRef[ref] = plan;
    _planImages[plan] = reader.integers('images');
  }

  WorkoutDay _day(_Reader reader, int index) {
    final ref = reader.integer('ref');
    if (_daysByRef.containsKey(ref)) {
      throw BackupFormatException(
        BackupProblem.damaged,
        '${reader.where}: giorno $ref ripetuto.',
      );
    }

    final day = WorkoutDay(
      label: reader.text('label'),
      notes: reader.optionalText('notes'),
      sortOrder: reader.optionalInteger('sortOrder') ?? index,
    );
    for (final (index, block) in reader.objects('blocks').indexed) {
      day.blocks.add(_block(block, index));
    }
    _daysByRef[ref] = day;
    return day;
  }

  Block _block(_Reader reader, int index) {
    final type = reader.text('type');
    if (!BlockType.values.any((value) => value.name == type)) {
      throw BackupFormatException(
        BackupProblem.damaged,
        '${reader.where}: tipo di blocco sconosciuto "$type".',
      );
    }

    final block =
        Block(
            dbType: type,
            sortOrder: reader.optionalInteger('sortOrder') ?? index,
            notes: reader.optionalText('notes'),
          )
          ..intervalSeconds = reader.optionalInteger('intervalSeconds')
          ..totalMinutes = reader.optionalInteger('totalMinutes')
          ..durationSeconds = reader.optionalInteger('durationSeconds')
          ..workSeconds = reader.optionalInteger('workSeconds')
          ..restSeconds = reader.optionalInteger('restSeconds')
          ..rounds = reader.optionalInteger('rounds')
          ..restBetweenRoundsSeconds = reader.optionalInteger(
            'restBetweenRoundsSeconds',
          )
          ..timeCapSeconds = reader.optionalInteger('timeCapSeconds')
          ..freeTextContent = reader.optionalText('freeTextContent');

    for (final (index, exercise) in reader.objects('exercises').indexed) {
      block.exercises.add(
        Exercise(
          name: exercise.text('name'),
          sets: exercise.optionalInteger('sets'),
          reps: exercise.optionalText('reps'),
          load: exercise.optionalText('load'),
          restSeconds: exercise.optionalInteger('restSeconds'),
          durationSeconds: exercise.optionalInteger('durationSeconds'),
          notes: exercise.optionalText('notes'),
          sortOrder: exercise.optionalInteger('sortOrder') ?? index,
        ),
      );
    }
    return block;
  }

  void _addLog(_Reader reader) {
    final status = reader.text('status');
    if (!WorkoutStatus.values.any((value) => value.name == status)) {
      throw BackupFormatException(
        BackupProblem.damaged,
        '${reader.where}: stato sconosciuto "$status".',
      );
    }

    final log = WorkoutLog(
      startedAt: reader.date('startedAt'),
      finishedAt: reader.optionalDate('finishedAt'),
      dbStatus: status,
      notes: reader.optionalText('notes'),
      planNameSnapshot: reader.text('planNameSnapshot'),
      dayLabelSnapshot: reader.text('dayLabelSnapshot'),
    );
    for (final (index, entry) in reader.objects('entries').indexed) {
      final logEntry = LogEntry(
        exerciseNameSnapshot: entry.text('exerciseNameSnapshot'),
        sortOrder: entry.optionalInteger('sortOrder') ?? index,
      );
      for (final set in entry.objects('sets')) {
        logEntry.sets.add(
          LogSet(
            setNumber: set.integer('setNumber'),
            reps: set.optionalText('reps'),
            weightKg: set.optionalNumber('weightKg'),
            notes: set.optionalText('notes'),
            completedAt: set.date('completedAt'),
          ),
        );
      }
      log.entries.add(logEntry);
    }

    // I riferimenti si risolvono in [finish]: le schede possono stare anche
    // dopo, e un riferimento a una scheda che non c'è vale "nessuna scheda",
    // come un riferimento debole del database.
    _logs.add((
      log: log,
      planRef: reader.optionalInteger('plan'),
      dayRef: reader.optionalInteger('day'),
    ));
  }

  BackupImage _addImage(_Reader reader) {
    final ref = reader.integer('ref');
    if (!_imageRefs.add(ref)) {
      throw BackupFormatException(
        BackupProblem.damaged,
        '${reader.where}: immagine $ref ripetuta.',
      );
    }
    try {
      return (ref: ref, bytes: base64Decode(reader.text('data')));
    } on FormatException {
      throw BackupFormatException(
        BackupProblem.damaged,
        '${reader.where}: immagine $ref illeggibile.',
      );
    }
  }

  /// Una scheda in uso al massimo, e mai fra le archiviate: se il file ne
  /// dichiara di più vince la modificata più di recente.
  void _keepOneActivePlan() {
    WorkoutPlan? keep;
    for (final plan in _plans) {
      if (plan.isArchived) plan.isActive = false;
      if (!plan.isActive) continue;
      if (keep == null || plan.updatedAt.isAfter(keep.updatedAt)) keep = plan;
    }
    for (final plan in _plans) {
      plan.isActive = identical(plan, keep);
    }
  }

  /// Un allenamento aperto al massimo, come garantisce `startSession`: se il
  /// file ne ha di più resta aperto il più recente, e gli altri si chiudono
  /// come interrotti all'ora della loro ultima serie.
  void _keepOneOpenSession(List<WorkoutLog> logs) {
    final open = logs
        .where((log) => log.status == WorkoutStatus.inProgress)
        .toList();
    if (open.length <= 1) return;

    open.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    for (final log in open.skip(1)) {
      var end = log.startedAt;
      for (final entry in log.entries) {
        for (final set in entry.sets) {
          if (set.completedAt.isAfter(end)) end = set.completedAt;
        }
      }
      log
        ..status = WorkoutStatus.aborted
        ..finishedAt = end;
    }
  }
}

/// Lettura tipata di un oggetto JSON del backup: ogni campo che non ha il
/// tipo atteso rende il backup `damaged`, con il punto esatto nel messaggio.
class _Reader {
  _Reader(this._json, this.where);

  final Map<String, Object?> _json;

  /// Dove si trova l'oggetto, per i messaggi ("riga 4, giorno 2").
  final String where;

  String text(String key) =>
      optionalText(key) ?? (throw _missing(key, 'un testo'));

  String? optionalText(String key) => _typed<String>(key, 'un testo');

  int integer(String key) =>
      optionalInteger(key) ?? (throw _missing(key, 'un intero'));

  /// Un conteggio dell'intestazione: un intero non negativo.
  int count(String key) {
    final value = integer(key);
    if (value < 0) throw _wrong(key, 'un intero non negativo');
    return value;
  }

  int? optionalInteger(String key) {
    final value = _json[key];
    if (value == null) return null;
    // JSON non distingue 3 da 3.0: un intero scritto con il punto è ancora
    // un intero.
    if (value is num && value == value.roundToDouble()) return value.toInt();
    throw _wrong(key, 'un intero');
  }

  double? optionalNumber(String key) =>
      _typed<num>(key, 'un numero')?.toDouble();

  bool flag(String key) => _typed<bool>(key, 'vero o falso') ?? false;

  DateTime date(String key) =>
      optionalDate(key) ?? (throw _missing(key, 'una data'));

  DateTime? optionalDate(String key) {
    final value = optionalText(key);
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw _wrong(key, 'una data');
    return parsed.toLocal();
  }

  List<int> integers(String key) => [
    for (final (index, value) in _list(key).indexed)
      if (value is num && value == value.roundToDouble())
        value.toInt()
      else
        throw _wrong('$key[$index]', 'un intero'),
  ];

  List<_Reader> objects(String key) => [
    for (final (index, value) in _list(key).indexed)
      if (value is Map<String, Object?>)
        _Reader(value, '$where, $key[$index]')
      else
        throw _wrong('$key[$index]', 'un oggetto'),
  ];

  List<Object?> _list(String key) =>
      _typed<List<Object?>>(key, 'un elenco') ?? const [];

  T? _typed<T extends Object>(String key, String expected) {
    final value = _json[key];
    if (value == null || value is T) return value as T?;
    throw _wrong(key, expected);
  }

  BackupFormatException _missing(String key, String expected) =>
      BackupFormatException(
        BackupProblem.damaged,
        '$where: manca "$key" ($expected).',
      );

  BackupFormatException _wrong(String key, String expected) =>
      BackupFormatException(
        BackupProblem.damaged,
        '$where: "$key" dovrebbe essere $expected.',
      );
}

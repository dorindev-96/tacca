import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'package:tacca/data/entities/log_entry.dart';
import 'package:tacca/data/entities/log_set.dart';
import 'package:tacca/data/entities/workout_day.dart';
import 'package:tacca/data/entities/workout_log.dart';
import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/data/repositories/plan_repository.dart';
import 'package:tacca/data/repositories/settings_repository.dart';
import 'package:tacca/data/repositories/workout_log_repository.dart';
import 'package:tacca/services/clipboard/clipboard_service.dart';
import 'package:tacca/services/feedback/session_feedback.dart';
import 'package:tacca/services/images/image_input.dart';
import 'package:tacca/services/images/ocr_service.dart';
import 'package:tacca/services/images/plan_image_store.dart';
import 'package:tacca/services/links/link_opener.dart';
import 'package:tacca/services/live_session/live_session_controller.dart';
import 'package:tacca/services/notifications/session_notifier.dart';
import 'package:tacca/services/share/image_share_service.dart';
import 'package:tacca/services/timer/timer_engine.dart';
import 'package:tacca/services/wakelock/screen_wake.dart';

/// Doppi di test condivisi: tengono i test lontani da ObjectBox e dai plugin
/// di piattaforma, che nei widget test non sono disponibili.

/// [PlanRepository] in memoria: le schede vengono servite così come sono
/// state registrate con [add].
class FakePlanRepository implements PlanRepository {
  final Map<int, WorkoutPlan> plans = {};

  void add(WorkoutPlan plan) => plans[plan.id] = plan;

  @override
  Stream<List<WorkoutPlan>> watchActive() =>
      Stream.value(plans.values.where((p) => !p.isArchived).toList());

  @override
  Stream<List<WorkoutPlan>> watchArchived() =>
      Stream.value(plans.values.where((p) => p.isArchived).toList());

  @override
  WorkoutPlan? getById(int id) => plans[id];

  @override
  WorkoutPlan? getActivePlan() {
    for (final plan in plans.values) {
      if (plan.isActive) return plan;
    }
    return null;
  }

  @override
  int savePlan(WorkoutPlan plan) {
    plans[plan.id] = plan;
    return plan.id;
  }

  @override
  void setActivePlan(int planId) => throw UnimplementedError();

  @override
  void clearActivePlan() => throw UnimplementedError();

  @override
  void setArchived(int planId, {required bool archived}) =>
      throw UnimplementedError();

  @override
  int duplicatePlan(int planId) => throw UnimplementedError();

  @override
  void deletePlan(int planId) => plans.remove(planId);
}

/// [WorkoutLogRepository] in memoria. Conserva i riferimenti agli stessi
/// oggetti passati dal Bloc: quello che conta nei test è **quante volte** e
/// **con quale contenuto** viene chiamato [saveLog] (autosave, RF-06).
class FakeWorkoutLogRepository implements WorkoutLogRepository {
  final Map<int, WorkoutLog> logs = {};
  final Map<String, LastPerformance> lastPerformances = {};

  /// Numero di autosave richiesti: un handler che muta e non salva si vede.
  int saveCount = 0;

  int _nextId = 1;
  final _controller = StreamController<List<WorkoutLog>>.broadcast();
  final _inProgressController = StreamController<WorkoutLog?>.broadcast();

  @override
  WorkoutLog startSession({
    required WorkoutPlan plan,
    required WorkoutDay day,
    DateTime? startedAt,
  }) {
    final start = startedAt ?? DateTime(2026, 8, 15, 18);
    // Come in produzione: una sessione per volta, quella aperta si chiude.
    for (final open in logs.values) {
      if (open.status == WorkoutStatus.inProgress) {
        open
          ..status = WorkoutStatus.aborted
          ..finishedAt = start;
      }
    }

    final log = WorkoutLog.start(
      startedAt: start,
      planNameSnapshot: plan.name,
      dayLabelSnapshot: day.label,
    );
    log.plan.target = plan;
    log.day.target = day;
    final exercises = flattenExercises(day);
    for (var i = 0; i < exercises.length; i++) {
      log.entries.add(
        LogEntry(exerciseNameSnapshot: exercises[i].name, sortOrder: i),
      );
    }
    saveLog(log);
    return log;
  }

  @override
  WorkoutLog? findInProgress() {
    for (final log in logs.values) {
      if (log.status == WorkoutStatus.inProgress) return log;
    }
    return null;
  }

  @override
  Stream<WorkoutLog?> watchInProgress() async* {
    yield findInProgress();
    yield* _inProgressController.stream;
  }

  @override
  WorkoutLog? getById(int id) => logs[id];

  @override
  Stream<List<WorkoutLog>> watchFinished() async* {
    yield _finished();
    yield* _controller.stream;
  }

  List<WorkoutLog> _finished() =>
      logs.values
          .where((log) => log.status != WorkoutStatus.inProgress)
          .toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  @override
  int saveLog(WorkoutLog log) {
    if (log.id == 0) log.id = _nextId++;
    logs[log.id] = log;
    saveCount++;
    _notify();
    return log.id;
  }

  @override
  void deleteLog(int logId) {
    logs.remove(logId);
    _notify();
  }

  /// Come i watcher di ObjectBox: ogni scrittura ripropaga entrambi gli
  /// elenchi osservati.
  void _notify() {
    if (!_controller.isClosed) _controller.add(_finished());
    if (!_inProgressController.isClosed) {
      _inProgressController.add(findInProgress());
    }
  }

  @override
  LastPerformance? lastPerformance(String exerciseName, {int? excludeLogId}) =>
      lastPerformances[exerciseName];

  Future<void> dispose() async {
    await _controller.close();
    await _inProgressController.close();
  }
}

/// Registra i segnali resi percepibili, senza toccare audio o vibrazione.
class RecordingSessionFeedback implements SessionFeedback {
  final List<TimerSignal> signals = [];
  int prepareCount = 0;

  @override
  Future<void> prepare() async => prepareCount++;

  @override
  Future<void> emit(TimerSignal signal) async => signals.add(signal);

  @override
  Future<void> dispose() async {}
}

/// Registra le notifiche programmate invece di parlare con il sistema.
class RecordingSessionNotifier implements SessionNotifier {
  final List<List<DateTime>> scheduled = [];
  final List<({String title, String body})> scheduledText = [];
  int cancelCount = 0;

  @override
  Future<void> prepare() async {}

  @override
  Future<void> scheduleSignals(
    List<DateTime> times, {
    required String title,
    required String body,
  }) async {
    scheduled.add(times);
    scheduledText.add((title: title, body: body));
  }

  @override
  Future<void> cancelPending() async => cancelCount++;
}

/// Etichette della schermata di blocco: in produzione arrivano dagli ARB
/// passando dal router, nei test bastano queste.
const kTestLiveLabels = LiveSessionLabels(
  title: 'Allenamento',
  setsLabel: 'Serie',
  completeAction: 'Serie fatta',
  restLabel: 'Recupero',
  restDoneLabel: 'Recupero finito',
);

/// Registra quello che finisce sulla schermata di blocco e permette di
/// simulare una conferma arrivata da lì, senza Live Activity né notifiche.
class RecordingLiveSession implements LiveSessionController {
  final List<LiveSessionSnapshot> started = [];
  final List<LiveSessionSnapshot> updated = [];
  int stopCount = 0;

  /// Azioni che il prossimo [drainPendingActions] restituirà: è la coda
  /// riempita dal nativo mentre l'app era ferma.
  List<LiveSessionAction> pending = [];

  final _controller = StreamController<LiveSessionAction>.broadcast();

  /// Ultimo stato pubblicato, da qualunque delle due strade.
  LiveSessionSnapshot? get last => updated.isNotEmpty
      ? updated.last
      : (started.isNotEmpty ? started.last : null);

  /// Conferma consegnata subito, con l'app ancora viva.
  void deliver(LiveSessionAction action) => _controller.add(action);

  @override
  Stream<LiveSessionAction> get actions => _controller.stream;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<void> start(LiveSessionSnapshot snapshot) async =>
      started.add(snapshot);

  @override
  Future<void> update(LiveSessionSnapshot snapshot) async =>
      updated.add(snapshot);

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<List<LiveSessionAction>> drainPendingActions() async {
    final queued = pending;
    pending = [];
    return queued;
  }

  @override
  Future<void> dispose() async => _controller.close();
}

/// Traccia le richieste di wake lock.
class RecordingScreenWake implements ScreenWake {
  bool enabled = false;

  @override
  Future<void> enable() async => enabled = true;

  @override
  Future<void> disable() async => enabled = false;
}

/// OCR pilotato: a ogni immagine il testo che deve riconoscere, e la
/// possibilità di farla fallire.
class FakeOcrService implements OcrService {
  final texts = <Uint8List, String>{};
  final failing = <Uint8List>{};
  final calls = <Uint8List>[];

  @override
  Future<String> recognizeText(Uint8List bytes) async {
    calls.add(bytes);
    if (failing.contains(bytes)) throw Exception('OCR fallito');
    return texts[bytes] ?? '';
  }
}

/// Fotocamera e galleria senza plugin: restituiscono ciò che il test ha
/// preparato.
class FakeImageInput implements ImageInput {
  Uint8List? cameraResult;
  List<Uint8List> galleryResult = const [];

  @override
  Future<Uint8List?> takePhoto() async => cameraResult;

  @override
  Future<List<Uint8List>> pickFromGallery() async => galleryResult;
}

/// Niente disco nei test: la "compressione" è un marker in coda ai byte e il
/// salvataggio registra i path senza scrivere niente.
class FakeImageStore extends PlanImageStore {
  final saved = <Uint8List>[];

  @override
  Future<Uint8List> compressForUpload(Uint8List bytes) async =>
      Uint8List.fromList([...bytes, 99]);

  @override
  Future<String> saveOriginal(Uint8List bytes) async {
    saved.add(bytes);
    return 'plan_images/img_${saved.length}.jpg';
  }
}

/// Appunti in memoria: registra tutto ciò che ci viene scritto, così i test
/// possono guardare *cosa* è stato copiato e non solo che si è copiato.
class RecordingClipboardService implements ClipboardService {
  final written = <String>[];
  String? content;

  String? get last => written.isEmpty ? null : written.last;

  @override
  Future<void> write(String text) async {
    written.add(text);
    content = text;
  }

  @override
  Future<String?> read() async => content;
}

/// Serie di comodo per costruire uno storico nei test.
LogSet buildLogSet(int number, {double? weightKg, String? reps}) => LogSet(
  setNumber: number,
  weightKg: weightKg,
  reps: reps,
  completedAt: DateTime(2026, 8, 1),
);

/// [SettingsRepository] in memoria: nessun secure storage nei test.
///
/// Key e modello sono per provider come in produzione; [apiKey] e [modelId]
/// restano scorciatoie per il provider di default dei test ([providerId]).
class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository({
    String? apiKey,
    String? modelId,
    this.providerId,
    this.acceptedLegalNoticeVersion,
    this.defaultProviderId = 'openrouter',
  }) {
    if (apiKey != null) apiKeys[defaultProviderId] = apiKey;
    if (modelId != null) modelIds[defaultProviderId] = modelId;
  }

  /// Versione dell'informativa legale già accettata; null = primo avvio.
  int? acceptedLegalNoticeVersion;

  /// Provider su cui puntano [apiKey] e [modelId].
  final String defaultProviderId;

  String? providerId;
  final Map<String, String> apiKeys = {};
  final Map<String, String> modelIds = {};

  String? get apiKey => apiKeys[defaultProviderId];

  set apiKey(String? value) => _put(apiKeys, defaultProviderId, value);

  String? get modelId => modelIds[defaultProviderId];

  set modelId(String? value) => _put(modelIds, defaultProviderId, value);

  @override
  Future<String?> getAiProviderId() async => providerId;

  @override
  Future<void> setAiProviderId(String? id) async => providerId = id;

  @override
  Future<String?> getApiKey(String providerId) async => apiKeys[providerId];

  @override
  Future<void> setApiKey(String providerId, String? key) async =>
      _put(apiKeys, providerId, key);

  @override
  Future<String?> getModelId(String providerId) async => modelIds[providerId];

  @override
  Future<void> setModelId(String providerId, String? modelId) async =>
      _put(modelIds, providerId, modelId);

  @override
  Future<int?> getAcceptedLegalNoticeVersion() async =>
      acceptedLegalNoticeVersion;

  @override
  Future<void> setAcceptedLegalNoticeVersion(int version) async =>
      acceptedLegalNoticeVersion = version;

  void _put(Map<String, String> into, String key, String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      into.remove(key);
    } else {
      into[key] = trimmed;
    }
  }
}

/// [LinkOpener] che non apre niente: registra gli indirizzi richiesti e
/// decide se l'apertura riesce, così si può provare anche il piano B (link
/// copiato negli appunti).
class FakeLinkOpener implements LinkOpener {
  FakeLinkOpener({this.succeeds = true});

  /// False = nessun browser disponibile.
  final bool succeeds;

  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return succeeds;
  }
}

/// Foglio di condivisione finto: registra *cosa* è stato condiviso senza
/// disegnare nessuna immagine.
///
/// Il rendering vero è caro (una scheda lunga è un'immagine da megapixel) e
/// non c'entra niente con la pagina che lo chiede: quello ha i suoi test in
/// `test/services/images/widget_image_renderer_test.dart`.
class RecordingImageShareService implements ImageShareService {
  RecordingImageShareService({this.fails = false});

  /// True = il disegno o la consegna non riescono, come quando il foglio di
  /// sistema non è disponibile.
  final bool fails;

  final List<SharedImage> shared = [];

  @override
  Future<void> shareWidgetAsImage({
    required Widget widget,
    required double width,
    required String fileName,
    String? text,
    Rect? originRect,
  }) async {
    if (fails) throw Exception('condivisione non riuscita');
    shared.add(
      SharedImage(
        widget: widget,
        width: width,
        fileName: fileName,
        text: text,
        originRect: originRect,
      ),
    );
  }
}

/// Una chiamata registrata da [RecordingImageShareService].
class SharedImage {
  const SharedImage({
    required this.widget,
    required this.width,
    required this.fileName,
    required this.text,
    required this.originRect,
  });

  final Widget widget;
  final double width;
  final String fileName;
  final String? text;
  final Rect? originRect;
}

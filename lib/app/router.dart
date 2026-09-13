import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/design/app_colors.dart';
import '../core/design/linear_icons.dart';
import '../core/widgets/app_scaffold.dart';
import '../core/widgets/confirm_dialog.dart';
import '../core/widgets/home_tab_bar.dart';
import '../data/repositories/plan_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/workout_log_repository.dart';
import '../features/ai_import/cubit/ai_import_cubit.dart';
import '../features/ai_import/cubit/ai_paste_import_cubit.dart';
import '../features/ai_import/pages/ai_import_page.dart';
import '../features/ai_import/pages/ai_import_review_args.dart';
import '../features/ai_import/pages/ai_paste_import_page.dart';
import '../features/history/cubit/history_detail_cubit.dart';
import '../features/history/pages/history_detail_page.dart';
import '../features/history/pages/history_page.dart';
import '../features/legal/pages/legal_notice_page.dart';
import '../features/plans/cubit/plan_editor_cubit.dart';
import '../features/plans/cubit/plan_editor_labels.dart';
import '../features/plans/pages/plan_detail_page.dart';
import '../features/plans/pages/plan_editor_page.dart';
import '../features/plans/pages/plan_images_page.dart';
import '../features/plans/pages/plans_page.dart';
import '../features/settings/cubit/settings_cubit.dart';
import '../features/settings/pages/ai_settings_page.dart';
import '../features/settings/pages/settings_page.dart';
import '../features/workout/bloc/workout_session_bloc.dart';
import '../features/workout/bloc/workout_session_event.dart';
import '../features/workout/cubit/active_session_cubit.dart';
import '../features/workout/cubit/active_session_state.dart';
import '../features/workout/pages/workout_session_page.dart';
import '../l10n/app_localizations.dart';
import '../services/ai/ai_provider.dart';
import '../services/ai/ai_selection.dart';
import '../services/clipboard/clipboard_service.dart';
import '../services/feedback/session_feedback.dart';
import '../services/images/image_input.dart';
import '../services/images/ocr_service.dart';
import '../services/images/plan_image_store.dart';
import '../services/live_session/live_session_controller.dart';
import '../services/notifications/session_notifier.dart';
import '../services/timer/timer_engine.dart';
import '../services/wakelock/screen_wake.dart';

/// Costruisce il router dell'app: una [StatefulShellRoute.indexedStack] con
/// tre rami (schede, storico, impostazioni) sotto una bottom navigation
/// condivisa. Ogni ramo mantiene il proprio stack di navigazione.
///
/// Dettaglio, editor, sessione e dettaglio sessione sono route di primo
/// livello (fuori dalla shell, come `/workout/:logId` in §8 dell'analisi
/// tecnica): sono pagine a schermo intero, la bottom nav non deve competere
/// con form, timer e tastiera.
GoRouter createRouter() {
  return GoRouter(
    initialLocation: '/plans',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/plans',
                builder: (context, state) => const PlansPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                builder: (context, state) => const HistoryPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
                routes: [
                  // La manleva accettata al primo avvio, rileggibile quando
                  // si vuole.
                  GoRoute(
                    path: 'legal',
                    builder: (context, state) => const LegalNoticePage(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      // Impostazioni AI (RF-08). Vive **fuori** dalla shell anche se il suo
      // posto nell'interfaccia è dentro Impostazioni: ci si arriva anche
      // dall'import senza key, cioè da una pagina che è già di primo
      // livello. Se fosse un ramo della shell, quella push ricostruirebbe la
      // shell come seconda pagina del navigator radice e il framework si
      // ferma su chiavi di pagina duplicate ('!keyReservation.contains(key)').
      GoRoute(
        path: '/settings/ai',
        builder: (context, state) => BlocProvider(
          create: (context) => SettingsCubit(
            settings: context.read<SettingsRepository>(),
            provider: context.read<AiProvider>(),
            selection: context.read<AiSelectionResolver>(),
          ),
          child: const AiSettingsPage(),
        ),
      ),
      GoRoute(
        path: '/plans/new',
        builder: (context, state) {
          // Le etichette si leggono qui e non dentro `create`: quel callback
          // non può dipendere da un InheritedWidget (e `Localizations` lo è).
          final labels = PlanEditorLabels.of(AppLocalizations.of(context));
          return BlocProvider(
            create: (context) => PlanEditorCubit.create(
              repository: context.read<PlanRepository>(),
              labels: labels,
            ),
            child: const PlanEditorPage(),
          );
        },
      ),
      // Import AI da foto/galleria/testo (RF-03). Fuori dalla shell come le
      // altre pagine di lavoro a schermo intero.
      GoRoute(
        path: '/plans/new/import',
        builder: (context, state) => BlocProvider(
          create: (context) => AiImportCubit(
            provider: context.read<AiProvider>(),
            imageInput: context.read<ImageInput>(),
            imageStore: context.read<PlanImageStore>(),
            selection: context.read<AiSelectionResolver>(),
            ocr: context.read<OcrService>(),
          ),
          child: const AiImportPage(),
        ),
      ),
      // Lo stesso import, ma con l'AI fuori dall'app: l'utente porta il
      // prompt nella chat che preferisce e riporta indietro la risposta
      // (RF-03). Nessuna key, nessuna rete: qui non c'è AiProvider.
      GoRoute(
        path: '/plans/new/import/paste',
        builder: (context, state) => BlocProvider(
          create: (context) => AiPasteImportCubit(
            imageInput: context.read<ImageInput>(),
            imageStore: context.read<PlanImageStore>(),
            ocr: context.read<OcrService>(),
            clipboard: context.read<ClipboardService>(),
          ),
          child: const AiPasteImportPage(),
        ),
      ),
      // Revisione della proposta AI: l'editor manuale (RF-02) su una bozza
      // non ancora persistita. Il salvataggio è sempre esplicito (RF-03).
      GoRoute(
        path: '/plans/new/review',
        builder: (context, state) {
          final args = state.extra! as AiImportReviewArgs;
          final labels = PlanEditorLabels.of(AppLocalizations.of(context));
          return BlocProvider(
            create: (context) => PlanEditorCubit.draft(
              repository: context.read<PlanRepository>(),
              labels: labels,
              draft: args.draft,
            ),
            child: const PlanEditorPage(),
          );
        },
      ),
      // Immagini originali allegate a una scheda (RF-03).
      GoRoute(
        path: '/plan-images',
        builder: (context, state) =>
            PlanImagesPage(imagePaths: state.extra! as List<String>),
      ),
      GoRoute(
        path: '/plans/:id',
        builder: (context, state) =>
            PlanDetailPage(planId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/plans/:id/edit',
        builder: (context, state) {
          final labels = PlanEditorLabels.of(AppLocalizations.of(context));
          return BlocProvider(
            create: (context) => PlanEditorCubit.edit(
              repository: context.read<PlanRepository>(),
              labels: labels,
              planId: int.parse(state.pathParameters['id']!),
            ),
            child: const PlanEditorPage(),
          );
        },
      ),
      // Nuova sessione: il log non esiste ancora, lo crea il Bloc a partire
      // da scheda e giorno scelti (§5.1, evento SessionStarted).
      GoRoute(
        path: '/workout/new',
        builder: (context, state) {
          final planId = int.parse(state.uri.queryParameters['planId']!);
          final dayId = int.parse(state.uri.queryParameters['dayId']!);
          final liveLabels = _liveSessionLabels(context);
          return BlocProvider(
            create: (context) =>
                _createSessionBloc(context, liveLabels)
                  ..add(SessionStarted(planId: planId, dayId: dayId)),
            child: const WorkoutSessionPage(),
          );
        },
      ),
      GoRoute(
        path: '/workout/:logId',
        builder: (context, state) {
          final logId = int.parse(state.pathParameters['logId']!);
          final liveLabels = _liveSessionLabels(context);
          return BlocProvider(
            create: (context) =>
                _createSessionBloc(context, liveLabels)
                  ..add(SessionResumed(logId)),
            child: const WorkoutSessionPage(),
          );
        },
      ),
      GoRoute(
        path: '/history/:logId',
        builder: (context, state) => BlocProvider(
          create: (context) => HistoryDetailCubit(
            repository: context.read<WorkoutLogRepository>(),
            logId: int.parse(state.pathParameters['logId']!),
          ),
          child: const HistoryDetailPage(),
        ),
      ),
    ],
  );
}

// Le etichette della schermata di blocco le disegna il sistema operativo, che
// gli ARB non può leggerli: si risolvono qui, in fase di build del route (dove
// dipendere da `Localizations` è lecito), e viaggiano nel payload verso il
// nativo. Risolverle invece dentro il `create:` del `BlocProvider` registra una
// dipendenza da un InheritedWidget in un lifecycle che non verrà più richiamato.
LiveSessionLabels _liveSessionLabels(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return LiveSessionLabels(
    title: l10n.workoutLiveTitle,
    setsLabel: l10n.workoutLiveSets,
    completeAction: l10n.workoutLiveCompleteSet,
    restLabel: l10n.workoutTimerRest,
    restDoneLabel: l10n.workoutLiveRestDone,
  );
}

WorkoutSessionBloc _createSessionBloc(
  BuildContext context,
  LiveSessionLabels liveLabels,
) {
  return WorkoutSessionBloc(
    planRepository: context.read<PlanRepository>(),
    logRepository: context.read<WorkoutLogRepository>(),
    timerEngine: context.read<TimerEngine>(),
    feedback: context.read<SessionFeedback>(),
    notifier: context.read<SessionNotifier>(),
    screenWake: context.read<ScreenWake>(),
    liveSession: context.read<LiveSessionController>(),
    liveLabels: liveLabels,
  );
}

/// Radice delle tre schermate della shell: il corpo è lo `IndexedStack` dei
/// rami e sopra ci galleggia la tab bar del restyling (toccare una
/// destinazione cambia ramo, ri-tap = pop allo stack root).
///
/// È anche il punto in cui si propone di riprendere la sessione trovata
/// aperta all'avvio (§8). Solo *quella*: la sessione aperta durante l'uso
/// dell'app si ritrova dalla card in cima all'archivio, senza che un dialog
/// la rincorra ogni volta che si torna indietro.
class _HomeShell extends StatefulWidget {
  const _HomeShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  @override
  void initState() {
    super.initState();
    // La proposta può essere già pronta quando la shell viene montata: il
    // gate legale sta sopra al router e le schermate nascono solo dopo
    // l'accettazione, cioè molto dopo la prima lettura del database. Si
    // guarda quindi lo stato appena montati, oltre ad ascoltarne i cambi.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeProposeResume());
  }

  void _onDestinationSelected(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // La tab bar del restyling galleggia *sopra* il contenuto: sta nello
    // Stack della shell, non in `bottomNavigationBar`, e le pagine le
    // lasciano spazio in fondo alle liste (AppSpacing.tabBarClearance).
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          BlocListener<ActiveSessionCubit, ActiveSessionState>(
            listenWhen: (previous, current) =>
                !previous.promptPending && current.promptPending,
            listener: (context, state) => _maybeProposeResume(),
            child: widget.navigationShell,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AppDock(
              child: HomeTabBar(
                currentIndex: widget.navigationShell.currentIndex,
                onSelected: _onDestinationSelected,
                tabs: [
                  HomeTab(icon: AppIcons.noteAdd, label: l10n.navPlans),
                  HomeTab(icon: AppIcons.calendar, label: l10n.navHistory),
                  HomeTab(icon: AppIcons.settings, label: l10n.navSettings),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Propone di riprendere la sessione trovata aperta all'avvio, se c'è e se
  /// non è già stata proposta.
  Future<void> _maybeProposeResume() async {
    if (!mounted) return;
    final cubit = context.read<ActiveSessionCubit>();
    final log = cubit.state.log;
    if (!cubit.state.promptPending || log == null) return;

    // Si spegne *prima* di aprire il dialog: la proposta è una sola, e le due
    // strade che arrivano qui (montaggio e cambio di stato) non devono
    // sovrapporsi.
    cubit.dismissPrompt();

    final l10n = AppLocalizations.of(context);
    final resume = await showConfirmDialog(
      context,
      title: l10n.workoutResumeTitle,
      message: l10n.workoutResumeBody(
        log.planNameSnapshot,
        log.dayLabelSnapshot,
        log.startedAt,
      ),
      confirmLabel: l10n.workoutResumeConfirm,
      cancelLabel: l10n.workoutResumeDismiss,
    );

    // "Più tardi" non chiude niente: la sessione resta aperta e resta a
    // portata di mano nella card in cima all'archivio.
    if (resume && mounted) {
      context.push('/workout/${log.id}');
    }
  }
}

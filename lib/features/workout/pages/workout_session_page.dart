import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart' hide Block;

import '../../../core/block_type_labels.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/widgets/app_menu.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/meta_chip.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/square_icon_button.dart';
import '../../../data/entities/block.dart';
import '../../../data/entities/workout_log.dart';
import '../../../l10n/app_localizations.dart';
import '../bloc/block_timer_spec.dart';
import '../bloc/session_item.dart';
import '../bloc/workout_session_bloc.dart';
import '../bloc/workout_session_event.dart';
import '../bloc/workout_session_state.dart';
import '../widgets/session_exercise_card.dart';
import '../widgets/session_summary_sheet.dart';
import '../widgets/set_log_sheet.dart';
import '../widgets/timer_bar.dart';

/// Modalità allenamento (RF-06): la schermata che si usa in palestra.
///
/// Osserva il lifecycle dell'app per delegare al Bloc la programmazione delle
/// notifiche quando si va in background e la riconciliazione al rientro (§7).
class WorkoutSessionPage extends StatefulWidget {
  const WorkoutSessionPage({super.key});

  @override
  State<WorkoutSessionPage> createState() => _WorkoutSessionPageState();
}

class _WorkoutSessionPageState extends State<WorkoutSessionPage>
    with WidgetsBindingObserver {
  // `didChangeAppLifecycleState` può scattare mentre l'elemento è già
  // disattivato (uscita dalla sessione + passaggio in background nello stesso
  // frame): lì un lookup che *ascolta* un InheritedWidget — come
  // `AppLocalizations.of` — lancia. Le stringhe si catturano quando il context
  // è ancora valido e si riusano nel callback di lifecycle.
  late AppLocalizations _l10n;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _l10n = AppLocalizations.of(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    // `inactive` **non** è background (spike S-01): iOS lo manda anche quando
    // l'app resta in primo piano e visibile — centro di controllo, centro
    // notifiche, banner di chiamata, selettore delle app, richiesta Face ID.
    // Lì il motore continua a battere e il beep lo suona l'app: programmare
    // anche le notifiche vorrebbe dire sentire il segnale due volte, perché
    // `kTimerSignalDetails` le fa presentare pure in primo piano.
    // Il passaggio vero è `resumed → inactive → hidden → paused`: si
    // programma da `hidden`, il primo istante in cui l'app non si vede più e
    // c'è ancora tempo prima che iOS sospenda il processo.
    final toBackground = switch (state) {
      AppLifecycleState.resumed => false,
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached => true,
      // Né andata né ritorno: non c'è niente da programmare e niente da
      // annullare, e il rientro vero lo annuncia `resumed` subito dopo.
      AppLifecycleState.inactive => null,
    };
    if (toBackground == null) return;

    context.read<WorkoutSessionBloc>().add(
      AppLifecycleChanged(
        toBackground: toBackground,
        notificationTitle: _l10n.workoutNotificationTitle,
        notificationBody: _l10n.workoutNotificationBody,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return BlocConsumer<WorkoutSessionBloc, WorkoutSessionState>(
      listenWhen: (previous, current) =>
          previous.errorMessage != current.errorMessage ||
          previous.pendingTimerRequest != current.pendingTimerRequest ||
          previous.status != current.status,
      listener: (context, state) {
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          context.read<WorkoutSessionBloc>().add(const SessionErrorDismissed());
        }
        if (state.pendingTimerRequest != null) {
          _confirmTimerReplacement(context, l10n);
        }
        if (state.status == WorkoutSessionStatus.finished) {
          final logId = state.log?.id;
          if (logId != null) {
            context.pushReplacement('/history/$logId');
          } else {
            context.pop();
          }
        }
      },
      builder: (context, state) {
        switch (state.status) {
          case WorkoutSessionStatus.loading:
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          case WorkoutSessionStatus.notFound:
            return AppScaffold(
              leading: const AppBackButton(),
              body: EmptyState(
                icon: AppIcons.search,
                message: l10n.workoutSessionNotFound,
              ),
            );
          case WorkoutSessionStatus.finished:
          case WorkoutSessionStatus.ready:
            return _SessionScaffold(state: state);
        }
      },
    );
  }

  Future<void> _confirmTimerReplacement(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final bloc = context.read<WorkoutSessionBloc>();
    final spec = bloc.state.pendingTimerRequest;
    if (spec == null) return;

    final replace = await showConfirmDialog(
      context,
      title: l10n.workoutReplaceTimerTitle,
      message: l10n.workoutReplaceTimerBody,
      confirmLabel: l10n.workoutReplaceTimerConfirm,
    );

    if (replace) {
      bloc.add(TimerRequested(spec, force: true));
    } else {
      bloc.add(const TimerRequestDismissed());
    }
  }
}

class _SessionScaffold extends StatelessWidget {
  const _SessionScaffold({required this.state});

  final WorkoutSessionState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bloc = context.read<WorkoutSessionBloc>();
    final items = state.items;
    final log = state.log;

    return PopScope(
      canPop: state.status != WorkoutSessionStatus.ready,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await _confirmExit(context, l10n);
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: AppScaffold(
        topSpacing: AppSpacing.md,
        leading: const AppBackButton(),
        actions: [
          PillButton.compact(
            label: l10n.workoutFinishAction,
            tone: PillTone.surface,
            onPressed: () => _finish(context, bloc, l10n),
          ),
          const SizedBox(width: AppSpacing.xs),
          AppMenuButton<_SessionMenuAction>(
            onSelected: (action) => _handleMenu(context, bloc, l10n, action),
            itemBuilder: (context) => [
              appMenuCheckItem(
                value: _SessionMenuAction.toggleAutoRest,
                label: l10n.workoutAutoRestLabel,
                checked: state.autoStartRest,
              ),
              appMenuItem(
                value: _SessionMenuAction.abort,
                label: l10n.workoutAbortAction,
                destructive: true,
              ),
            ],
          ),
        ],
        // Giorno, avanzamento e barra restano fermi in cima: durante
        // l'allenamento sono i tre dati che si guardano di continuo.
        header: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                log?.dayLabelSnapshot ?? '',
                style: context.type.screenTitle,
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.workoutProgress(state.completedExercises, items.length),
                  style: context.type.sectionLabel.copyWith(fontSize: 14),
                ),
                const SizedBox(height: AppSpacing.md),
                ProgressLine(value: state.completedExercises / items.length),
              ],
              if (state.timer case final timer?) ...[
                const SizedBox(height: AppSpacing.lg),
                TimerBar(
                  timer: timer,
                  onStop: () => bloc.add(const TimerStopped()),
                ),
              ],
            ],
          ),
        ),
        body: items.isEmpty
            ? EmptyState(
                icon: AppIcons.noteAdd,
                message: l10n.workoutNoExercises,
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.xxl,
                ),
                children: _buildBody(context, bloc, l10n, items),
              ),
      ),
    );
  }

  List<Widget> _buildBody(
    BuildContext context,
    WorkoutSessionBloc bloc,
    AppLocalizations l10n,
    List<SessionItem> items,
  ) {
    final widgets = <Widget>[];

    if (state.day == null) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          child: InfoBanner(message: l10n.workoutPlanRemoved),
        ),
      );
    }

    for (final block in state.blocks) {
      if (block.type == BlockType.freeText) {
        widgets
          ..add(_BlockHeader(block: block, state: state))
          ..add(
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              child: Text(
                block.freeTextContent ?? '',
                style: context.type.paragraph,
              ),
            ),
          );
        continue;
      }

      final blockItems = items
          .where((item) => item.block?.id == block.id)
          .toList();
      // Superset e circuiti si eseguono insieme: la lettera A/B sulla card e
      // la nota sotto l'intestazione dicono che vanno alternati — nel design
      // non c'è alcun riquadro attorno al gruppo.
      final grouped =
          (block.type == BlockType.superset ||
              block.type == BlockType.circuit) &&
          blockItems.length > 1;

      widgets.add(_BlockHeader(block: block, state: state, inGroup: grouped));
      for (var i = 0; i < blockItems.length; i++) {
        widgets.add(
          Padding(
            padding: EdgeInsets.only(
              bottom: i == blockItems.length - 1
                  ? AppSpacing.xl
                  : AppSpacing.sm,
            ),
            child: _card(
              context,
              bloc,
              blockItems[i],
              groupMarker: grouped ? String.fromCharCode(0x41 + i) : null,
            ),
          ),
        );
      }
    }

    // Esercizi registrati che non esistono più in scheda: restano in fondo,
    // non vengono mai nascosti (analisi funzionale §9).
    for (final item in items.where((item) => item.block == null)) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _card(context, bloc, item),
        ),
      );
    }

    return widgets;
  }

  Widget _card(
    BuildContext context,
    WorkoutSessionBloc bloc,
    SessionItem item, {
    String? groupMarker,
  }) {
    final rest = restTimerSpec(item, label: item.name);
    return SessionExerciseCard(
      key: ValueKey('session-item-${item.index}'),
      item: item,
      isCurrent: item.index == state.currentIndex,
      lastPerformance: state.lastPerformances[item.name],
      groupMarker: groupMarker,
      onFocus: () => bloc.add(ExerciseFocused(item.index)),
      onToggleSet: (setNumber) {
        if (item.isSetDone(setNumber)) {
          bloc.add(SetUnchecked(entryIndex: item.index, setNumber: setNumber));
        } else {
          bloc.add(SetCompleted(entryIndex: item.index, setNumber: setNumber));
        }
      },
      onEditSet: (setNumber) => _editSet(context, bloc, item, setNumber),
      onStartRest: rest == null ? null : () => bloc.add(TimerRequested(rest)),
    );
  }

  Future<void> _editSet(
    BuildContext context,
    WorkoutSessionBloc bloc,
    SessionItem item,
    int setNumber,
  ) async {
    final suggestion = state.lastPerformances[item.name];
    final reference = suggestion == null || suggestion.sets.isEmpty
        ? null
        : suggestion.sets.last;

    final outcome = await showSetLogSheet(
      context,
      exerciseName: item.name,
      setNumber: setNumber,
      current: item.setNumbered(setNumber),
      suggestedWeightKg: reference?.weightKg,
      suggestedReps: reference?.reps ?? item.exercise?.reps,
    );

    switch (outcome) {
      case null:
        return;
      case SetLogRemoved():
        bloc.add(SetUnchecked(entryIndex: item.index, setNumber: setNumber));
      case SetLogSaved(:final weightKg, :final reps, :final notes):
        bloc.add(
          SetLogged(
            entryIndex: item.index,
            setNumber: setNumber,
            weightKg: weightKg,
            reps: reps,
            notes: notes,
          ),
        );
    }
  }

  Future<void> _finish(
    BuildContext context,
    WorkoutSessionBloc bloc,
    AppLocalizations l10n,
  ) async {
    final log = state.log;
    if (log == null) return;

    final result = await showSessionSummarySheet(
      context,
      elapsed: log.duration(),
      completedExercises: state.completedExercises,
      totalExercises: state.items.length,
      loggedSets: state.loggedSets,
      items: state.items,
      initialNotes: log.notes,
    );
    if (result == null) return;

    bloc.add(
      SessionFinished(status: WorkoutStatus.completed, notes: result.notes),
    );
  }

  Future<void> _handleMenu(
    BuildContext context,
    WorkoutSessionBloc bloc,
    AppLocalizations l10n,
    _SessionMenuAction action,
  ) async {
    switch (action) {
      case _SessionMenuAction.toggleAutoRest:
        bloc.add(AutoStartRestToggled(!state.autoStartRest));
      case _SessionMenuAction.abort:
        final confirmed = await showConfirmDialog(
          context,
          title: l10n.workoutAbortConfirmTitle,
          message: l10n.workoutAbortConfirmBody,
          confirmLabel: l10n.workoutAbortAction,
          destructive: true,
        );
        if (confirmed) {
          bloc.add(const SessionFinished(status: WorkoutStatus.aborted));
        }
    }
  }

  Future<bool> _confirmExit(BuildContext context, AppLocalizations l10n) {
    return showConfirmDialog(
      context,
      title: l10n.workoutExitTitle,
      message: l10n.workoutExitBody,
      confirmLabel: l10n.workoutExitConfirm,
      cancelLabel: l10n.commonContinue,
    );
  }
}

enum _SessionMenuAction { toggleAutoRest, abort }

/// Intestazione di un blocco: tipo, parametri e, dove esiste, il timer che
/// guida l'esecuzione dell'intero blocco.
class _BlockHeader extends StatelessWidget {
  const _BlockHeader({
    required this.block,
    required this.state,
    this.inGroup = false,
  });

  final Block block;
  final WorkoutSessionState state;

  /// Il blocco si esegue a giri: sotto l'intestazione compare la nota che
  /// spiega come alternare gli esercizi.
  final bool inGroup;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spec = blockTimerSpec(block, label: blockTypeLabel(l10n, block.type));
    final rounds = block.rounds;
    final roundRest = block.restBetweenRoundsSeconds;

    // Il "come si esegue" è la prima cosa da capire di un superset: giri e
    // recupero stanno accanto al nome del blocco, non sepolti negli esercizi.
    final params = <String>[
      if (block.type != BlockType.tabata && rounds != null && rounds > 0)
        l10n.workoutBlockRounds(rounds),
      if (roundRest != null && roundRest > 0)
        l10n.workoutBlockRestBetweenRounds(roundRest),
    ];

    final hint = switch (block.type) {
      BlockType.superset when inGroup => l10n.workoutSupersetHint,
      BlockType.circuit when inGroup => l10n.workoutCircuitHint,
      _ => null,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                blockTypeLabel(l10n, block.type),
                style: context.type.blockType,
              ),
              for (final param in params)
                MetaChip(label: param, tone: ChipTone.onBackground),
            ],
          ),
          if (spec != null) ...[
            const SizedBox(height: AppSpacing.md),
            PillButton.compact(
              label: l10n.workoutStartBlockTimer,
              icon: AppIcons.play,
              tone: PillTone.outline,
              onPressed: () =>
                  context.read<WorkoutSessionBloc>().add(TimerRequested(spec)),
            ),
          ],
          if (hint != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(hint, style: context.type.paragraphSmall),
          ],
          if ((block.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(block.notes!, style: context.type.paragraphSmall),
          ],
        ],
      ),
    );
  }
}

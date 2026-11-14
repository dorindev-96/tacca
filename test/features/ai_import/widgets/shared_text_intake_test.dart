import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tacca/features/ai_import/cubit/shared_text_cubit.dart';
import 'package:tacca/features/ai_import/pages/ai_paste_import_page.dart';
import 'package:tacca/features/ai_import/widgets/shared_text_intake.dart';

import '../../../support/fakes.dart';

void main() {
  late FakeSharedTextReceiver receiver;
  late SharedTextCubit sharedText;
  late GoRouter router;

  setUp(() {
    receiver = FakeSharedTextReceiver();
    sharedText = SharedTextCubit(receiver: receiver);
    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: AiPasteImportPage.routePath,
          builder: (context, state) => const Scaffold(body: Text('IMPORT')),
        ),
      ],
    );
  });

  tearDown(() {
    sharedText.close();
    router.dispose();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      BlocProvider<SharedTextCubit>.value(
        value: sharedText,
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) =>
              SharedTextIntake(router: router, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  testWidgets('senza niente in attesa non apre niente', (tester) async {
    await pumpApp(tester);

    expect(receiver.takeCalls, 1);
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('IMPORT'), findsNothing);
  });

  testWidgets('un testo in attesa all\'avvio apre l\'import senza key e lo '
      'lascia alla pagina', (tester) async {
    receiver.pending.add('risposta');

    await pumpApp(tester);

    expect(find.text('IMPORT'), findsOneWidget);
    // A prenderlo è la pagina, non chi la apre.
    expect(sharedText.state, 'risposta');
  });

  testWidgets('al rientro in primo piano svuota la coda nativa', (
    tester,
  ) async {
    await pumpApp(tester);
    receiver.pending.add('risposta');

    await resume(tester);

    expect(receiver.takeCalls, 2);
    expect(find.text('IMPORT'), findsOneWidget);
  });

  testWidgets('se l\'import è già in cima non ne apre un secondo sopra', (
    tester,
  ) async {
    receiver.pending.add('prima');
    await pumpApp(tester);
    sharedText.consume();
    receiver.pending.add('seconda');

    await resume(tester);

    expect(sharedText.state, 'seconda');
    expect(router.routerDelegate.currentConfiguration.matches, hasLength(2));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/features/ai_import/cubit/shared_text_cubit.dart';

import '../../../support/fakes.dart';

void main() {
  late FakeSharedTextReceiver receiver;

  setUp(() => receiver = FakeSharedTextReceiver());

  test('senza niente in attesa lo stato resta vuoto', () async {
    final cubit = SharedTextCubit(receiver: receiver);

    await cubit.drain();

    expect(cubit.state, isNull);
    expect(receiver.takeCalls, 1);
  });

  test(
    'un testo in attesa diventa lo stato finché qualcuno non lo prende',
    () async {
      receiver.pending.add('risposta della chat');
      final cubit = SharedTextCubit(receiver: receiver);

      await cubit.drain();
      expect(cubit.state, 'risposta della chat');

      // Svuotare di nuovo non lo perde: il nativo l'ha già consegnato e qui
      // resta finché la pagina non lo consuma.
      await cubit.drain();
      expect(cubit.state, 'risposta della chat');

      cubit.consume();
      expect(cubit.state, isNull);
    },
  );
}

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/share/shared_text_receiver.dart';

/// Il testo che un'altra app ha appena condiviso con Tacca, finché qualcuno
/// non se lo prende.
///
/// Lo stato è il testo in attesa, `null` quando non c'è niente. Vive nella
/// composition root perché ha due lettori che non si vedono fra loro:
/// `SharedTextIntake`, sopra al router, che lo svuota dal nativo e apre
/// l'import senza key se non è già aperto, e la pagina di quell'import, che
/// lo prende ([consume]) e lo mette dove va. Un testo resta qui finché la
/// pagina non lo ha letto: se è arrivato ad app chiusa, la pagina che lo
/// aspetta non esiste ancora quando lo si svuota dal nativo.
class SharedTextCubit extends Cubit<String?> {
  SharedTextCubit({required SharedTextReceiver receiver})
    : _receiver = receiver,
      super(null);

  final SharedTextReceiver _receiver;

  /// Chiede al nativo se c'è un testo in attesa. Va chiamato all'avvio e a
  /// ogni rientro in primo piano: su entrambe le piattaforme la condivisione
  /// porta l'app davanti, e il nativo non spinge niente da sé.
  Future<void> drain() async {
    final text = await _receiver.takePending();
    if (text == null || isClosed) return;
    emit(text);
  }

  /// La pagina ha preso il testo: non è più in attesa.
  void consume() => emit(null);
}

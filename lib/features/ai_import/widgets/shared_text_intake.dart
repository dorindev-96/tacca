import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubit/shared_text_cubit.dart';
import '../pages/ai_paste_import_page.dart';

/// Raccoglie il testo che un'altra app ha condiviso con Tacca e lo porta
/// all'import senza key (RF-03).
///
/// Sta nel `builder` di `MaterialApp.router`, **dentro** il cancello legale e
/// attorno al router: così esiste solo quando le schermate esistono (un
/// testo arrivato prima dell'accettazione aspetta nel nativo) e tiene in
/// mano il [router] per aprire la pagina giusta. Svuota la coda nativa
/// quando compare e a ogni rientro in primo piano — l'arrivo di un testo
/// porta l'app davanti su entrambe le piattaforme — e poi fa una cosa sola:
/// se l'import non è già la pagina in cima lo apre. A prendersi il testo è
/// sempre la pagina, che sa in quale passo si trova; qui non si decide
/// niente sul contenuto.
class SharedTextIntake extends StatefulWidget {
  const SharedTextIntake({
    required this.router,
    required this.child,
    super.key,
  });

  final GoRouter router;
  final Widget child;

  @override
  State<SharedTextIntake> createState() => _SharedTextIntakeState();
}

class _SharedTextIntakeState extends State<SharedTextIntake> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _drain);
    // Dopo il primo frame, non in `initState`: il router sotto deve essere
    // montato perché una `push` abbia un posto in cui finire.
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _drain() {
    if (!mounted) return;
    context.read<SharedTextCubit>().drain();
  }

  /// La pagina in cima, `push` comprese: `currentConfiguration.uri` no, quello
  /// ignora le route aperte in modo imperativo, e questa lo è sempre.
  bool get _onPastePage {
    final matches = widget.router.routerDelegate.currentConfiguration;
    return matches.isNotEmpty &&
        matches.last.matchedLocation == AiPasteImportPage.routePath;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SharedTextCubit, String?>(
      listenWhen: (previous, current) => current != null,
      listener: (context, text) {
        // Se l'import è già aperto è lui ad ascoltare: aprirne un secondo
        // sopra butterebbe via foto e testo del primo passo.
        if (_onPastePage) return;
        widget.router.push(AiPasteImportPage.routePath);
      },
      child: widget.child,
    );
  }
}

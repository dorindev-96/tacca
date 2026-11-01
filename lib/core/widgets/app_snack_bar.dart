import 'package:flutter/material.dart';

/// L'unico modo in cui l'app dà un avviso passeggero.
extension AppSnackBar on ScaffoldMessengerState {
  /// Mostra [message] **al posto** di quello eventualmente a schermo: due
  /// avvisi in fila non devono aspettare l'uno la fine dell'altro, conta
  /// l'ultimo.
  void showMessage(String message) {
    this
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

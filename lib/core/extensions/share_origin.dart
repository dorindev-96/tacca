import 'package:flutter/widgets.dart';

/// L'ancora del foglio di condivisione di sistema.
extension ShareOrigin on BuildContext {
  /// Il rettangolo di questo widget sullo schermo, o null se non è ancora
  /// stato disposto. Su iPad il foglio di condivisione è un popover, e senza
  /// un'ancora compare dove capita.
  Rect? get shareOrigin {
    final box = findRenderObject() as RenderBox?;
    return box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
  }
}

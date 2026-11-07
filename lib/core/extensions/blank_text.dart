/// Testo che conta come assente: `null`, vuoto o fatto solo di spazi.
///
/// È la domanda che si fa ogni volta che il testo arriva da fuori — una
/// risposta del modello, un campo lasciato con uno spazio dentro — e merita
/// una risposta sola.
extension BlankText on String? {
  bool get isBlank => this?.trim().isEmpty ?? true;

  /// Il testo senza gli spazi ai bordi, o `null` se non ne resta niente.
  String? get trimmedOrNull {
    final trimmed = this?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

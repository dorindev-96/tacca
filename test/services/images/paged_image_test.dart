import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/services/images/paged_image.dart';
import 'package:tacca/services/share/image_share_service.dart';

/// Dove va a capo un'immagine lunga: è aritmetica, quindi la si prova con
/// altezze inventate invece che con widget veri.
void main() {
  /// Pezzi alti 100 l'uno dentro una cornice alta 50, salvo quelli indicati.
  double Function(int, int) heights({Map<int, double> tall = const {}}) =>
      (start, end) {
        var height = 50.0;
        for (var i = start; i < end; i++) {
          height += tall[i] ?? 100;
        }
        return height;
      };

  test('senza pezzi c\'è comunque una pagina: la cornice da sola', () {
    expect(paginateRanges(count: 0, maxHeight: 400, heightOf: heights()), [
      (start: 0, end: 0),
    ]);
  });

  test('ciò che ci sta resta su una pagina sola', () {
    expect(paginateRanges(count: 3, maxHeight: 400, heightOf: heights()), [
      (start: 0, end: 3),
    ]);
  });

  test('ogni pagina prende tutti i pezzi che ci stanno, non uno di più', () {
    // 50 + 3×100 = 350 ci sta, 50 + 4×100 = 450 no.
    expect(paginateRanges(count: 7, maxHeight: 400, heightOf: heights()), [
      (start: 0, end: 3),
      (start: 3, end: 6),
      (start: 6, end: 7),
    ]);
  });

  test('un pezzo più alto di una pagina va da solo e non blocca niente', () {
    expect(
      paginateRanges(
        count: 4,
        maxHeight: 400,
        heightOf: heights(tall: {1: 1000}),
      ),
      [(start: 0, end: 1), (start: 1, end: 2), (start: 2, end: 4)],
    );
  });

  test('dove non si può andare a capo, la pagina si chiude prima', () {
    // La pagina starebbe piena a tre pezzi, ma il terzo non può aprirne
    // una nuova (è un'intestazione rimasta in fondo, o la metà di un blocco).
    expect(
      paginateRanges(
        count: 7,
        maxHeight: 400,
        heightOf: heights(),
        canBreakBefore: (index) => index != 3,
      ),
      [(start: 0, end: 2), (start: 2, end: 5), (start: 5, end: 7)],
    );
  });

  test('si torna indietro fino all\'ultimo punto buono', () {
    expect(
      paginateRanges(
        count: 7,
        maxHeight: 400,
        heightOf: heights(),
        canBreakBefore: (index) => index == 1 || index == 4,
      ),
      [(start: 0, end: 1), (start: 1, end: 4), (start: 4, end: 7)],
    );
  });

  test('se non c\'è nessun punto buono si va a capo comunque', () {
    // L'altezza è un limite, il bel taglio una preferenza.
    expect(
      paginateRanges(
        count: 7,
        maxHeight: 400,
        heightOf: heights(),
        canBreakBefore: (index) => false,
      ),
      [(start: 0, end: 3), (start: 3, end: 6), (start: 6, end: 7)],
    );
  });

  test('la fine della sequenza è sempre un buon punto per chiudere', () {
    expect(
      paginateRanges(
        count: 3,
        maxHeight: 400,
        heightOf: heights(),
        canBreakBefore: (index) => false,
      ),
      [(start: 0, end: 3)],
    );
  });

  test('un pezzo che non può aprire una pagina, seguito da uno enorme, non '
      'la lascia vuota', () {
    expect(
      paginateRanges(
        count: 2,
        maxHeight: 400,
        heightOf: heights(tall: {1: 1000}),
        canBreakBefore: (index) => index != 1,
      ),
      [(start: 0, end: 1), (start: 1, end: 2)],
    );
  });

  test('le pagine si trovano senza provare un pezzo alla volta, e senza '
      'misurare candidate lunghe mezza scheda', () {
    var measures = 0;
    var longest = 0;
    final pages = paginateRanges(
      count: 200,
      maxHeight: 1050,
      heightOf: (start, end) {
        measures++;
        if (end - start > longest) longest = end - start;
        return heights()(start, end);
      },
    );

    expect(pages, hasLength(20));
    // Un pezzo alla volta sarebbero più di duecento misure.
    expect(measures, lessThan(200));
    // Le pagine vere sono da dieci pezzi: nessuna candidata misurata è più
    // lunga del doppio.
    expect(longest, lessThanOrEqualTo(20));
  });

  group('i nomi dei file', () {
    test('una pagina sola non si numera', () {
      expect(pageFileNames('push-pull-legs', 1), ['push-pull-legs.png']);
    });

    test('più pagine si numerano nell\'ordine in cui si leggono', () {
      expect(pageFileNames('push-pull-legs', 3), [
        'push-pull-legs-1.png',
        'push-pull-legs-2.png',
        'push-pull-legs-3.png',
      ]);
    });
  });
}

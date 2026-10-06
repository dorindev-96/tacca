import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/constants.dart';
import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/widgets/linear_icon.dart';
import '../../../core/widgets/meta_chip.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../data/entities/workout_plan.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/images/paged_image.dart';
import '../../../services/images/widget_image_renderer.dart';
import 'plan_day_view.dart';

/// La scheda intera da mandare in chat, impaginata in **una o più immagini**.
///
/// Una scheda corta è un'immagine sola; una lunga si divide in pagine con le
/// proporzioni di uno schermo di telefono ([maxPageHeight]). Una striscia
/// unica alta dieci schermi verrebbe ridimensionata dalla chat sul lato lungo
/// e arriverebbe sgranata, qualunque fosse la sua definizione di partenza:
/// più pagine arrivano ciascuna come uno screenshot, leggibili. Ogni pagina è
/// firmata col nome dell'app e, se sono più d'una, numerata.
///
/// Dove andare a capo lo decide [paginate] **misurando le pagine vere**,
/// disegnate fuori schermo da `WidgetImageRenderer`: la scheda si divide in
/// pezzi indivisibili (una riga della descrizione, l'etichetta di un giorno,
/// un esercizio), e ogni pagina ne prende quanti ce ne stanno. Un blocco può
/// quindi spezzarsi fra due pagine; il pezzo che continua ne ripete
/// l'intestazione, come la pagina che riprende un giorno a metà ne ripete
/// l'etichetta.
///
/// Le pagine ([PlanSharePage]) si disegnano fuori dall'albero dell'app, a
/// larghezza fissa e altezza libera. Da qui le regole che le riguardano:
///
/// * si portano dietro il proprio contesto — [Directionality], [MediaQuery],
///   [Localizations] e [Theme] — perché sopra di loro non c'è nessun
///   `MaterialApp`. Il [MediaQuery] è volutamente quello di default: il
///   fattore di ingrandimento del testo del telefono di chi condivide non
///   deve sfondare un'impaginazione a larghezza fissa;
/// * niente `ListView` e niente `Expanded`: in altezza non c'è un viewport da
///   riempire, c'è una colonna che si misura da sé;
/// * niente lime. Nell'app l'accento dice "questo, adesso" (la scheda in uso,
///   l'esercizio corrente); dentro un'immagine spedita a qualcun altro non
///   direbbe niente, quindi le chip di stato ("In uso", "Archiviata") qui non
///   compaiono, e la firma è in inchiostro.
class PlanShareImage implements PagedImage {
  const PlanShareImage({
    required this.plan,
    required this.locale,
    required this.brightness,
  });

  final WorkoutPlan plan;

  /// La lingua con cui impaginare: fuori dall'albero dell'app non c'è nessuno
  /// da cui ereditarla, quindi la passa il chiamante
  /// (`Localizations.localeOf`).
  final Locale locale;

  /// Il tema con cui impaginare, per la stessa ragione della lingua: qui sopra
  /// non c'è nessun `MaterialApp` da cui ereditarlo.
  ///
  /// Il chiamante passa quello in cui l'utente sta guardando la scheda: si
  /// condivide ciò che si vede. Un'immagine sempre chiara sarebbe una
  /// sorpresa per chi ha l'app scura, e sempre scura per chi non ce l'ha.
  final Brightness brightness;

  /// Larghezza logica delle pagine. Vicina a quella di un telefono, così le
  /// righe vanno a capo dove l'utente le ha viste andare a capo nell'app; il
  /// numero di pixel veri lo decide il `pixelRatio` del rendering.
  static const double logicalWidth = 420;

  /// Altezza massima di una pagina: il doppio della larghezza, le
  /// proporzioni di uno screenshot.
  ///
  /// È la misura che regge il ridimensionamento delle chat: una pagina a
  /// densità 3 è 1260×2520 px, e WhatsApp in qualità standard (lato lungo
  /// ~1600 px) la riduce a circa 800×1600 — testo leggibile come in uno
  /// screenshot. La stessa scheda in una striscia sola alta 7000 px
  /// arriverebbe larga meno di 300.
  static const double maxPageHeight = logicalWidth * 2;

  @override
  double get pageWidth => logicalWidth;

  @override
  List<Widget> paginate(WidgetHeightMeasure measure) {
    final pieces = PlanSharePiece.sequenceOf(plan);

    final pages = paginateRanges(
      count: pieces.length,
      maxHeight: maxPageHeight,
      // Il numero totale di pagine qui non si sa ancora: ne basta uno
      // qualsiasi maggiore di uno, la riga della firma è alta uguale.
      heightOf: (start, end) => measure(
        _page(pieces, start, end, index: start == 0 ? 0 : 1, count: 2),
      ),
      canBreakBefore: (index) => _canBreakBefore(pieces, index),
    );

    return [
      for (var i = 0; i < pages.length; i++)
        _page(
          pieces,
          pages[i].start,
          pages[i].end,
          index: i,
          count: pages.length,
        ),
    ];
  }

  /// Se una pagina può cominciare dal pezzo [index].
  ///
  /// Non dopo l'etichetta di un giorno che ha dei blocchi: intesterebbe la
  /// pagina sbagliata (quella di un giorno vuoto invece sì, l'avviso "nessun
  /// blocco" ce l'ha già sotto). E dentro un blocco, o un testo, solo dove
  /// ne restano almeno due righe per parte: un esercizio da solo in cima a
  /// una pagina sembra un blocco a sé. Un blocco corto, come un superset, non
  /// si spezza affatto.
  bool _canBreakBefore(List<PlanSharePiece> pieces, int index) {
    final days = plan.days.toList();
    final previous = pieces[index - 1];
    if (previous is PlanShareDayLabel && days[previous.day].blocks.isNotEmpty) {
      return false;
    }

    final (position, length) = switch (pieces[index]) {
      PlanShareBlockRow(:final day, :final block, :final row) => (
        row,
        PlanBlockCard.rowCountOf(days[day].blocks.toList()[block]),
      ),
      PlanShareTextLine(:final text, :final line) => (
        line,
        text.linesOf(plan).length,
      ),
      PlanShareDayLabel() || PlanShareEmptyDay() => (0, 1),
    };
    return position == 0 ||
        (length > _shortGroup &&
            position >= _minRowsPerSide &&
            length - position >= _minRowsPerSide);
  }

  /// Fin qui un gruppo di righe (un blocco, un testo) non si spezza.
  static const int _shortGroup = 4;

  /// Le righe che un gruppo spezzato lascia almeno da ciascuna parte.
  static const int _minRowsPerSide = 2;

  PlanSharePage _page(
    List<PlanSharePiece> pieces,
    int start,
    int end, {
    required int index,
    required int count,
  }) => PlanSharePage(
    plan: plan,
    locale: locale,
    brightness: brightness,
    pieces: pieces.sublist(start, end),
    index: index,
    count: count,
  );
}

/// Un pezzo indivisibile della scheda, nell'ordine in cui si legge: è
/// l'unità con cui [PlanShareImage] riempie le pagine.
sealed class PlanSharePiece {
  const PlanSharePiece();

  /// La scheda smontata nei suoi pezzi, dall'alto in basso.
  ///
  /// Le righe dei testi lunghi (descrizione, note, testo libero) sono pezzi a
  /// sé: un testo che va a capo cento volte non deve trascinarsi dietro una
  /// pagina intera. Un esercizio invece è indivisibile, note comprese.
  static List<PlanSharePiece> sequenceOf(WorkoutPlan plan) {
    final days = plan.days.toList();
    final showDayLabels = days.length > 1;

    return [
      for (final kind in PlanShareText.values)
        for (var line = 0; line < kind.linesOf(plan).length; line++)
          PlanShareTextLine(kind, line),
      for (var day = 0; day < days.length; day++) ...[
        if (showDayLabels) PlanShareDayLabel(day),
        if (days[day].blocks.isEmpty && !showDayLabels) PlanShareEmptyDay(day),
        for (final (index, block) in days[day].blocks.indexed)
          for (var row = 0; row < PlanBlockCard.rowCountOf(block); row++)
            PlanShareBlockRow(day: day, block: index, row: row),
      ],
    ];
  }
}

/// I due testi liberi della scheda, nell'ordine in cui compaiono.
enum PlanShareText {
  description,
  notes;

  /// Le righe del testo; nessuna se il testo manca.
  List<String> linesOf(WorkoutPlan plan) {
    final text = switch (this) {
      PlanShareText.description => plan.description,
      PlanShareText.notes => plan.notes,
    };
    return (text ?? '').isEmpty ? const [] : text!.split('\n');
  }
}

/// Una riga della descrizione o delle note della scheda.
final class PlanShareTextLine extends PlanSharePiece {
  const PlanShareTextLine(this.text, this.line);

  final PlanShareText text;
  final int line;
}

/// L'etichetta di un giorno, con le sue note (o con l'avviso che il giorno
/// non ha blocchi). C'è solo sulle schede di più giorni, come nel dettaglio.
final class PlanShareDayLabel extends PlanSharePiece {
  const PlanShareDayLabel(this.day);

  final int day;
}

/// L'unico giorno di una scheda a giorno singolo, quando non ha blocchi: non
/// avendo etichetta, l'avviso "nessun blocco" ha bisogno di un pezzo suo.
final class PlanShareEmptyDay extends PlanSharePiece {
  const PlanShareEmptyDay(this.day);

  final int day;
}

/// Una riga di un blocco: un esercizio, o una riga del testo libero (vedi
/// [PlanBlockCard.rowCountOf]). La prima porta con sé l'intestazione del
/// blocco.
final class PlanShareBlockRow extends PlanSharePiece {
  const PlanShareBlockRow({
    required this.day,
    required this.block,
    required this.row,
  });

  final int day;
  final int block;
  final int row;
}

/// Una pagina dell'immagine condivisa: un tratto contiguo della scheda
/// ([pieces]), con la testata in cima e la firma in fondo.
///
/// La prima pagina si apre col titolo della scheda, le successive con il suo
/// nome in piccolo: ogni pagina viaggia da sola in una chat, e da sola deve
/// dire di che scheda è.
class PlanSharePage extends StatelessWidget {
  const PlanSharePage({
    required this.plan,
    required this.locale,
    required this.brightness,
    required this.pieces,
    required this.index,
    required this.count,
    super.key,
  });

  final WorkoutPlan plan;
  final Locale locale;
  final Brightness brightness;

  /// I pezzi della scheda che stanno in questa pagina, in ordine.
  final List<PlanSharePiece> pieces;

  /// Posizione della pagina (da zero) e numero di pagine.
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Localizations(
          locale: locale,
          delegates: AppLocalizations.localizationsDelegates,
          child: Theme(
            data: AppTheme.of(brightness),
            child: Builder(builder: _buildPage),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ColoredBox(
      color: context.colors.background,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (index == 0) ...[
              Text(plan.name, style: context.type.screenTitle),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: MetaChip(
                  icon: AppIcons.calendar,
                  label: l10n.plansDaysCount(plan.days.length),
                  tone: ChipTone.onBackground,
                  small: false,
                ),
              ),
            ] else
              Text(
                plan.name,
                style: context.type.sectionLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ..._content(l10n),
            _Signature(index: index, count: count),
          ],
        ),
      ),
    );
  }

  /// I pezzi della pagina raggruppati in ciò che si disegna: i testi della
  /// scheda per riquadro, il resto per giorno.
  List<Widget> _content(AppLocalizations l10n) {
    final days = plan.days.toList();
    final showDayLabels = days.length > 1;
    final widgets = <Widget>[];

    var i = 0;
    while (i < pieces.length) {
      final first = pieces[i];
      var j = i + 1;

      if (first is PlanShareTextLine) {
        while (j < pieces.length &&
            pieces[j] is PlanShareTextLine &&
            (pieces[j] as PlanShareTextLine).text == first.text) {
          j++;
        }
        final lines = first.text.linesOf(plan);
        widgets.add(
          _TextSection(
            label: switch (first.text) {
              PlanShareText.description => l10n.planDetailDescriptionLabel,
              PlanShareText.notes => l10n.planDetailNotesLabel,
            },
            text: [
              for (final piece in pieces.sublist(i, j))
                lines[(piece as PlanShareTextLine).line],
            ].join('\n'),
          ),
        );
      } else {
        // Tutto ciò che non è un testo della scheda appartiene a un giorno.
        final day = _dayOf(first)!;
        while (j < pieces.length && _dayOf(pieces[j]) == day) {
          j++;
        }
        widgets.add(
          PlanDaySection(
            day: days[day],
            showLabel: showDayLabels,
            part: _dayPart(pieces.sublist(i, j)),
          ),
        );
      }
      i = j;
    }
    return widgets;
  }

  static int? _dayOf(PlanSharePiece piece) => switch (piece) {
    PlanShareTextLine() => null,
    PlanShareDayLabel(:final day) => day,
    PlanShareEmptyDay(:final day) => day,
    PlanShareBlockRow(:final day) => day,
  };

  /// La parte di giorno fatta da [pieces], tutti dello stesso giorno: quali
  /// blocchi, con quali righe, e se la parte comincia dal giorno stesso.
  static PlanDayPart _dayPart(List<PlanSharePiece> pieces) {
    final blocks = <PlanBlockRows>[];
    for (final piece in pieces.whereType<PlanShareBlockRow>()) {
      final last = blocks.isEmpty ? null : blocks.last;
      if (last != null && last.block == piece.block) {
        blocks.last = PlanBlockRows(
          block: piece.block,
          start: last.start,
          end: piece.row + 1,
        );
      } else {
        blocks.add(
          PlanBlockRows(
            block: piece.block,
            start: piece.row,
            end: piece.row + 1,
          ),
        );
      }
    }
    return PlanDayPart(
      opensDay: pieces.first is! PlanShareBlockRow,
      blocks: blocks,
    );
  }
}

/// Descrizione o note: label grigia + riquadro bianco, come nel dettaglio.
///
/// Non usa `Section` perché quello imposta `crossAxisAlignment.stretch` su una
/// colonna che qui è già stirata, e soprattutto perché la label qui deve
/// restare attaccata al testo anche senza il resto della pagina intorno — la
/// si ripete anche in cima alla pagina che riprende un testo a metà.
class _TextSection extends StatelessWidget {
  const _TextSection({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: context.type.sectionLabel),
          const SizedBox(height: AppSpacing.md),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.card,
              vertical: AppSpacing.lg,
            ),
            child: Text(text, style: context.type.paragraph),
          ),
        ],
      ),
    );
  }
}

/// La firma in fondo a ogni pagina: il marchio con il nome dell'app a destra
/// e, se le pagine sono più d'una, a che punto si è a sinistra.
///
/// Il marchio ridisegna l'icona dell'app — la spunta su un quadrato pieno —
/// con i colori del blocco pieno invece che col lime: nell'immagine il lime
/// non compare (vedi [PlanShareImage]).
class _Signature extends StatelessWidget {
  const _Signature({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Row(
        children: [
          if (count > 1)
            Text(
              l10n.planSharePageIndicator(index + 1, count),
              style: context.type.meta,
            ),
          const Spacer(),
          Container(
            height: 26,
            width: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.colors.inkSurface,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: LinearIcon(
              AppIcons.check,
              size: 18,
              color: context.colors.onInkSurface,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(AppConstants.appName, style: context.type.subtitle),
        ],
      ),
    );
  }
}

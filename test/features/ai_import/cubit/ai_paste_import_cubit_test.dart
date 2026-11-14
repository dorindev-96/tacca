import 'dart:typed_data';

import 'package:tacca/data/entities/block.dart';
import 'package:tacca/features/ai_import/cubit/ai_paste_import_cubit.dart';
import 'package:tacca/features/ai_import/cubit/ai_paste_import_state.dart';
import 'package:tacca/services/share/text_share_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes.dart';

const _validResponse = '''
Certo, ecco la tua scheda!

```json
{
  "name": "Full body",
  "days": [
    {
      "label": "Giorno 1",
      "blocks": [
        {
          "type": "standard",
          "exercises": [{ "name": "Panca piana", "sets": 4, "reps": "8" }]
        }
      ]
    }
  ]
}
```

Fammi sapere se vuoi che cambi qualcosa.
''';

void main() {
  late FakeImageInput imageInput;
  late FakeImageStore imageStore;
  late FakeOcrService ocr;
  late RecordingTextShareService share;
  late RecordingClipboardService clipboard;

  setUp(() {
    imageInput = FakeImageInput();
    imageStore = FakeImageStore();
    ocr = FakeOcrService();
    share = RecordingTextShareService();
    clipboard = RecordingClipboardService();
  });

  AiPasteImportCubit buildCubit() => AiPasteImportCubit(
    imageInput: imageInput,
    imageStore: imageStore,
    ocr: ocr,
    share: share,
    clipboard: clipboard,
  );

  group('primo passo: preparare il messaggio', () {
    test('le foto passano dall\'OCR e il testo finisce nel campo, dove si '
        'può ancora correggere', () async {
      final cubit = buildCubit();
      final photo = Uint8List.fromList([7]);
      ocr.texts[photo] = 'Panca 10x4';
      imageInput.cameraResult = photo;

      await cubit.addFromCamera();

      expect(ocr.calls, [photo]);
      expect(cubit.state.text, 'Panca 10x4');
      expect(cubit.state.usedOcr, isTrue);
      expect(cubit.state.isReadingImages, isFalse);
      expect(cubit.state.images, hasLength(1));
    });

    test('il testo delle foto si aggiunge a quello già scritto', () async {
      final cubit = buildCubit();
      final photo = Uint8List.fromList([7]);
      ocr.texts[photo] = 'Squat 10x4';
      imageInput.cameraResult = photo;

      cubit.updateText('Giorno 1');
      await cubit.addFromCamera();

      expect(cubit.state.text, 'Giorno 1\n\nSquat 10x4');
    });

    test('una foto illeggibile non fa perdere le altre (RNF-05)', () async {
      final cubit = buildCubit();
      final bad = Uint8List.fromList([1]);
      final good = Uint8List.fromList([2]);
      ocr.failing.add(bad);
      ocr.texts[good] = 'Stacco 5x5';
      imageInput.galleryResult = [bad, good];

      await cubit.addFromGallery();

      expect(cubit.state.text, 'Stacco 5x5');
      expect(cubit.state.error, isNull);
    });

    test('OCR senza testo leggibile: errore, niente da mandare', () async {
      final cubit = buildCubit();
      imageInput.cameraResult = Uint8List.fromList([7]);

      await cubit.addFromCamera();

      expect(cubit.state.error, AiPasteImportError.ocrEmpty);
      expect(cubit.state.text, isEmpty);
      expect(cubit.state.canContinue, isFalse);
    });

    test('continuare manda al foglio di condivisione il prompt con dentro la '
        'scheda e le indicazioni, senza toccare gli appunti', () async {
      final cubit = buildCubit()
        ..updateText('Panca 10x4 1\'30"')
        ..updateHint('è una scheda push');

      final delivery = await cubit.continueToPaste();

      expect(delivery, AiPasteDelivery.shared);
      expect(cubit.state.step, AiPasteImportStep.paste);
      expect(share.last, contains('Panca 10x4 1\'30"'));
      expect(share.last, contains('=== WORKOUT PLAN ==='));
      expect(share.last, contains('è una scheda push'));
      // Niente copia silenziosa: Android annuncia ogni scrittura negli
      // appunti e direbbe che è successo qualcos'altro.
      expect(clipboard.written, isEmpty);
      // Il prompt resta nello stato: si deve poter rimandare dal passo 2.
      expect(cubit.state.prompt, share.last);
    });

    test(
      'un foglio chiuso senza scegliere niente lascia tutto com\'è',
      () async {
        share.outcome = TextShareOutcome.dismissed;
        final cubit = buildCubit()..updateText('Panca 10x4');

        final delivery = await cubit.continueToPaste();

        expect(delivery, AiPasteDelivery.cancelled);
        expect(cubit.state.step, AiPasteImportStep.compose);
        expect(clipboard.written, isEmpty);
      },
    );

    test('senza foglio di condivisione il prompt finisce negli appunti e si '
        'va avanti lo stesso', () async {
      share.outcome = TextShareOutcome.unavailable;
      final cubit = buildCubit()..updateText('Panca 10x4');

      final delivery = await cubit.continueToPaste();

      expect(delivery, AiPasteDelivery.copied);
      expect(cubit.state.step, AiPasteImportStep.paste);
      expect(clipboard.last, cubit.state.prompt);
    });

    test('senza testo non si va avanti e non esce niente', () async {
      final cubit = buildCubit();

      final delivery = await cubit.continueToPaste();

      expect(delivery, AiPasteDelivery.cancelled);
      expect(cubit.state.step, AiPasteImportStep.compose);
      expect(share.shared, isEmpty);
      expect(clipboard.written, isEmpty);
    });
  });

  group('secondo passo: riportare la risposta', () {
    test('una risposta valida diventa bozza, con gli originali allegati '
        '(RF-03)', () async {
      final cubit = buildCubit();
      final photo = Uint8List.fromList([7]);
      ocr.texts[photo] = 'Panca 10x4';
      imageInput.cameraResult = photo;
      await cubit.addFromCamera();
      await cubit.continueToPaste();

      cubit.updateResponse(_validResponse);
      await cubit.finish();

      final draft = cubit.state.draft!;
      expect(draft.name, 'Full body');
      expect(draft.days.single.blocks.single.type, BlockType.standard);
      expect(
        draft.days.single.blocks.single.exercises.single.name,
        'Panca piana',
      );
      expect(draft.imagePaths, ['plan_images/img_1.jpg']);
      expect(cubit.state.usedFallback, isFalse);
      expect(cubit.state.isParsing, isFalse);
    });

    test('una risposta non utilizzabile lascia tutto dov\'è e conserva '
        'l\'errore da rimandare alla chat', () async {
      final cubit = buildCubit()
        ..updateResponse('Non ci sono riuscito, scusa.');

      await cubit.finish();

      expect(cubit.state.draft, isNull);
      expect(cubit.state.error, AiPasteImportError.parse);
      expect(cubit.state.parseError, isNotNull);
      expect(cubit.state.response, 'Non ci sono riuscito, scusa.');
    });

    test('il messaggio di correzione va al foglio di condivisione e porta '
        'con sé l\'errore del parser', () async {
      final cubit = buildCubit()..updateResponse('{"name": "Senza giorni"}');
      await cubit.finish();

      final delivery = await cubit.shareCorrection();

      expect(delivery, AiPasteDelivery.shared);
      expect(share.last, contains(cubit.state.parseError!));
      expect(share.last, contains('```json'));
    });

    test('la correzione si può anche copiare, e negli appunti va lo stesso '
        'messaggio', () async {
      final cubit = buildCubit()..updateResponse('{"name": "Senza giorni"}');
      await cubit.finish();

      await cubit.copyCorrection();

      expect(clipboard.last, contains(cubit.state.parseError!));
      expect(share.shared, isEmpty);
    });

    test('dal secondo passo il prompt si rimanda o si copia', () async {
      final cubit = buildCubit()..updateText('Panca 10x4');
      await cubit.continueToPaste();

      await cubit.sharePrompt();
      await cubit.copyPrompt();

      expect(share.shared, [cubit.state.prompt, cubit.state.prompt]);
      expect(clipboard.last, cubit.state.prompt);
    });

    test('l\'uscita di sicurezza conserva la risposta come testo libero '
        '(RNF-05)', () async {
      final cubit = buildCubit()..updateResponse('Lunedì: panca, croci, dip');

      await cubit.keepAsFreeText();

      final block = cubit.state.draft!.days.single.blocks.single;
      expect(block.type, BlockType.freeText);
      expect(block.freeTextContent, 'Lunedì: panca, croci, dip');
      expect(cubit.state.usedFallback, isTrue);
    });

    test('incollare dagli appunti riempie il campo della risposta', () async {
      final cubit = buildCubit();
      clipboard.content = _validResponse;

      await cubit.pasteResponse();

      expect(cubit.state.response, _validResponse);
    });

    test('tornare al primo passo non perde niente', () async {
      final cubit = buildCubit()..updateText('Panca 10x4');
      await cubit.continueToPaste();
      cubit.updateResponse('risposta a metà');

      cubit.backToCompose();

      expect(cubit.state.step, AiPasteImportStep.compose);
      expect(cubit.state.text, 'Panca 10x4');
      expect(cubit.state.response, 'risposta a metà');
    });
  });

  group('testo condiviso con l\'app da un\'altra app', () {
    test('nel secondo passo è la risposta, e si legge subito senza premere '
        'Fine', () async {
      final cubit = buildCubit()..updateText('Panca 10x4');
      await cubit.continueToPaste();

      await cubit.receiveSharedText(_validResponse);

      expect(cubit.state.response, _validResponse);
      expect(cubit.state.draft?.name, 'Full body');
    });

    test('nel secondo passo una risposta che non si legge mostra l\'errore '
        'come se fosse stata incollata', () async {
      final cubit = buildCubit()..updateText('Panca 10x4');
      await cubit.continueToPaste();

      await cubit.receiveSharedText('Non ci sono riuscito, scusa.');

      expect(cubit.state.step, AiPasteImportStep.paste);
      expect(cubit.state.draft, isNull);
      expect(cubit.state.error, AiPasteImportError.parse);
      expect(cubit.state.response, 'Non ci sono riuscito, scusa.');
    });

    test('nel primo passo un testo con dentro un JSON è la risposta: si '
        'passa al secondo passo e si legge', () async {
      final cubit = buildCubit();

      await cubit.receiveSharedText(_validResponse);

      expect(cubit.state.step, AiPasteImportStep.paste);
      expect(cubit.state.draft?.name, 'Full body');
    });

    test('nel primo passo un testo senza JSON è la scheda: va nel campo, in '
        'coda a quello che c\'è', () async {
      final cubit = buildCubit()..updateText('Giorno 1');

      await cubit.receiveSharedText('Panca 10x4\nSquat 10x4\n');

      expect(cubit.state.step, AiPasteImportStep.compose);
      expect(cubit.state.text, 'Giorno 1\n\nPanca 10x4\nSquat 10x4');
      expect(cubit.state.draft, isNull);
    });

    test('un testo vuoto non fa niente', () async {
      final cubit = buildCubit()..updateText('Giorno 1');

      await cubit.receiveSharedText('   \n');

      expect(cubit.state.text, 'Giorno 1');
      expect(cubit.state.step, AiPasteImportStep.compose);
    });
  });
}

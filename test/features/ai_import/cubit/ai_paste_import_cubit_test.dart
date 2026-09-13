import 'dart:typed_data';

import 'package:tacca/data/entities/block.dart';
import 'package:tacca/features/ai_import/cubit/ai_paste_import_cubit.dart';
import 'package:tacca/features/ai_import/cubit/ai_paste_import_state.dart';
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
  late RecordingClipboardService clipboard;

  setUp(() {
    imageInput = FakeImageInput();
    imageStore = FakeImageStore();
    ocr = FakeOcrService();
    clipboard = RecordingClipboardService();
  });

  AiPasteImportCubit buildCubit() => AiPasteImportCubit(
    imageInput: imageInput,
    imageStore: imageStore,
    ocr: ocr,
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

    test('OCR senza testo leggibile: errore, niente da copiare', () async {
      final cubit = buildCubit();
      imageInput.cameraResult = Uint8List.fromList([7]);

      await cubit.addFromCamera();

      expect(cubit.state.error, AiPasteImportError.ocrEmpty);
      expect(cubit.state.text, isEmpty);
      expect(cubit.state.canContinue, isFalse);
    });

    test('continuare copia negli appunti il prompt con dentro la scheda e le '
        'indicazioni', () async {
      final cubit = buildCubit()
        ..updateText('Panca 10x4 1\'30"')
        ..updateHint('è una scheda push');

      await cubit.continueToPaste();

      expect(cubit.state.step, AiPasteImportStep.paste);
      expect(clipboard.last, contains('Panca 10x4 1\'30"'));
      expect(clipboard.last, contains('=== WORKOUT PLAN ==='));
      expect(clipboard.last, contains('è una scheda push'));
      // Il prompt resta nello stato: si deve poter ricopiare dal passo 2.
      expect(cubit.state.prompt, clipboard.last);
    });

    test('senza testo non si va avanti e non si copia niente', () async {
      final cubit = buildCubit();

      await cubit.continueToPaste();

      expect(cubit.state.step, AiPasteImportStep.compose);
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

    test(
      'il messaggio di correzione porta con sé l\'errore del parser',
      () async {
        final cubit = buildCubit()..updateResponse('{"name": "Senza giorni"}');
        await cubit.finish();

        await cubit.copyCorrection();

        expect(clipboard.last, contains(cubit.state.parseError!));
        expect(clipboard.last, contains('```json'));
      },
    );

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
}

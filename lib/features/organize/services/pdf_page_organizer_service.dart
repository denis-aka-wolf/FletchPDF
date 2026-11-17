import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// Exports an edited page arrangement as a new PDF without changing the source.
class PdfPageOrganizerService {
  const PdfPageOrganizerService();

  Future<String> save({
    required PdfDocument sourceDocument,
    required List<PdfPage> pages,
    required String outputPath,
    bool overwriteExisting = false,
  }) async {
    if (pages.isEmpty) {
      throw ArgumentError('Нельзя сохранить PDF без страниц.');
    }

    final output = p.normalize(p.absolute(outputPath));
    if (p.extension(output).toLowerCase() != '.pdf') {
      throw ArgumentError('Выходной файл должен иметь расширение .pdf.');
    }
    final directory = Directory(p.dirname(output));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final outputFile = File(output);
    if (await outputFile.exists() && !overwriteExisting) {
      throw FileSystemException(
        'Выходной файл уже существует. Подтвердите перезапись.',
        output,
      );
    }

    final operationId = DateTime.now().microsecondsSinceEpoch;
    final temporaryFile = File('$output.$operationId.tmp');
    final backupFile = File('$output.$operationId.bak');
    PdfDocument? resultDocument;
    var backedUp = false;
    var committed = false;

    try {
      resultDocument = await PdfDocument.createNew(sourceName: output);
      resultDocument.pages = List<PdfPage>.of(pages);

      // The source document must remain open until encodePdf completes.
      final bytes = await resultDocument.encodePdf();
      if (bytes.isEmpty) {
        throw StateError('PDFium вернул пустой результат.');
      }
      await temporaryFile.writeAsBytes(bytes, flush: true);

      if (await outputFile.exists()) {
        if (!overwriteExisting) {
          throw FileSystemException(
            'Выходной файл уже существует. Подтвердите перезапись.',
            output,
          );
        }
        await outputFile.rename(backupFile.path);
        backedUp = true;
      }

      await temporaryFile.rename(output);
      committed = true;

      if (await outputFile.length() == 0) {
        throw FileSystemException('Созданный PDF оказался пустым.', output);
      }

      if (backedUp && await backupFile.exists()) {
        try {
          await backupFile.delete();
          backedUp = false;
        } on FileSystemException {
          // A leftover backup is preferable to reporting a failed export.
        }
      }
      return output;
    } on Object {
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
      if (committed && await outputFile.exists()) {
        await outputFile.delete();
      }
      if (backedUp && await backupFile.exists()) {
        await backupFile.rename(output);
      }
      rethrow;
    } finally {
      if (resultDocument != null) {
        await resultDocument.dispose();
      }
    }
  }
}

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart';

import 'pdf_nup_geometry.dart';

/// Places source pages as vector Form XObjects on new sheets using PDFium.
class PdfNupService {
  const PdfNupService();

  Future<String> createNup({
    required String sourcePath,
    required String outputPath,
    required int columns,
    required int rows,
    required double paperWidthMm,
    required double paperHeightMm,
    required double marginMm,
    required double spacingMm,
    bool overwriteExisting = false,
  }) async {
    final source = p.normalize(p.absolute(sourcePath));
    final output = p.normalize(p.absolute(outputPath));
    if (p.extension(source).toLowerCase() != '.pdf' ||
        p.extension(output).toLowerCase() != '.pdf') {
      throw ArgumentError('Исходный и выходной файлы должны быть PDF.');
    }
    if (_samePath(source, output)) {
      throw ArgumentError('Нельзя сохранить результат поверх исходного PDF.');
    }

    final sourceFile = File(source);
    if (!await sourceFile.exists()) {
      throw FileSystemException('Исходный PDF не найден.', source);
    }
    if (await sourceFile.length() == 0) {
      throw FileSystemException('Исходный PDF пуст.', source);
    }

    final cells = PdfNupGeometry.layout(
      paperWidthMm: paperWidthMm,
      paperHeightMm: paperHeightMm,
      columns: columns,
      rows: rows,
      marginMm: marginMm,
      spacingMm: spacingMm,
    );
    final capacity = columns * rows;

    final outputDirectory = Directory(p.dirname(output));
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }

    final outputFile = File(output);
    if (await outputFile.exists() && !overwriteExisting) {
      throw FileSystemException(
        'Выходной файл уже существует. Подтвердите перезапись.',
        output,
      );
    }

    PdfDocument? sourceDocument;
    final operationId = DateTime.now().microsecondsSinceEpoch;
    final temporaryFile = File('$output.$operationId.tmp');
    final backupFile = File('$output.$operationId.bak');
    var backedUp = false;
    var committed = false;

    try {
      sourceDocument = await PdfDocument.openFile(source);
      final pageCount = sourceDocument.pages.length;
      if (pageCount == 0) {
        throw StateError('В исходном PDF нет страниц.');
      }

      final paperWidth =
          paperWidthMm * PdfNupGeometry.pointsPerMillimeter;
      final paperHeight =
          paperHeightMm * PdfNupGeometry.pointsPerMillimeter;

      final nativeOutput = await temporaryFile.open(mode: FileMode.write);
      try {
        final saved = await sourceDocument.useNativeDocumentHandle(
          (nativeDocumentHandle) {
            final pdfium = getPdfium();
            final nativeSource = ffi.Pointer<fpdf_document_t__>.fromAddress(
              nativeDocumentHandle,
            );
            final nativeOutputDocument = pdfium.FPDF_CreateNewDocument();
            if (nativeOutputDocument.address == 0) {
              throw StateError('PDFium не смог создать выходной документ.');
            }

            try {
              final sheetCount = (pageCount + capacity - 1) ~/ capacity;
              for (var sheetIndex = 0; sheetIndex < sheetCount; sheetIndex++) {
                final page = pdfium.FPDFPage_New(
                  nativeOutputDocument,
                  sheetIndex,
                  paperWidth,
                  paperHeight,
                );
                if (page.address == 0) {
                  throw StateError(
                    'PDFium не смог создать лист ${sheetIndex + 1}.',
                  );
                }

                try {
                  for (var cellIndex = 0; cellIndex < capacity; cellIndex++) {
                    final sourcePageIndex = sheetIndex * capacity + cellIndex;
                    if (sourcePageIndex >= pageCount) break;

                    final xobject = pdfium.FPDF_NewXObjectFromPage(
                      nativeOutputDocument,
                      nativeSource,
                      sourcePageIndex,
                    );
                    if (xobject.address == 0) {
                      throw StateError(
                        'Не удалось подготовить страницу ${sourcePageIndex + 1}.',
                      );
                    }

                    final pageObject = pdfium.FPDF_NewFormObjectFromXObject(
                      xobject,
                    );
                    pdfium.FPDF_CloseXObject(xobject);
                    if (pageObject.address == 0) {
                      throw StateError(
                        'Не удалось разместить страницу ${sourcePageIndex + 1}.',
                      );
                    }

                    final bounds = calloc<ffi.Float>(4);
                    try {
                      final hasBounds = pdfium.FPDFPageObj_GetBounds(
                        pageObject,
                        bounds,
                        bounds + 1,
                        bounds + 2,
                        bounds + 3,
                      );
                      if (hasBounds == 0) {
                        pdfium.FPDFPageObj_Destroy(pageObject);
                        throw StateError(
                          'Не удалось определить размеры страницы ${sourcePageIndex + 1}.',
                        );
                      }

                      final left = bounds[0];
                      final bottom = bounds[1];
                      final right = bounds[2];
                      final top = bounds[3];
                      final sourceWidth = right - left;
                      final sourceHeight = top - bottom;
                      if (sourceWidth <= 0 || sourceHeight <= 0) {
                        pdfium.FPDFPageObj_Destroy(pageObject);
                        throw StateError(
                          'Страница ${sourcePageIndex + 1} имеет некорректные размеры.',
                        );
                      }

                      final cell = cells[cellIndex];
                      final scale = (cell.width / sourceWidth)
                          .clamp(0.0, cell.height / sourceHeight)
                          .toDouble();
                      final x = cell.left +
                          (cell.width - sourceWidth * scale) / 2 -
                          left * scale;
                      final y = cell.bottom +
                          (cell.height - sourceHeight * scale) / 2 -
                          bottom * scale;

                      pdfium.FPDFPageObj_Transform(
                        pageObject,
                        scale,
                        0,
                        0,
                        scale,
                        x,
                        y,
                      );
                      final inserted = pdfium.FPDFPage_InsertObject(
                        page,
                        pageObject,
                      );
                      if (inserted == 0) {
                        pdfium.FPDFPageObj_Destroy(pageObject);
                        throw StateError(
                          'PDFium не смог добавить страницу ${sourcePageIndex + 1} на лист.',
                        );
                      }
                    } finally {
                      calloc.free(bounds);
                    }
                  }

                  if (pdfium.FPDFPage_GenerateContent(page) == 0) {
                    throw StateError(
                      'Не удалось сформировать содержимое листа ${sheetIndex + 1}.',
                    );
                  }
                } finally {
                  pdfium.FPDF_ClosePage(page);
                }
              }

              final writer = calloc<FPDF_FILEWRITE>();
              Object? writeFailure;
              final callback = ffi.NativeCallable<
                  int Function(
                    ffi.Pointer<FPDF_FILEWRITE>,
                    ffi.Pointer<ffi.Void>,
                    int,
                  )>.isolateLocal((
                ffi.Pointer<FPDF_FILEWRITE> _,
                ffi.Pointer<ffi.Void> data,
                int size,
              ) {
                try {
                  nativeOutput.writeFromSync(
                    data.cast<ffi.Uint8>().asTypedList(size),
                  );
                  return 1;
                } on Object catch (error) {
                  writeFailure = error;
                  return 0;
                }
              }, exceptionalReturn: 0);

              try {
                writer.ref
                  ..version = 1
                  ..WriteBlock = callback.nativeFunction;
                if (pdfium.FPDF_SaveAsCopy(
                          nativeOutputDocument,
                          writer,
                          0,
                        ) ==
                        0 ||
                    writeFailure != null) {
                  throw StateError(
                    'PDFium не смог сохранить результат N-up'
                    '${writeFailure == null ? '.' : ': $writeFailure'}',
                  );
                }
              } finally {
                callback.close();
                calloc.free(writer);
              }
              return true;
            } finally {
              pdfium.FPDF_CloseDocument(nativeOutputDocument);
            }
          },
        );
        if (!saved) {
          throw StateError('Не удалось сформировать PDF с несколькими страницами на листе.');
        }
        await nativeOutput.flush();
      } finally {
        await nativeOutput.close();
      }

      if (!await temporaryFile.exists() || await temporaryFile.length() == 0) {
        throw StateError('PDFium создал пустой выходной файл.');
      }

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
          // Keep the backup rather than report failure after a successful save.
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
      if (sourceDocument != null) {
        await sourceDocument.dispose();
      }
    }
  }

  bool _samePath(String first, String second) {
    return Platform.isWindows
        ? first.toLowerCase() == second.toLowerCase()
        : first == second;
  }
}

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart';

import 'pdf_booklet_geometry.dart';

/// Creates a duplex-printable booklet using vector Form XObjects.
class PdfBookletService {
  const PdfBookletService();

  Future<String> createBooklet({
    required String sourcePath,
    required String outputPath,
    required double paperWidthMm,
    required double paperHeightMm,
    required double marginMm,
    required double gutterMm,
    bool rightBinding = false,
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
    if (paperWidthMm <= paperHeightMm) {
      throw ArgumentError('Для буклета требуется альбомная ориентация листа.');
    }

    final sourceFile = File(source);
    if (!await sourceFile.exists()) {
      throw FileSystemException('Исходный PDF не найден.', source);
    }
    if (await sourceFile.length() == 0) {
      throw FileSystemException('Исходный PDF пуст.', source);
    }

    final cells = PdfBookletGeometry.layout(
      paperWidthMm: paperWidthMm,
      paperHeightMm: paperHeightMm,
      marginMm: marginMm,
      gutterMm: gutterMm,
    );

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
      final imposedSheets = PdfBookletGeometry.impose(
        pageCount: pageCount,
        rightBinding: rightBinding,
      );

      final paperWidth =
          paperWidthMm * PdfBookletGeometry.pointsPerMillimeter;
      final paperHeight =
          paperHeightMm * PdfBookletGeometry.pointsPerMillimeter;

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
              var outputPageIndex = 0;
              for (final sheet in imposedSheets) {
                for (final side in [sheet.front, sheet.back]) {
                  final page = pdfium.FPDFPage_New(
                    nativeOutputDocument,
                    outputPageIndex++,
                    paperWidth,
                    paperHeight,
                  );
                  if (page.address == 0) {
                    throw StateError(
                      'PDFium не смог создать сторону буклета $outputPageIndex.',
                    );
                  }

                  try {
                    final pageIndices = [
                      side.leftPageIndex,
                      side.rightPageIndex,
                    ];
                    for (var cellIndex = 0;
                        cellIndex < pageIndices.length;
                        cellIndex++) {
                      final sourcePageIndex = pageIndices[cellIndex];
                      if (sourcePageIndex == null) continue;

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

                      final pageObject =
                          pdfium.FPDF_NewFormObjectFromXObject(xobject);
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
                        var left = bounds[0];
                        var bottom = bounds[1];
                        var right = bounds[2];
                        var top = bounds[3];
                        var sourceWidth = right - left;
                        var sourceHeight = top - bottom;

                        final boundsAreValid = hasBounds != 0 &&
                            left.isFinite &&
                            bottom.isFinite &&
                            right.isFinite &&
                            top.isFinite &&
                            sourceWidth.isFinite &&
                            sourceHeight.isFinite &&
                            sourceWidth > 0 &&
                            sourceHeight > 0;
                        if (!boundsAreValid) {
                          final sourcePage = pdfium.FPDF_LoadPage(
                            nativeSource,
                            sourcePageIndex,
                          );
                          if (sourcePage.address == 0) {
                            pdfium.FPDFPageObj_Destroy(pageObject);
                            throw StateError(
                              'Не удалось определить размеры страницы ${sourcePageIndex + 1}.',
                            );
                          }

                          double pageWidth;
                          double pageHeight;
                          try {
                            pageWidth =
                                pdfium.FPDF_GetPageWidthF(sourcePage);
                            pageHeight =
                                pdfium.FPDF_GetPageHeightF(sourcePage);
                          } finally {
                            pdfium.FPDF_ClosePage(sourcePage);
                          }

                          if (!pageWidth.isFinite ||
                              !pageHeight.isFinite ||
                              pageWidth <= 0 ||
                              pageHeight <= 0) {
                            pdfium.FPDFPageObj_Destroy(pageObject);
                            throw StateError(
                              'PDFium вернул недопустимые размеры страницы ${sourcePageIndex + 1}.',
                            );
                          }
                          left = 0;
                          bottom = 0;
                          right = pageWidth;
                          top = pageHeight;
                          sourceWidth = pageWidth;
                          sourceHeight = pageHeight;
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
                            'PDFium не смог добавить страницу ${sourcePageIndex + 1} на лист буклета.',
                          );
                        }
                      } finally {
                        calloc.free(bounds);
                      }
                    }

                    if (pdfium.FPDFPage_GenerateContent(page) == 0) {
                      throw StateError(
                        'Не удалось сформировать сторону буклета $outputPageIndex.',
                      );
                    }
                  } finally {
                    pdfium.FPDF_ClosePage(page);
                  }
                }
              }

              final writer = calloc<FPDF_FILEWRITE>();
              Object? writeFailure;
              final callback = ffi.NativeCallable<
                  ffi.Int Function(
                    ffi.Pointer<FPDF_FILEWRITE>,
                    ffi.Pointer<ffi.Void>,
                    ffi.UnsignedLong,
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
                    'PDFium не смог сохранить буклет'
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
          throw StateError('Не удалось сформировать PDF-буклет.');
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

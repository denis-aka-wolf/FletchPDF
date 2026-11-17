# Third-party notices

Этот файл является начальным реестром зависимостей. Он не заменяет автоматическую проверку lock-файла и бинарного состава релиза.

## Dart / Flutter dependencies

| Компонент | Назначение | Лицензия | Источник |
|---|---|---|---|
| Flutter SDK | UI framework | BSD-3-Clause | https://github.com/flutter/flutter |
| Dart SDK | Runtime / language | BSD-3-Clause | https://github.com/dart-lang/sdk |
| pdfrx 2.12.1 | PDF viewer / PDFium integration | MIT | https://pub.dev/packages/pdfrx |
| pdfrx_engine 0.9.2 | PDFium document/page manipulation API (transitive dependency) | MIT | https://pub.dev/packages/pdfrx_engine |
| pdfium_flutter 0.4.2 | Native PDFium integration and runtime bindings (direct dependency) | BSD-3-Clause, verify bundled notices | https://pub.dev/packages/pdfium_flutter |
| pdfium_dart 0.4.2 | PDFium Dart FFI bindings (transitive dependency) | BSD-3-Clause, verify bundled notices | https://pub.dev/packages/pdfium_dart |
| file_picker 13.4.0 | Native file selection (resolved from ^13.3.3) | MIT | https://pub.dev/packages/file_picker |
| path 1.9.1 | Path utilities | BSD-3-Clause | https://pub.dev/packages/path |
| ffi 2.2.0 | Native FFI memory allocation and bindings support | BSD-3-Clause | https://pub.dev/packages/ffi |
| path_provider 2.1.6 | App directories | BSD-3-Clause | https://pub.dev/packages/path_provider |
| cupertino_icons 1.0.8 | Icon font | MIT | https://pub.dev/packages/cupertino_icons |
| flutter_lints 6.0.0 | Static analysis rules (dev) | BSD-3-Clause | https://pub.dev/packages/flutter_lints |

Точные транзитивные версии фиксируются в `pubspec.lock`. Перед релизом необходимо проверить все транзитивные лицензии и notices конкретных нативных сборок.

## Native engines

Внешние native engine executables пока не включены в репозиторий или дистрибутив. PDFium поставляется зависимостями pdfrx/pdfium_flutter и используется для просмотра, объединения, изменения CropBox, векторного размещения страниц при N-up и формирования буклетов.

| Компонент | Предполагаемая лицензия | Статус |
|---|---|---|
| PDFium | BSD-3-Clause (проверить notices конкретной сборки) | Используется через pdfrx; N-up и буклет используют PDFium Form XObject API |
| QPDF | Apache-2.0 | Планируется, бинарник не включён |
| MuPDF | AGPL-3.0 / Commercial | Не включён |
| Ghostscript | AGPL-3.0 / Commercial | Не включён |
| Tesseract | Apache-2.0 | Не включён |
| LibreOffice | MPL-2.0 и лицензии компонентов | Не включён |
| veraPDF | MPL-2.0 | Не включён |

## Обязательные действия перед релизом

- Сохранить тексты лицензий и copyright notices.
- Проверить все транзитивные Dart packages.
- Зафиксировать версии и SHA-256 нативных бинарников.
- Проверить условия перераспространения и обязательства copyleft.
- Сформировать SBOM для каждого дистрибутива.
- Не использовать Syncfusion до подтверждения соответствия Community License или приобретения коммерческой лицензии.

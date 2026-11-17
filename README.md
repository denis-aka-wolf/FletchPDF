# FletchPDF

**FletchPDF** is a local-first desktop PDF workspace built with Dart and Flutter.

The project aims to provide a comprehensive set of PDF tools without a server, cloud dependency, Docker, or Java runtime. The first target is Windows 10/11 x64. Linux and macOS are planned as subsequent desktop targets.

> **Development status:** active development. This repository is the application source, not a claim that FletchPDF 1.0 is already feature-complete.

## Product principles

- Local First: documents remain on the user's device unless the user explicitly exports or shares them.
- No backend: no application server, REST API, Docker, or Java service.
- Native desktop experience: Flutter UI with native PDF engines and carefully isolated process adapters.
- Engine independence: PDF operations are accessed through Dart interfaces, not called directly from UI widgets.
- Safe operations: preserve source files by default, write outputs to an explicit destination, and report engine errors.
- License transparency: every bundled executable, native library, model, font, and Dart dependency must be recorded.

## Technology

- Flutter 3.50 / Dart 3.14 baseline.
- [pdfrx](https://pub.dev/packages/pdfrx) for PDF viewing and PDFium integration, including local page manipulation and native CropBox editing through PDFium FFI.
- [file_picker](https://pub.dev/packages/file_picker) for native file selection.
- PDF merging is implemented through the PDFium document API already used by pdfrx. QPDF remains a planned adapter for structural operations that are not covered by the current PDFium API. Its executable is not bundled.

Exact dependency versions are declared in `pubspec.yaml`. Third-party native binaries are not yet included.

## Getting started

1. Install Flutter 3.50 stable or newer and the Windows desktop build prerequisites.
2. Enable Windows Developer Mode if required by native plugin build hooks.
3. Clone this repository.
4. Run:

```powershell
flutter pub get
flutter run -d windows
```

Build a release:

```powershell
flutter build windows --release
```

## Repository layout

```text
lib/
  app/                 Application shell and theme
  core/
    engines/           PDF engine contracts and adapters
    files/             File selection and validation
    operations/        Operation state and results
  features/
    home/              Home workspace
    viewer/            PDF viewing
  shared/              Reusable UI
docs/                  Architecture and development notes
licenses/              Third-party license register
```

## PDF engine strategy

The UI must depend on Dart abstractions. Native libraries and command-line tools are integrated behind adapters. The viewer and the first page-combination workflow use pdfrx/PDFium. The merge screen supports multiple files, drag-and-drop ordering, output folder/name selection, overwrite confirmation, and local processing. The split screen accepts semicolon-separated page groups (for example, `1-3; 4-6; 7-10`) and writes each group as a separate PDF. The extraction screen collects selected pages (for example, `1-3, 5, 8-10`) into one PDF while preserving the requested order. The page organizer provides visual thumbnails, drag-and-drop reordering, deletion, duplication, clockwise rotation, undo for the latest page operations, and export to a separate PDF. The crop tool provides a draggable visual selection and applies PDFium CropBox changes to one page or all pages. The source document remains unchanged. Processing engines such as QPDF, MuPDF, Ghostscript, Tesseract, and LibreOffice will be evaluated individually for operations not covered by the existing PDFium API.

No engine is considered bundled or available until its exact version, binary provenance, platform support, redistribution terms, and license notices have been reviewed.

## Licensing

The current intended license for original FletchPDF code is **GNU AGPL v3 or later**. See [LICENSE](LICENSE).

Third-party components retain their own licenses. The presence of an AGPL license in this repository does not relicense dependencies or native tools. See [licenses/THIRD_PARTY_NOTICES.md](licenses/THIRD_PARTY_NOTICES.md).

Syncfusion components are not included in this initial dependency set. Their Community License eligibility and terms must be checked before any integration.

## Contributing

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before adding an engine or feature. Do not add downloaded native binaries without documenting their source, version, checksum, target architecture, and redistribution license.

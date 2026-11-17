import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'services/pdf_nup_geometry.dart';
import 'services/pdf_nup_service.dart';

class NupPdfScreen extends StatefulWidget {
  const NupPdfScreen({super.key});

  @override
  State<NupPdfScreen> createState() => _NupPdfScreenState();
}

class _NupPdfScreenState extends State<NupPdfScreen> {
  final PdfNupService _service = const PdfNupService();
  final TextEditingController _nameController =
      TextEditingController(text: 'document_nup');
  final TextEditingController _marginController =
      TextEditingController(text: '8');
  final TextEditingController _spacingController =
      TextEditingController(text: '4');

  File? _sourceFile;
  PdfDocument? _previewDocument;
  String? _outputDirectory;
  int _pagesPerSheet = 4;
  String _paper = 'A4';
  bool _landscape = true;
  bool _isOpening = false;
  bool _isSaving = false;
  String? _error;
  String? _savedPath;

  static const Map<String, Size> _paperSizes = {
    'A4': Size(210, 297),
    'A3': Size(297, 420),
    'Letter': Size(215.9, 279.4),
  };

  @override
  void dispose() {
    _nameController.dispose();
    _marginController.dispose();
    _spacingController.dispose();
    final document = _previewDocument;
    if (document != null) unawaited(document.dispose());
    super.dispose();
  }

  Future<void> _pickSource() async {
    if (_isOpening || _isSaving) return;
    setState(() {
      _isOpening = true;
      _error = null;
      _savedPath = null;
    });

    PdfDocument? opened;
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        dialogTitle: 'Выберите PDF для размещения страниц на листе',
      );
      if (!mounted || picked == null) return;

      final path = picked.path;
      if (path == null || path.isEmpty) {
        throw const FileSystemException('Не удалось получить путь к PDF.');
      }
      final file = File(path);
      if (!await file.exists() || await file.length() == 0) {
        throw FileSystemException('PDF-файл не найден или пуст.', path);
      }

      opened = await PdfDocument.openFile(path);
      if (opened.pages.isEmpty) {
        throw StateError('В документе нет страниц.');
      }
      if (!mounted) return;

      final previous = _previewDocument;
      setState(() {
        _sourceFile = file;
        _previewDocument = opened;
        _outputDirectory = p.dirname(path);
        _nameController.text =
            '${p.basenameWithoutExtension(path)}_nup';
        _savedPath = null;
        _error = null;
      });
      opened = null;
      if (previous != null) await previous.dispose();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    } finally {
      if (opened != null) await opened.dispose();
      if (mounted) setState(() => _isOpening = false);
    }
  }

  Future<void> _chooseOutputDirectory() async {
    if (_isSaving) return;
    final directory = await FilePicker.getDirectoryPath(
      dialogTitle: 'Выберите папку для сохранения N-up PDF',
    );
    if (!mounted || directory == null) return;
    setState(() {
      _outputDirectory = directory;
      _savedPath = null;
      _error = null;
    });
  }

  void _updateLayout(VoidCallback update) {
    setState(() {
      update();
      _savedPath = null;
      _error = null;
    });
  }

  double _numberFrom(TextEditingController controller, double fallback) {
    final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
    return value != null && value.isFinite && value >= 0 ? value : fallback;
  }

  Size get _orientedPaperSize {
    final base = _paperSizes[_paper]!;
    return _landscape ? Size(base.height, base.width) : base;
  }

  PdfNupGrid get _grid => PdfNupGeometry.gridFor(
        pagesPerSheet: _pagesPerSheet,
        landscape: _landscape,
      );

  Future<void> _save() async {
    final source = _sourceFile;
    final directory = _outputDirectory;
    if (source == null) {
      setState(() => _error = 'Сначала выберите исходный PDF.');
      return;
    }
    if (directory == null || directory.trim().isEmpty) {
      setState(() => _error = 'Выберите папку для сохранения.');
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty ||
        p.basename(name) != name ||
        name.contains(RegExp(r'[<>:"/\\|?*]'))) {
      setState(() => _error = 'Укажите корректное имя выходного файла.');
      return;
    }

    final outputPath = p.join(directory, '$name.pdf');
    final sourcePath = p.normalize(p.absolute(source.path));
    final normalizedOutput = p.normalize(p.absolute(outputPath));
    if (Platform.isWindows
        ? normalizedOutput.toLowerCase() == sourcePath.toLowerCase()
        : normalizedOutput == sourcePath) {
      setState(() => _error =
          'Выходной файл совпадает с исходным. Выберите другое имя.');
      return;
    }

    var overwrite = false;
    if (await File(outputPath).exists()) {
      if (!mounted) return;
      overwrite = await _confirmOverwrite(outputPath);
      if (!overwrite || !mounted) return;
    }

    final paperSize = _orientedPaperSize;
    final margin = _numberFrom(_marginController, -1);
    final spacing = _numberFrom(_spacingController, -1);
    if (margin < 0 || spacing < 0) {
      setState(() => _error = 'Поля и промежутки должны быть числами не меньше нуля.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
      _savedPath = null;
    });
    try {
      final result = await _service.createNup(
        sourcePath: source.path,
        outputPath: outputPath,
        columns: _grid.columns,
        rows: _grid.rows,
        paperWidthMm: paperSize.width,
        paperHeightMm: paperSize.height,
        marginMm: margin,
        spacingMm: spacing,
        overwriteExisting: overwrite,
      );
      if (!mounted) return;
      setState(() => _savedPath = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF сохранён: ${p.basename(result)}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool> _confirmOverwrite(String path) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Файл уже существует'),
        content: Text(
          'Файл "${p.basename(path)}" будет заменён. Продолжить?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Заменить'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String _readableError(Object error) {
    if (error is FileSystemException) return error.message;
    if (error is ArgumentError) {
      return error.message?.toString() ?? error.toString();
    }
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final source = _sourceFile;
    final document = _previewDocument;
    final paperSize = _orientedPaperSize;

    return Scaffold(
      appBar: AppBar(title: const Text('Несколько страниц на листе')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        const Icon(Icons.picture_as_pdf_outlined, size: 28),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            source == null
                                ? 'Исходный PDF не выбран'
                                : p.basename(source.path),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isOpening || _isSaving ? null : _pickSource,
                          icon: _isOpening
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.folder_open),
                          label: Text(_isOpening ? 'Открываем…' : 'Выбрать PDF'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (document != null) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Настройки листа',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<int>(
                          initialValue: _pagesPerSheet,
                          decoration: const InputDecoration(
                            labelText: 'Страниц на листе',
                            border: OutlineInputBorder(),
                          ),
                          items: const [2, 4, 6, 9]
                              .map((value) => DropdownMenuItem(
                                    value: value,
                                    child: Text('$value страницы'),
                                  ))
                              .toList(),
                          onChanged: _isSaving
                              ? null
                              : (value) {
                                  if (value != null) {
                                    _updateLayout(() => _pagesPerSheet = value);
                                  }
                                },
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          initialValue: _paper,
                          decoration: const InputDecoration(
                            labelText: 'Формат бумаги',
                            border: OutlineInputBorder(),
                          ),
                          items: const ['A4', 'A3', 'Letter']
                              .map((value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(value),
                                  ))
                              .toList(),
                          onChanged: _isSaving
                              ? null
                              : (value) {
                                  if (value != null) {
                                    _updateLayout(() => _paper = value);
                                  }
                                },
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('Книжная'),
                              icon: Icon(Icons.stay_current_portrait),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text('Альбомная'),
                              icon: Icon(Icons.stay_current_landscape),
                            ),
                          ],
                          selected: {_landscape},
                          onSelectionChanged: _isSaving
                              ? null
                              : (selection) => _updateLayout(
                                    () => _landscape = selection.first,
                                  ),
                        ),
                      ),
                      SizedBox(
                        width: 150,
                        child: TextField(
                          controller: _marginController,
                          enabled: !_isSaving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Поля, мм',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => _updateLayout(() {}),
                        ),
                      ),
                      SizedBox(
                        width: 170,
                        child: TextField(
                          controller: _spacingController,
                          enabled: !_isSaving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Промежуток, мм',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => _updateLayout(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Text(
                        'Предпросмотр первого листа',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Spacer(),
                      Text(
                        '${_grid.columns} × ${_grid.rows}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: _NupPreview(
                        paperSize: paperSize,
                        grid: _grid,
                        pageCount: document.pages.length,
                        marginMm: _numberFrom(_marginController, 8),
                        spacingMm: _numberFrom(_spacingController, 4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Сохранение',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    enabled: !_isSaving,
                    decoration: const InputDecoration(
                      labelText: 'Имя выходного файла',
                      suffixText: '.pdf',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _outputDirectory ?? 'Папка не выбрана',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isSaving ? null : _chooseOutputDirectory,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Папка'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_isSaving ? 'Сохранение…' : 'Создать PDF'),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Выберите PDF, чтобы настроить размещение страниц и увидеть раскладку листа.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _NupStatusPanel(message: _error!, isError: true),
                ],
                if (_savedPath != null) ...[
                  const SizedBox(height: 16),
                  _NupStatusPanel(
                    message: 'Сохранено: $_savedPath',
                    isError: false,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NupPreview extends StatelessWidget {
  const _NupPreview({
    required this.paperSize,
    required this.grid,
    required this.pageCount,
    required this.marginMm,
    required this.spacingMm,
  });

  final Size paperSize;
  final PdfNupGrid grid;
  final int pageCount;
  final double marginMm;
  final double spacingMm;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final paperWidth = paperSize.width * PdfNupGeometry.pointsPerMillimeter;
    final paperHeight = paperSize.height * PdfNupGeometry.pointsPerMillimeter;

    try {
      final cells = PdfNupGeometry.layout(
        paperWidthMm: paperSize.width,
        paperHeightMm: paperSize.height,
        columns: grid.columns,
        rows: grid.rows,
        marginMm: marginMm,
        spacingMm: spacingMm,
      );
      return AspectRatio(
        aspectRatio: paperSize.width / paperSize.height,
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.outline),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  for (var index = 0; index < cells.length; index++)
                    if (index < pageCount)
                      Positioned(
                        left: cells[index].left / paperWidth *
                            constraints.maxWidth,
                        bottom: cells[index].bottom / paperHeight *
                            constraints.maxHeight,
                        width: cells[index].width / paperWidth *
                            constraints.maxWidth,
                        height: cells[index].height / paperHeight *
                            constraints.maxHeight,
                        child: Container(
                          margin: const EdgeInsets.all(1),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer.withValues(alpha: 0.48),
                            border: Border.all(color: colors.primary),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 20,
                                color: colors.primary,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Страница ${index + 1}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              );
            },
          ),
        ),
      );
    } on ArgumentError catch (error) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          error.message?.toString() ?? 'Некорректные параметры листа.',
          style: TextStyle(color: colors.onErrorContainer),
        ),
      );
    }
  }
}

class _NupStatusPanel extends StatelessWidget {
  const _NupStatusPanel({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background =
        isError ? colors.errorContainer : colors.primaryContainer;
    final foreground =
        isError ? colors.onErrorContainer : colors.onPrimaryContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: TextStyle(color: foreground)),
    );
  }
}

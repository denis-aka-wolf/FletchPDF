import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'services/pdf_booklet_geometry.dart';
import 'services/pdf_booklet_service.dart';

class BookletPdfScreen extends StatefulWidget {
  const BookletPdfScreen({super.key});

  @override
  State<BookletPdfScreen> createState() => _BookletPdfScreenState();
}

class _BookletPdfScreenState extends State<BookletPdfScreen> {
  final PdfBookletService _service = const PdfBookletService();
  final TextEditingController _nameController =
      TextEditingController(text: 'document_booklet');
  final TextEditingController _marginController =
      TextEditingController(text: '8');
  final TextEditingController _gutterController =
      TextEditingController(text: '8');

  static const Map<String, Size> _paperSizes = {
    'A4': Size(210, 297),
    'A3': Size(297, 420),
    'Letter': Size(215.9, 279.4),
  };

  File? _sourceFile;
  PdfDocument? _previewDocument;
  String? _outputDirectory;
  String _paper = 'A4';
  bool _rightBinding = false;
  bool _isOpening = false;
  bool _isSaving = false;
  String? _error;
  String? _savedPath;

  Size get _landscapePaper {
    final size = _paperSizes[_paper]!;
    return Size(size.height, size.width);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _marginController.dispose();
    _gutterController.dispose();
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
        dialogTitle: 'Выберите PDF для создания буклета',
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
            '${p.basenameWithoutExtension(path)}_booklet';
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
      dialogTitle: 'Выберите папку для сохранения буклета',
    );
    if (!mounted || directory == null) return;
    setState(() {
      _outputDirectory = directory;
      _savedPath = null;
      _error = null;
    });
  }

  double _numberFrom(TextEditingController controller, double fallback) {
    final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
    return value != null && value.isFinite && value >= 0 ? value : fallback;
  }

  void _update(VoidCallback update) {
    setState(() {
      update();
      _savedPath = null;
      _error = null;
    });
  }

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
      setState(() =>
          _error = 'Выходной файл совпадает с исходным. Выберите другое имя.');
      return;
    }

    final margin = _numberFrom(_marginController, -1);
    final gutter = _numberFrom(_gutterController, -1);
    if (margin < 0 || gutter < 0) {
      setState(() =>
          _error = 'Поля и центральный отступ должны быть числами не меньше нуля.');
      return;
    }

    var overwrite = false;
    if (await File(outputPath).exists()) {
      if (!mounted) return;
      overwrite = await _confirmOverwrite(outputPath);
      if (!overwrite || !mounted) return;
    }

    final paper = _landscapePaper;
    setState(() {
      _isSaving = true;
      _error = null;
      _savedPath = null;
    });
    try {
      final result = await _service.createBooklet(
        sourcePath: source.path,
        outputPath: outputPath,
        paperWidthMm: paper.width,
        paperHeightMm: paper.height,
        marginMm: margin,
        gutterMm: gutter,
        rightBinding: _rightBinding,
        overwriteExisting: overwrite,
      );
      if (!mounted) return;
      setState(() => _savedPath = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Буклет сохранён: ${p.basename(result)}'),
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
    final paper = _landscapePaper;
    final margin = _numberFrom(_marginController, 8);
    final gutter = _numberFrom(_gutterController, 8);
    final sheets = document == null
        ? const <PdfBookletSheet>[]
        : PdfBookletGeometry.impose(
            pageCount: document.pages.length,
            rightBinding: _rightBinding,
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Создать буклет')),
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
                          onPressed:
                              _isOpening || _isSaving ? null : _pickSource,
                          icon: _isOpening
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
                    'Параметры буклета',
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
                                    _update(() => _paper = value);
                                  }
                                },
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('Переплёт слева'),
                              icon: Icon(Icons.menu_book_outlined),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text('Переплёт справа'),
                              icon: Icon(Icons.import_contacts_outlined),
                            ),
                          ],
                          selected: {_rightBinding},
                          onSelectionChanged: _isSaving
                              ? null
                              : (selection) => _update(
                                    () => _rightBinding = selection.first,
                                  ),
                        ),
                      ),
                      SizedBox(
                        width: 145,
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
                          onChanged: (_) => _update(() {}),
                        ),
                      ),
                      SizedBox(
                        width: 175,
                        child: TextField(
                          controller: _gutterController,
                          enabled: !_isSaving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Центральный отступ, мм',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => _update(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Лист будет альбомным. Страницы размещаются попарно, '
                    'с сохранением векторного содержимого.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Text(
                        'Предпросмотр раскладки',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Spacer(),
                      Text(
                        '${sheets.length} листов · ${sheets.length * 2} сторон',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (sheets.isNotEmpty)
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: Column(
                          children: [
                            _BookletSidePreview(
                              title: 'Лист 1 · лицевая сторона',
                              side: sheets.first.front,
                              paperSize: paper,
                              marginMm: margin,
                              gutterMm: gutter,
                            ),
                            const SizedBox(height: 14),
                            _BookletSidePreview(
                              title: 'Лист 1 · обратная сторона',
                              side: sheets.first.back,
                              paperSize: paper,
                              marginMm: margin,
                              gutterMm: gutter,
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Для печати выберите двусторонний режим. Каждый лист содержит '
                      'две стороны буклета; после печати листы складываются пополам '
                      'и вкладываются друг в друга. Если страниц не хватает до '
                      'кратности четырём, недостающие места останутся пустыми.',
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
                        onPressed:
                            _isSaving ? null : _chooseOutputDirectory,
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
                        label: Text(_isSaving ? 'Сохранение…' : 'Создать буклет'),
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
                      'Выберите PDF, чтобы подготовить его страницы к '
                      'двусторонней печати в виде буклета.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _BookletStatusPanel(message: _error!, isError: true),
                ],
                if (_savedPath != null) ...[
                  const SizedBox(height: 16),
                  _BookletStatusPanel(
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

class _BookletSidePreview extends StatelessWidget {
  const _BookletSidePreview({
    required this.title,
    required this.side,
    required this.paperSize,
    required this.marginMm,
    required this.gutterMm,
  });

  final String title;
  final PdfBookletSide side;
  final Size paperSize;
  final double marginMm;
  final double gutterMm;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final cells = PdfBookletGeometry.layout(
      paperWidthMm: paperSize.width,
      paperHeightMm: paperSize.height,
      marginMm: marginMm,
      gutterMm: gutterMm,
    );
    final pageIndices = [side.leftPageIndex, side.rightPageIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: paperSize.width / paperSize.height,
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.outline),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    for (var index = 0; index < cells.length; index++)
                      Positioned(
                        left: cells[index].left /
                            (paperSize.width *
                                PdfBookletGeometry.pointsPerMillimeter) *
                            constraints.maxWidth,
                        bottom: cells[index].bottom /
                            (paperSize.height *
                                PdfBookletGeometry.pointsPerMillimeter) *
                            constraints.maxHeight,
                        width: cells[index].width /
                            (paperSize.width *
                                PdfBookletGeometry.pointsPerMillimeter) *
                            constraints.maxWidth,
                        height: cells[index].height /
                            (paperSize.height *
                                PdfBookletGeometry.pointsPerMillimeter) *
                            constraints.maxHeight,
                        child: Container(
                          decoration: BoxDecoration(
                            color: colors.primaryContainer.withValues(
                              alpha: 0.42,
                            ),
                            border: Border.all(color: colors.primary),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            pageIndices[index] == null
                                ? 'Пусто'
                                : 'Стр. ${pageIndices[index]! + 1}',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ),
                    Positioned(
                      left: constraints.maxWidth / 2 - 0.5,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 1,
                        color: colors.outlineVariant,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _BookletStatusPanel extends StatelessWidget {
  const _BookletStatusPanel({
    required this.message,
    required this.isError,
  });

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

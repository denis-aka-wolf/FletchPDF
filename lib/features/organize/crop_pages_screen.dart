import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'services/pdf_crop_geometry.dart';
import 'services/pdf_crop_service.dart';

class CropPagesScreen extends StatefulWidget {
  const CropPagesScreen({super.key});

  @override
  State<CropPagesScreen> createState() => _CropPagesScreenState();
}

class _CropPagesScreenState extends State<CropPagesScreen> {
  final PdfCropService _service = const PdfCropService();
  final TextEditingController _nameController = TextEditingController();

  PdfDocument? _document;
  File? _sourceFile;
  String? _outputDirectory;
  int _currentPage = 0;
  NormalizedCropRect _selection = const NormalizedCropRect.full();
  Offset? _dragStart;
  bool _applyToAll = false;
  bool _isOpening = false;
  bool _isSaving = false;
  String? _error;
  String? _savedPath;

  @override
  void dispose() {
    _nameController.dispose();
    final document = _document;
    if (document != null) {
      unawaited(document.dispose());
    }
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
        dialogTitle: 'Выберите PDF для обрезки страниц',
      );
      if (!mounted || picked == null) return;

      final path = picked.path;
      if (path == null || path.isEmpty) {
        throw const FileSystemException('Не удалось получить путь к PDF.');
      }
      final file = File(path);
      if (!await file.exists()) {
        throw FileSystemException('Файл не найден.', path);
      }
      if (await file.length() == 0) {
        throw FileSystemException('PDF-файл пуст.', path);
      }

      opened = await PdfDocument.openFile(path);
      if (opened.pages.isEmpty) {
        throw StateError('В документе нет страниц.');
      }
      await _service.readVisibleBounds(opened);
      if (!mounted) return;

      final previous = _document;
      setState(() {
        _document = opened;
        _sourceFile = file;
        _currentPage = 0;
        _selection = const NormalizedCropRect.full();
        _dragStart = null;
        _applyToAll = false;
        _outputDirectory = p.dirname(path);
        _nameController.text =
            '${p.basenameWithoutExtension(path)}_cropped';
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

  void _changePage(int pageIndex) {
    final document = _document;
    if (document == null ||
        pageIndex < 0 ||
        pageIndex >= document.pages.length ||
        _isSaving) {
      return;
    }
    setState(() {
      _currentPage = pageIndex;
      _selection = const NormalizedCropRect.full();
      _dragStart = null;
      _savedPath = null;
      _error = null;
    });
  }

  void _updateSelection(Offset first, Offset second, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final x1 = (first.dx / size.width).clamp(0.0, 1.0);
    final y1 = (first.dy / size.height).clamp(0.0, 1.0);
    final x2 = (second.dx / size.width).clamp(0.0, 1.0);
    final y2 = (second.dy / size.height).clamp(0.0, 1.0);

    final left = x1 < x2 ? x1 : x2;
    final right = x1 > x2 ? x1 : x2;
    final top = y1 < y2 ? y1 : y2;
    final bottom = y1 > y2 ? y1 : y2;

    if (right - left < 0.015 || bottom - top < 0.015) return;
    setState(() {
      _selection = NormalizedCropRect(
        left: left,
        top: top,
        right: right,
        bottom: bottom,
      );
      _savedPath = null;
      _error = null;
    });
  }

  void _resetSelection() {
    setState(() {
      _selection = const NormalizedCropRect.full();
      _dragStart = null;
      _savedPath = null;
      _error = null;
    });
  }

  Future<void> _chooseOutputDirectory() async {
    if (_isSaving) return;
    try {
      final directoryUri = await FilePicker.pickDirectory(
        dialogTitle: 'Выберите папку для сохранения PDF',
        initialDirectory: _outputDirectory,
      );
      if (!mounted || directoryUri == null) return;
      setState(() {
        _outputDirectory = directoryUri.toFilePath();
        _savedPath = null;
        _error = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final document = _document;
    final source = _sourceFile;
    final directory = _outputDirectory;
    if (document == null || source == null) {
      setState(() => _error = 'Сначала выберите исходный PDF.');
      return;
    }
    if (directory == null || directory.trim().isEmpty) {
      setState(() => _error = 'Выберите папку для сохранения.');
      return;
    }

    try {
      _selection.validate();
    } on Object catch (error) {
      setState(() => _error = _readableError(error));
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
    final samePath = Platform.isWindows
        ? normalizedOutput.toLowerCase() == sourcePath.toLowerCase()
        : normalizedOutput == sourcePath;
    if (samePath) {
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

    final selections = <int, NormalizedCropRect>{
      if (_applyToAll)
        for (var index = 0; index < document.pages.length; index++)
          index: _selection
      else
        _currentPage: _selection,
    };

    setState(() {
      _isSaving = true;
      _error = null;
      _savedPath = null;
    });

    try {
      final result = await _service.cropAndSave(
        sourceDocument: document,
        selections: selections,
        outputPath: outputPath,
        overwriteExisting: overwrite,
      );
      await _service.readVisibleBounds(document);
      if (!mounted) return;
      setState(() {
        _selection = const NormalizedCropRect.full();
        _savedPath = result;
      });
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
    final document = _document;
    final source = _sourceFile;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Обрезка страниц PDF')),
      body: document == null || source == null
          ? _buildEmptyState(colors)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          p.basename(source.path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '${_currentPage + 1} / ${document.pages.length}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      IconButton(
                        tooltip: 'Предыдущая страница',
                        onPressed: _currentPage > 0 && !_isSaving
                            ? () => _changePage(_currentPage - 1)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: 'Следующая страница',
                        onPressed: _currentPage < document.pages.length - 1 &&
                                !_isSaving
                            ? () => _changePage(_currentPage + 1)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                      TextButton.icon(
                        onPressed: _isSaving ? null : _pickSource,
                        icon: const Icon(Icons.change_circle_outlined),
                        label: const Text('Другой файл'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      FilterChip(
                        label: const Text('Только текущую страницу'),
                        selected: !_applyToAll,
                        onSelected: _isSaving
                            ? null
                            : (_) => setState(() {
                                  _applyToAll = false;
                                  _savedPath = null;
                                }),
                      ),
                      FilterChip(
                        label: const Text('Все страницы'),
                        selected: _applyToAll,
                        onSelected: _isSaving
                            ? null
                            : (_) => setState(() {
                                  _applyToAll = true;
                                  _savedPath = null;
                                }),
                      ),
                      TextButton.icon(
                        onPressed: _isSaving ? null : _resetSelection,
                        icon: const Icon(Icons.crop_free, size: 18),
                        label: const Text('Сбросить область'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final page = document.pages[_currentPage];
                      final aspectRatio = page.width / page.height;
                      var width = constraints.maxWidth - 40;
                      var height = width / aspectRatio;
                      final maxHeight = constraints.maxHeight - 24;
                      if (height > maxHeight) {
                        height = maxHeight;
                        width = height * aspectRatio;
                      }

                      return Center(
                        child: SizedBox(
                          width: width,
                          height: height,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              PdfPageView(
                                document: document,
                                pageNumber: _currentPage + 1,
                                alignment: Alignment.center,
                              ),
                              Positioned.fill(
                                child: LayoutBuilder(
                                  builder: (context, overlayConstraints) {
                                    final size = Size(
                                      overlayConstraints.maxWidth,
                                      overlayConstraints.maxHeight,
                                    );
                                    return GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onPanStart: _isSaving
                                          ? null
                                          : (details) {
                                              _dragStart = details.localPosition;
                                              _updateSelection(
                                                details.localPosition,
                                                details.localPosition +
                                                    const Offset(0.02, 0.02),
                                                size,
                                              );
                                            },
                                      onPanUpdate: _isSaving || _dragStart == null
                                          ? null
                                          : (details) => _updateSelection(
                                                _dragStart!,
                                                details.localPosition,
                                                size,
                                              ),
                                      onPanEnd: (_) => _dragStart = null,
                                      child: CustomPaint(
                                        size: size,
                                        painter: _CropSelectionPainter(
                                          selection: _selection,
                                          overlayColor:
                                              Colors.black.withValues(alpha: 0.48),
                                          borderColor: colors.primary,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(
                    _applyToAll
                        ? 'Выделенная область будет применена ко всем страницам с учётом их ориентации.'
                        : 'Потяните мышью по странице, чтобы выделить область для обрезки.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: _CropMessage(message: _error!, isError: true),
                  ),
                if (_savedPath != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: _CropMessage(
                      message: 'Сохранено: $_savedPath',
                      isError: false,
                    ),
                  ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                  child: Column(
                    children: [
                      TextField(
                        controller: _nameController,
                        enabled: !_isSaving,
                        decoration: const InputDecoration(
                          labelText: 'Имя выходного файла',
                          suffixText: '.pdf',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
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
                                : const Icon(Icons.crop),
                            label: Text(
                              _isSaving ? 'Обрезка…' : 'Обрезать и сохранить',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(ColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.crop, size: 58, color: colors.primary),
            const SizedBox(height: 16),
            Text(
              'Обрезка страниц с предпросмотром',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Выделите нужную область мышью. Можно обрезать одну страницу или применить одинаковую область ко всему документу.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isOpening ? null : _pickSource,
              icon: _isOpening
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open),
              label: Text(_isOpening ? 'Открываем…' : 'Выбрать PDF'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _CropMessage(message: _error!, isError: true),
            ],
          ],
        ),
      ),
    );
  }
}

class _CropSelectionPainter extends CustomPainter {
  const _CropSelectionPainter({
    required this.selection,
    required this.overlayColor,
    required this.borderColor,
  });

  final NormalizedCropRect selection;
  final Color overlayColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final selected = Rect.fromLTRB(
      selection.left * size.width,
      selection.top * size.height,
      selection.right * size.width,
      selection.bottom * size.height,
    );

    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(selected);
    canvas.drawPath(outside, Paint()..color = overlayColor);
    canvas.drawRect(
      selected,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    const handleRadius = 4.0;
    final handlePaint = Paint()..color = borderColor;
    for (final point in [
      selected.topLeft,
      selected.topRight,
      selected.bottomLeft,
      selected.bottomRight,
    ]) {
      canvas.drawCircle(point, handleRadius, handlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CropSelectionPainter oldDelegate) {
    return oldDelegate.selection.left != selection.left ||
        oldDelegate.selection.top != selection.top ||
        oldDelegate.selection.right != selection.right ||
        oldDelegate.selection.bottom != selection.bottom ||
        oldDelegate.overlayColor != overlayColor ||
        oldDelegate.borderColor != borderColor;
  }
}

class _CropMessage extends StatelessWidget {
  const _CropMessage({required this.message, required this.isError});

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

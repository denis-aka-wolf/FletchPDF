import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'services/pdf_split_service.dart';

class SplitPdfScreen extends StatefulWidget {
  const SplitPdfScreen({super.key});

  @override
  State<SplitPdfScreen> createState() => _SplitPdfScreenState();
}

class _SplitPdfScreenState extends State<SplitPdfScreen> {
  final PdfSplitService _splitService = const PdfSplitService();
  final TextEditingController _rangesController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  File? _sourceFile;
  int? _pageCount;
  String? _outputDirectory;
  bool _isPicking = false;
  bool _isSplitting = false;
  String? _error;
  List<String> _createdFiles = const [];

  @override
  void dispose() {
    _rangesController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickSource() async {
    if (_isPicking || _isSplitting) return;

    setState(() {
      _isPicking = true;
      _error = null;
      _createdFiles = const [];
    });

    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        dialogTitle: 'Выберите PDF для разделения',
      );

      if (!mounted || picked == null) return;

      final path = picked.path;
      if (path == null || path.isEmpty) {
        throw const FileSystemException(
          'Операционная система не вернула путь к PDF-файлу.',
        );
      }

      final file = File(path);
      if (!await file.exists()) {
        throw FileSystemException('Файл не найден.', path);
      }
      if (await file.length() == 0) {
        throw FileSystemException('PDF-файл пуст.', path);
      }

      final document = await PdfDocument.openFile(path);
      late final int pageCount;
      try {
        pageCount = document.pages.length;
      } finally {
        await document.dispose();
      }

      if (pageCount < 2) {
        throw StateError(
          'В документе меньше двух страниц. Разделять его не требуется.',
        );
      }

      if (!mounted) return;

      setState(() {
        _sourceFile = file;
        _pageCount = pageCount;
        _outputDirectory = p.dirname(file.path);
        _nameController.text = p.basenameWithoutExtension(file.path);
        _rangesController.clear();
        _createdFiles = const [];
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = _readableError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  Future<void> _chooseOutputDirectory() async {
    if (_isSplitting) return;

    try {
      final directory = await FilePicker.getDirectoryPath(
        dialogTitle: 'Выберите папку для сохранения частей',
        initialDirectory: _outputDirectory,
      );

      if (!mounted || directory == null) return;

      setState(() {
        _outputDirectory = directory;
        _error = null;
        _createdFiles = const [];
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = _readableError(error));
      }
    }
  }

  Future<void> _split() async {
    if (_isSplitting) return;

    final source = _sourceFile;
    final pageCount = _pageCount;
    final outputDirectory = _outputDirectory;
    if (source == null || pageCount == null) {
      setState(() => _error = 'Сначала выберите исходный PDF-файл.');
      return;
    }
    if (outputDirectory == null || outputDirectory.trim().isEmpty) {
      setState(() => _error = 'Выберите папку для сохранения частей.');
      return;
    }

    final baseName = _nameController.text.trim();
    if (baseName.isEmpty ||
        p.basename(baseName) != baseName ||
        baseName.contains(RegExp(r'[<>:"/\\|?*]'))) {
      setState(() {
        _error = 'Укажите корректное имя файлов без недопустимых символов.';
      });
      return;
    }

    late final List<List<int>> groups;
    try {
      groups = PageRangeParser.parseGroups(
        _rangesController.text,
        pageCount: pageCount,
      );
    } on Object catch (error) {
      setState(() => _error = _readableError(error));
      return;
    }

    final outputPaths = [
      for (var index = 0; index < groups.length; index++)
        p.join(
          outputDirectory,
          '${baseName}_part_${(index + 1).toString().padLeft(3, '0')}.pdf',
        ),
    ];

    final existingPaths = <String>[];
    for (final path in outputPaths) {
      if (await File(path).exists()) existingPaths.add(path);
    }

    var overwrite = false;
    if (existingPaths.isNotEmpty) {
      if (!mounted) return;
      overwrite = await _confirmOverwrite(existingPaths);
      if (!overwrite || !mounted) return;
    }

    setState(() {
      _isSplitting = true;
      _error = null;
      _createdFiles = const [];
    });

    try {
      final created = await _splitService.split(
        inputPath: source.path,
        pageGroups: groups,
        outputPaths: outputPaths,
        overwriteExisting: overwrite,
      );

      if (!mounted) return;

      setState(() => _createdFiles = created);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Создано PDF-файлов: ${created.length}.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = _readableError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isSplitting = false);
      }
    }
  }

  Future<bool> _confirmOverwrite(List<String> paths) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Файлы уже существуют'),
        content: Text(
          'Будут заменены существующие файлы: ${paths.length}. Продолжить?',
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
    if (error is FileSystemException) {
      return error.message;
    }
    if (error is RangeError || error is FormatException) {
      return error.toString().replaceFirst('FormatException: ', '');
    }
    if (error is ArgumentError) {
      return error.message?.toString() ?? error.toString();
    }
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final source = _sourceFile;

    return Scaffold(
      appBar: AppBar(title: const Text('Разделить PDF')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Разделение документа на части',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Задайте диапазоны страниц. Каждая группа будет сохранена '
                  'в отдельный PDF в указанном порядке.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  onPressed: _isPicking || _isSplitting ? null : _pickSource,
                  icon: _isPicking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open),
                  label: Text(
                    _isPicking ? 'Открываем…' : 'Выбрать исходный PDF',
                  ),
                ),
                if (source != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.picture_as_pdf_outlined,
                          color: colors.primary,
                          size: 30,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.basename(source.path),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Страниц: $_pageCount',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Выбрать другой документ',
                          onPressed: _isSplitting ? null : _pickSource,
                          icon: const Icon(Icons.change_circle_outlined),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Группы страниц',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _rangesController,
                    enabled: !_isSplitting,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '1-3; 4-6; 7-10',
                      helperText:
                          'Разделяйте группы точкой с запятой. '
                          'Страницы внутри группы перечисляйте через запятую.',
                    ),
                    onChanged: (_) {
                      if (_createdFiles.isNotEmpty || _error != null) {
                        setState(() {
                          _createdFiles = const [];
                          _error = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Пример: 1-3; 4-6; 7, 9-10 создаст три PDF-файла. '
                    'Страницы должны быть указаны без повторений.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Сохранение',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nameController,
                    enabled: !_isSplitting,
                    decoration: const InputDecoration(
                      labelText: 'Основа имени файлов',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) {
                      if (_createdFiles.isNotEmpty) {
                        setState(() => _createdFiles = const []);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _outputDirectory ?? 'Папка не выбрана',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed:
                            _isSplitting ? null : _chooseOutputDirectory,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Папка'),
                      ),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _MessagePanel(message: _error!, isError: true),
                ],
                if (_createdFiles.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _MessagePanel(
                    message: 'Успешно создано файлов: ${_createdFiles.length}',
                    isError: false,
                  ),
                  const SizedBox(height: 8),
                  ..._createdFiles.map(
                    (path) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.picture_as_pdf_outlined),
                      title: Text(
                        p.basename(path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                if (source != null) ...[
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _isSplitting ? null : _split,
                      icon: _isSplitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.content_cut_rounded),
                      label: Text(
                        _isSplitting ? 'Разделение…' : 'Разделить PDF',
                      ),
                    ),
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

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
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

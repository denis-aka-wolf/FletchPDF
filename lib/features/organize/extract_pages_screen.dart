import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'services/pdf_extract_service.dart';

class ExtractPagesScreen extends StatefulWidget {
  const ExtractPagesScreen({super.key});

  @override
  State<ExtractPagesScreen> createState() => _ExtractPagesScreenState();
}

class _ExtractPagesScreenState extends State<ExtractPagesScreen> {
  final PdfExtractService _service = const PdfExtractService();
  final TextEditingController _pagesController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  File? _sourceFile;
  int? _pageCount;
  String? _outputDirectory;
  bool _isPicking = false;
  bool _isExtracting = false;
  String? _error;
  String? _createdFile;

  @override
  void dispose() {
    _pagesController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickSource() async {
    if (_isPicking || _isExtracting) return;
    setState(() {
      _isPicking = true;
      _error = null;
      _createdFile = null;
    });

    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        dialogTitle: 'Выберите PDF для извлечения страниц',
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

      final document = await PdfDocument.openFile(path);
      late final int count;
      try {
        count = document.pages.length;
      } finally {
        await document.dispose();
      }
      if (count < 1) {
        throw StateError('В документе нет страниц.');
      }
      if (!mounted) return;

      setState(() {
        _sourceFile = file;
        _pageCount = count;
        _outputDirectory = p.dirname(path);
        _nameController.text = '${p.basenameWithoutExtension(path)}_extracted';
        _pagesController.clear();
        _createdFile = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _chooseOutputDirectory() async {
    if (_isExtracting) return;
    try {
      final directoryUri = await FilePicker.pickDirectory(
        dialogTitle: 'Выберите папку для сохранения PDF',
        initialDirectory: _outputDirectory,
      );
      if (!mounted || directoryUri == null) return;
      setState(() {
        _outputDirectory = directoryUri.toFilePath();
        _error = null;
        _createdFile = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    }
  }

  Future<void> _extract() async {
    if (_isExtracting) return;
    final source = _sourceFile;
    final count = _pageCount;
    final directory = _outputDirectory;
    if (source == null || count == null) {
      setState(() => _error = 'Сначала выберите исходный PDF-файл.');
      return;
    }
    if (directory == null || directory.trim().isEmpty) {
      setState(() => _error = 'Выберите папку для сохранения результата.');
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty ||
        p.basename(name) != name ||
        name.contains(RegExp(r'[<>:"/\\|?*]'))) {
      setState(() => _error = 'Укажите корректное имя выходного файла.');
      return;
    }

    late final List<int> pages;
    try {
      pages = PageSelectionParser.parse(
        _pagesController.text,
        pageCount: count,
      );
    } on Object catch (error) {
      setState(() => _error = _readableError(error));
      return;
    }

    final outputPath = p.join(directory, '$name.pdf');
    var overwrite = false;
    if (await File(outputPath).exists()) {
      if (!mounted) return;
      overwrite = await _confirmOverwrite(outputPath);
      if (!overwrite || !mounted) return;
    }

    setState(() {
      _isExtracting = true;
      _error = null;
      _createdFile = null;
    });

    try {
      final result = await _service.extract(
        inputPath: source.path,
        outputPath: outputPath,
        pageNumbers: pages,
        overwriteExisting: overwrite,
      );
      if (!mounted) return;
      setState(() => _createdFile = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Создан PDF: ${p.basename(result)}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    } finally {
      if (mounted) setState(() => _isExtracting = false);
    }
  }

  Future<bool> _confirmOverwrite(String path) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Файл уже существует'),
        content: Text('Файл "${p.basename(path)}" будет заменён. Продолжить?'),
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
    if (error is FormatException || error is RangeError) {
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
      appBar: AppBar(title: const Text('Извлечь страницы')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Извлечение страниц в один PDF',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Выберите страницы исходного документа. Они попадут в новый PDF в указанном порядке.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  onPressed: _isPicking || _isExtracting ? null : _pickSource,
                  icon: _isPicking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open),
                  label: Text(_isPicking ? 'Открываем…' : 'Выбрать исходный PDF'),
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
                        Icon(Icons.picture_as_pdf_outlined,
                            color: colors.primary, size: 30),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.basename(source.path),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text('Страниц: $_pageCount'),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Выбрать другой документ',
                          onPressed: _isExtracting ? null : _pickSource,
                          icon: const Icon(Icons.change_circle_outlined),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Страницы для извлечения',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _pagesController,
                    enabled: !_isExtracting,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '1-3, 5, 8-10',
                      helperText: 'Укажите номера и диапазоны через запятую.',
                    ),
                    onChanged: (_) {
                      if (_createdFile != null || _error != null) {
                        setState(() {
                          _createdFile = null;
                          _error = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Порядок сохраняется. Например, "5, 1-3" создаст документ со страницами 5, 1, 2, 3.',
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
                    enabled: !_isExtracting,
                    decoration: const InputDecoration(
                      labelText: 'Имя выходного файла',
                      suffixText: '.pdf',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) {
                      if (_createdFile != null) {
                        setState(() => _createdFile = null);
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
                        onPressed: _isExtracting ? null : _chooseOutputDirectory,
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
                if (_createdFile != null) ...[
                  const SizedBox(height: 16),
                  _MessagePanel(
                    message: 'PDF успешно создан: ${p.basename(_createdFile!)}\n$_createdFile',
                    isError: false,
                  ),
                ],
                if (source != null) ...[
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _isExtracting ? null : _extract,
                      icon: _isExtracting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.file_download_outlined),
                      label: Text(
                        _isExtracting ? 'Извлечение…' : 'Извлечь страницы',
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
  const _MessagePanel({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = isError ? colors.errorContainer : colors.primaryContainer;
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

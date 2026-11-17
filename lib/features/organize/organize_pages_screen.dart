import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'services/pdf_page_organizer_service.dart';

class OrganizePagesScreen extends StatefulWidget {
  const OrganizePagesScreen({super.key});

  @override
  State<OrganizePagesScreen> createState() => _OrganizePagesScreenState();
}

class _OrganizePagesScreenState extends State<OrganizePagesScreen> {
  final PdfPageOrganizerService _service =
      const PdfPageOrganizerService();
  final TextEditingController _nameController = TextEditingController();
  final List<List<_OrganizedPage>> _history = [];

  PdfDocument? _document;
  File? _sourceFile;
  List<_OrganizedPage> _pages = [];
  String? _outputDirectory;
  bool _isOpening = false;
  bool _isSaving = false;
  String? _error;
  String? _savedPath;

  @override
  void dispose() {
    _nameController.dispose();
    _document?.dispose();
    super.dispose();
  }

  Future<void> _pickSource() async {
    if (_isOpening || _isSaving) return;
    setState(() {
      _isOpening = true;
      _error = null;
      _savedPath = null;
    });

    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        dialogTitle: 'Выберите PDF для организации страниц',
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

      final opened = await PdfDocument.openFile(path);
      final openedPages = opened.pages
          .map((page) => _OrganizedPage(page: page))
          .toList();
      if (openedPages.isEmpty) {
        await opened.dispose();
        throw StateError('В документе нет страниц.');
      }
      if (!mounted) {
        await opened.dispose();
        return;
      }

      final previous = _document;
      setState(() {
        _document = opened;
        _sourceFile = file;
        _pages = openedPages;
        _outputDirectory = p.dirname(path);
        _nameController.text =
            '${p.basenameWithoutExtension(path)}_organized';
        _history.clear();
        _savedPath = null;
        _error = null;
      });
      if (previous != null) await previous.dispose();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    } finally {
      if (mounted) setState(() => _isOpening = false);
    }
  }

  void _remember() {
    _history.add(List<_OrganizedPage>.of(_pages));
    if (_history.length > 50) _history.removeAt(0);
  }

  void _reorder(int oldIndex, int newIndex) {
    if (_isSaving) return;
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= _pages.length ||
        newIndex < 0 ||
        newIndex >= _pages.length) {
      return;
    }
    _remember();
    final updated = List<_OrganizedPage>.of(_pages);
    final page = updated.removeAt(oldIndex);
    updated.insert(newIndex, page);
    _document!.pages = updated.map((entry) => entry.page).toList();
    setState(() {
      _pages = updated;
      _savedPath = null;
      _error = null;
    });
  }

  void _removePage(int index) {
    if (_isSaving || _pages.length <= 1) return;
    _remember();
    final updated = List<_OrganizedPage>.of(_pages)..removeAt(index);
    _document!.pages = updated;
    setState(() {
      _pages = updated;
      _savedPath = null;
      _error = null;
    });
  }

  void _duplicatePage(int index) {
    if (_isSaving) return;
    _remember();
    final updated = List<_OrganizedPage>.of(_pages);
    updated.insert(index + 1, _OrganizedPage(page: _pages[index].page));
    _document!.pages = updated.map((entry) => entry.page).toList();
    setState(() {
      _pages = updated;
      _savedPath = null;
      _error = null;
    });
  }

  void _rotatePage(int index) {
    if (_isSaving) return;
    _remember();
    final updated = List<_OrganizedPage>.of(_pages);
    updated[index] = updated[index].withPage(updated[index].page.rotatedCW90());
    _document!.pages = updated.map((entry) => entry.page).toList();
    setState(() {
      _pages = updated;
      _savedPath = null;
      _error = null;
    });
  }

  void _undo() {
    if (_history.isEmpty || _isSaving) return;
    final restored = _history.removeLast();
    _document!.pages = restored.map((entry) => entry.page).toList();
    setState(() {
      _pages = restored;
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
    final directory = _outputDirectory;
    if (document == null || _sourceFile == null) {
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
    final sourcePath = p.normalize(p.absolute(_sourceFile!.path));
    if ((Platform.isWindows
            ? outputPath.toLowerCase() == sourcePath.toLowerCase()
            : outputPath == sourcePath)) {
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

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final result = await _service.save(
        sourceDocument: document,
        pages: _pages.map((entry) => entry.page).toList(),
        outputPath: outputPath,
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Организация страниц'),
        actions: [
          IconButton(
            tooltip: 'Отменить последнее действие',
            onPressed: _history.isEmpty || _isSaving ? null : _undo,
            icon: const Icon(Icons.undo),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: source == null
              ? Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.auto_awesome_mosaic_outlined,
                          size: 56, color: colors.primary),
                      const SizedBox(height: 16),
                      Text(
                        'Изменяйте структуру PDF визуально',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Перетаскивайте страницы, удаляйте, дублируйте и поворачивайте их. Исходный документ не изменяется.',
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
                        label: Text(
                            _isOpening ? 'Открываем…' : 'Выбрать PDF'),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        _StatusPanel(message: _error!, isError: true),
                      ],
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
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
                            '${_pages.length} стр.',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(width: 8),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Перетаскивайте карточки для изменения порядка',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _history.isEmpty || _isSaving
                                ? null
                                : _undo,
                            icon: const Icon(Icons.undo, size: 18),
                            label: const Text('Отменить'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                        itemCount: _pages.length,
                        buildDefaultDragHandles: false,
                        onReorderItem: _reorder,
                        itemBuilder: (context, index) {
                          final page = _pages[index].page;
                          return Card(
                            key: ValueKey(_pages[index].key),
                            margin: const EdgeInsets.only(bottom: 10),
                            clipBehavior: Clip.antiAlias,
                            child: SizedBox(
                              height: 184,
                              child: Row(
                                children: [
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: Container(
                                      width: 42,
                                      height: double.infinity,
                                      color: colors.surfaceContainerHighest,
                                      child: const Icon(Icons.drag_indicator),
                                    ),
                                  ),
                                  Container(
                                    width: 42,
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8),
                                      child: PdfPageView(
                                        document: _document!,
                                        pageNumber: index + 1,
                                        alignment: Alignment.center,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        tooltip: 'Повернуть на 90°',
                                        onPressed: _isSaving
                                            ? null
                                            : () => _rotatePage(index),
                                        icon: const Icon(Icons.rotate_right),
                                      ),
                                      IconButton(
                                        tooltip: 'Дублировать страницу',
                                        onPressed: _isSaving
                                            ? null
                                            : () => _duplicatePage(index),
                                        icon: const Icon(Icons.copy_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'Удалить страницу',
                                        onPressed: _isSaving || _pages.length <= 1
                                            ? null
                                            : () => _removePage(index),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 8),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        child: _StatusPanel(message: _error!, isError: true),
                      ),
                    if (_savedPath != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        child: _StatusPanel(
                          message: 'Сохранено: $_savedPath',
                          isError: false,
                        ),
                      ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                onPressed: _isSaving
                                    ? null
                                    : _chooseOutputDirectory,
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
                                label: Text(
                                    _isSaving ? 'Сохранение…' : 'Сохранить PDF'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _OrganizedPage {
  _OrganizedPage({required this.page}) : key = Object();

  _OrganizedPage._({required this.key, required this.page});

  final Object key;
  final PdfPage page;

  _OrganizedPage withPage(PdfPage updatedPage) {
    return _OrganizedPage._(key: key, page: updatedPage);
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.message, required this.isError});

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

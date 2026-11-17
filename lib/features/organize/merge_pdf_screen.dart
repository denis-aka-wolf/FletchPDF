import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'services/pdf_merge_service.dart';

class MergePdfScreen extends StatefulWidget {
  const MergePdfScreen({super.key});

  @override
  State<MergePdfScreen> createState() => _MergePdfScreenState();
}

class _MergePdfScreenState extends State<MergePdfScreen> {
  final PdfMergeService _mergeService = const PdfMergeService();
  final TextEditingController _fileNameController =
      TextEditingController(text: 'merged.pdf');

  final List<File> _files = [];

  String? _outputDirectory;
  bool _isPicking = false;
  bool _isMerging = false;
  String? _error;
  String? _successPath;

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }

  Future<void> _addFiles() async {
    if (_isPicking || _isMerging) return;

    setState(() {
      _isPicking = true;
      _error = null;
    });

    try {
      final selected = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        dialogTitle: 'Выберите PDF-файлы для объединения',
      );

      if (!mounted) return;

      if (selected.isNotEmpty) {
        final knownPaths = {
          for (final file in _files)
            _pathKey(file.path),
        };

        final added = <File>[];
        for (final picked in selected) {
          final path = picked.path;
          if (path == null || path.isEmpty) continue;

          final file = File(path);
          final key = _pathKey(file.path);
          if (knownPaths.add(key) && await file.exists()) {
            added.add(file);
          }
        }

        if (added.isNotEmpty) {
          setState(() {
            _files.addAll(added);
            _successPath = null;
            _outputDirectory ??= p.dirname(added.first.path);
          });
        }
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  Future<void> _chooseOutputDirectory() async {
    if (_isMerging) return;

    try {
      final directoryUri = await FilePicker.pickDirectory(
        dialogTitle: 'Выберите папку для сохранения результата',
        initialDirectory: _outputDirectory,
      );

      if (!mounted || directoryUri == null) return;

      setState(() {
        _outputDirectory = directoryUri.toFilePath();
        _error = null;
        _successPath = null;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  void _removeFile(int index) {
    setState(() {
      _files.removeAt(index);
      _successPath = null;
    });
  }

  void _reorderFiles(int oldIndex, int newIndex) {
    setState(() {
      final file = _files.removeAt(oldIndex);
      _files.insert(newIndex, file);
      _successPath = null;
    });
  }

  Future<void> _merge() async {
    if (_isMerging) return;

    if (_files.length < 2) {
      setState(() {
        _error = 'Добавьте не менее двух PDF-файлов.';
        _successPath = null;
      });
      return;
    }

    final directory = _outputDirectory;
    if (directory == null || directory.trim().isEmpty) {
      setState(() => _error = 'Выберите папку для сохранения результата.');
      return;
    }

    final fileName = _fileNameController.text.trim();
    if (fileName.isEmpty) {
      setState(() => _error = 'Укажите имя выходного PDF-файла.');
      return;
    }
    if (p.basename(fileName) != fileName ||
        fileName.contains(RegExp(r'[<>:"/\\|?*]'))) {
      setState(() {
        _error = 'Имя файла содержит недопустимые символы или путь.';
      });
      return;
    }

    final normalizedName = fileName.toLowerCase().endsWith('.pdf')
        ? fileName
        : '$fileName.pdf';
    final outputPath = p.join(directory, normalizedName);
    final outputFile = File(outputPath);

    var overwrite = false;
    if (await outputFile.exists()) {
      if (!mounted) return;
      overwrite = await _confirmOverwrite(outputPath);
      if (!overwrite || !mounted) return;
    }

    setState(() {
      _isMerging = true;
      _error = null;
      _successPath = null;
    });

    try {
      await _mergeService.merge(
        inputPaths: _files.map((file) => file.path).toList(),
        outputPath: outputPath,
        overwriteExisting: overwrite,
      );

      if (!mounted) return;

      setState(() => _successPath = outputPath);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF-файлы успешно объединены.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isMerging = false);
      }
    }
  }

  Future<bool> _confirmOverwrite(String outputPath) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Файл уже существует'),
        content: Text(
          'Файл "$outputPath" уже существует. Заменить его?',
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

  String _pathKey(String path) {
    final normalized = p.normalize(p.absolute(path));
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  String _displayName(File file) {
    return p.basename(file.path);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Объединить PDF'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Соберите несколько документов в один PDF',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Добавьте файлы и перетащите их в нужном порядке. '
                  'Страницы будут объединены в указанной последовательности.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _isPicking || _isMerging ? null : _addFiles,
                      icon: _isPicking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.add),
                      label: const Text('Добавить PDF'),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Файлов: ${_files.length}',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: _files.isEmpty
                        ? _buildEmptyState(context)
                        : ReorderableListView.builder(
                            padding: const EdgeInsets.all(10),
                            itemCount: _files.length,
                            buildDefaultDragHandles: !_isMerging,
                            onReorderItem: _reorderFiles,
                            itemBuilder: (context, index) {
                              final file = _files[index];
                              return Card(
                                key: ValueKey(_pathKey(file.path)),
                                margin: const EdgeInsets.symmetric(vertical: 5),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: colors.primaryContainer,
                                    foregroundColor: colors.onPrimaryContainer,
                                    child: Text('${index + 1}'),
                                  ),
                                  title: Text(
                                    _displayName(file),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    file.path,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!_isMerging)
                                        IconButton(
                                          tooltip: 'Удалить из списка',
                                          onPressed: () => _removeFile(index),
                                          icon: const Icon(Icons.close),
                                        ),
                                      if (!_isMerging)
                                        const Icon(Icons.drag_handle),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 18),
                _buildOutputSettings(context),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _MessagePanel(
                    message: _error!,
                    isError: true,
                  ),
                ],
                if (_successPath != null) ...[
                  const SizedBox(height: 12),
                  _MessagePanel(
                    message: 'Создан файл: $_successPath',
                    isError: false,
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _isMerging ? null : _merge,
                    icon: _isMerging
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.call_merge_rounded),
                    label: Text(
                      _isMerging ? 'Объединение…' : 'Объединить файлы',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.picture_as_pdf_outlined,
              size: 44,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            const Text(
              'Пока нет PDF-файлов',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            Text(
              'Нажмите «Добавить PDF», чтобы выбрать документы.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutputSettings(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Сохранение результата',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _fileNameController,
                enabled: !_isMerging,
                decoration: const InputDecoration(
                  labelText: 'Имя файла',
                  hintText: 'merged.pdf',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) {
                  if (_successPath != null) {
                    setState(() => _successPath = null);
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _isMerging ? null : _chooseOutputDirectory,
              icon: const Icon(Icons.folder_open),
              label: const Text('Папка'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _outputDirectory ?? 'Папка не выбрана',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
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
      child: Text(
        message,
        style: TextStyle(color: foreground),
      ),
    );
  }
}

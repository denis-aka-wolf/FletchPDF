import 'dart:io';

import 'package:flutter/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/files/pdf_file_service.dart';
import '../organize/merge_pdf_screen.dart';
import '../organize/split_pdf_screen.dart';
import '../organize/extract_pages_screen.dart';
import '../organize/organize_pages_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PdfFileService _fileService = PdfFileService();

  File? _activeFile;
  bool _isPicking = false;
  String? _error;

  Future<void> _openPdf() async {
    if (_isPicking) return;

    setState(() {
      _isPicking = true;
      _error = null;
    });

    try {
      final file = await _fileService.pickPdf();
      if (!mounted) return;

      if (file != null) {
        setState(() => _activeFile = file);
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  void _closeDocument() {
    setState(() {
      _activeFile = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final file = _activeFile;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 24,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.picture_as_pdf_rounded,
                color: Colors.white,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'FletchPDF',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 12),
            const _LocalBadge(),
          ],
        ),
        actions: [
          if (file != null)
            IconButton(
              tooltip: 'Закрыть документ',
              onPressed: _closeDocument,
              icon: const Icon(Icons.close),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: file == null ? _buildHome(context) : _buildViewer(context, file),
    );
  }

  Widget _buildHome(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 42, 28, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Рабочее пространство PDF',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                'Все документы обрабатываются локально на этом устройстве.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 30),
              _OpenDocumentCard(
                isLoading: _isPicking,
                onPressed: _openPdf,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                _ErrorPanel(message: _error!),
              ],
              const SizedBox(height: 38),
              Text(
                'Инструменты',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _ToolTile(
                    icon: Icons.call_merge_rounded,
                    title: 'Объединить PDF',
                    subtitle: 'Собрать документы в один файл',
                    status: 'Готово',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const MergePdfScreen(),
                        ),
                      );
                    },
                  ),
                  _ToolTile(
                    icon: Icons.content_cut_rounded,
                    title: 'Разделить PDF',
                    subtitle: 'Разбить документ на части',
                    status: 'Готово',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SplitPdfScreen(),
                        ),
                      );
                    },
                  ),
                  _ToolTile(
                    icon: Icons.file_download_outlined,
                    title: 'Извлечь страницы',
                    subtitle: 'Собрать выбранные страницы в один PDF',
                    status: 'Готово',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ExtractPagesScreen(),
                        ),
                      );
                    },
                  ),
                  _ToolTile(
                    icon: Icons.auto_awesome_mosaic_outlined,
                    title: 'Организация страниц',
                    subtitle: 'Порядок, удаление, копирование и поворот',
                    status: 'Готово',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const OrganizePagesScreen(),
                        ),
                      );
                    },
                  ),
                  _ToolTile(
                    icon: Icons.image_outlined,
                    title: 'PDF в изображения',
                    subtitle: 'Экспорт страниц в PNG или JPEG',
                    status: 'В разработке',
                  ),
                  _ToolTile(
                    icon: Icons.document_scanner_outlined,
                    title: 'OCR',
                    subtitle: 'Распознавание текста в сканах',
                    status: 'В разработке',
                  ),
                  _ToolTile(
                    icon: Icons.lock_outline_rounded,
                    title: 'Защита PDF',
                    subtitle: 'Пароли и разрешения документа',
                    status: 'В разработке',
                  ),
                  _ToolTile(
                    icon: Icons.edit_document,
                    title: 'Редактирование',
                    subtitle: 'Аннотации, текст и изображения',
                    status: 'В разработке',
                  ),
                ],
              ),
              const SizedBox(height: 34),
              const _PrivacyNote(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewer(BuildContext context, File file) {
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.picture_as_pdf_outlined, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    file.uri.pathSegments.isEmpty
                        ? file.path
                        : file.uri.pathSegments.last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  'Локальный файл',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: PdfViewer.file(
            file.path,
            params: const PdfViewerParams(
              textSelectionParams: PdfTextSelectionParams(enabled: true),
            ),
          ),
        ),
      ],
    );
  }
}

class _LocalBadge extends StatelessWidget {
  const _LocalBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE6F4EA),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          'LOCAL FIRST',
          style: TextStyle(
            color: Color(0xFF237A43),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
          ),
        ),
      ),
    );
  }
}

class _OpenDocumentCard extends StatelessWidget {
  const _OpenDocumentCard({
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.picture_as_pdf_rounded,
              size: 34,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Откройте PDF-документ',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Выберите файл на компьютере, чтобы начать работу.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: isLoading ? null : onPressed,
            icon: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_open_rounded),
            label: Text(isLoading ? 'Открываем…' : 'Выбрать PDF'),
          ),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      width: 320,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: colors.onSecondaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        status,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.tertiary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.shield_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'FletchPDF работает локально. Документы не отправляются на удалённый сервер.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

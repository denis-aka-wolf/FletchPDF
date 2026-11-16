import 'dart:io';

import 'package:file_picker/file_picker.dart';

class PdfFileService {
  Future<File?> pickPdf() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );

    if (picked == null) {
      return null;
    }

    final path = picked.path;
    if (path == null || path.isEmpty) {
      throw const FileSystemException(
        'Операционная система не вернула путь к выбранному PDF-файлу.',
      );
    }

    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Файл не найден.', path);
    }

    final length = await file.length();
    if (length == 0) {
      throw FileSystemException('PDF-файл пуст.', path);
    }

    return file;
  }
}

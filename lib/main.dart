import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app/fletch_pdf_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  runApp(const FletchPdfApp());
}

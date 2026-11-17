import 'package:material_ui/material_ui.dart';

import '../features/home/home_screen.dart';

class FletchPdfApp extends StatelessWidget {
  const FletchPdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF6750A4);

    return MaterialApp(
      title: 'FletchPDF',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F7FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7F7FA),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE7E5EC)),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

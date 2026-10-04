import 'package:flutter/material.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PokeLensApp());
}

class PokeLensApp extends StatelessWidget {
  const PokeLensApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PokéLens · Deine Karten. Ihr wahrer Wert.',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: const AppShell(),
  );
}

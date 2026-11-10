import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/server.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Server.I.init();
  runApp(const CouchSpaceApp());
}

class CouchSpaceApp extends StatelessWidget {
  const CouchSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CouchSpace',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeScreen(),
    );
  }
}

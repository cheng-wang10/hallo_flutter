import 'package:flutter/material.dart';
import 'screens/capture_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HumanCaptureApp());
}

class HumanCaptureApp extends StatelessWidget {
  const HumanCaptureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '人体采集系统',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const CaptureScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
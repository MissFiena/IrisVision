import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'views/live_detection_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // kunci portrait supaya kotak detection sentiasa sejajar
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const IrisVisionApp());
}

class IrisVisionApp extends StatelessWidget {
  const IrisVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IrisVision',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const LiveDetectionView(),
    );
  }
}
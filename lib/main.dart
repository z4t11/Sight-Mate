import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait — better for one-hand use
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Load .env (MOCK_MODE, GEMINI_API_KEY)
  await dotenv.load(fileName: '.env');

  runApp(const SightMateApp());
}

class SightMateApp extends StatelessWidget {
  const SightMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sight Mate',
      debugShowCheckedModeBanner: false,
      // High-contrast dark theme; large fonts for low-vision users.
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const HomeScreen(),
    );
  }
}

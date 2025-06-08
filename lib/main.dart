import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'theme_manager.dart'; // Import ThemeNotifier
import 'auth/login_page.dart'; // Import LoginPage

/// The main entry point of the Flutter application.
/// Initializes the theme and runs the MyApp widget.
void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensure Flutter is initialized
  final themeNotifier = ThemeNotifier();
  await themeNotifier.initTheme(); // Load the saved theme before starting

  runApp(
    ChangeNotifierProvider( // Allows access to ThemeNotifier throughout the widget tree
      create: (_) => themeNotifier,
      child: const MyApp(),
    ),
  );
}

/// MyApp is our top-level widget that defines the Material Design structure
/// and configures the app's themes (Light and Dark).
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Listen for changes in ThemeNotifier
    final themeNotifier = Provider.of<ThemeNotifier>(context);

    return MaterialApp(
      title: 'Stand App',
      // Define the Light Theme
      theme: ThemeData(
        primarySwatch: Colors.blue,
        primaryColor: Colors.blue, // Primary color for app bar etc.
        brightness: Brightness.light,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme.apply(
          bodyColor: Colors.grey[800], // Darker text for light mode
          displayColor: Colors.grey[800],
        )),
        scaffoldBackgroundColor: Colors.grey[100], // Background color like bg-gray-100
        cardColor: Colors.white, // Card background like bg-white
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blueAccent, // Match AppBar color
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.grey),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
          ),
          labelStyle: GoogleFonts.inter(color: Colors.grey[700]),
          hintStyle: GoogleFonts.inter(color: Colors.grey[500]),
          contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
            textStyle: GoogleFonts.inter(fontSize: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 5,
          ),
        ),
      ),
      // Define the Dark Theme
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        primaryColor: Colors.blueGrey[900], // Darker primary color for dark mode
        brightness: Brightness.dark,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme.apply(
          bodyColor: const Color(0xFFE2E8F0), // Lighter text like #e2e8f0
          displayColor: const Color(0xFFE2E8F0),
        )),
        scaffoldBackgroundColor: Colors.black, // OLED-optimized black as on the website
        cardColor: Colors.black, // Card background also black
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.blueGrey[900], // Darker AppBar background
          foregroundColor: const Color(0xFFE2E8F0),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF555555)), // Darker border
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.blue[300]!, width: 2),
          ),
          fillColor: const Color(0xFF1C1C1C), // Background color like #1c1c1c
          filled: true,
          labelStyle: GoogleFonts.inter(color: const Color(0xFFA0AEC0)), // Lighter label
          hintStyle: GoogleFonts.inter(color: Colors.grey),
          contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[700], // Darker blue tone for buttons
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
            textStyle: GoogleFonts.inter(fontSize: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 5,
          ),
        ),
      ),
      themeMode: themeNotifier.themeMode, // Use ThemeMode from the Notifier
      home: const LoginPage(),
    );
  }
}

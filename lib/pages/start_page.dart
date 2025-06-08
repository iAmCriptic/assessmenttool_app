import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The 'Start' page, displayed as the first tab in the bottom navigation.
class StartPage extends StatelessWidget {
  final String serverAddress;
  const StartPage({super.key, required this.serverAddress});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Willkommen auf der Startseite!',
            style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Verbunden mit: $serverAddress',
            style: GoogleFonts.inter(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            'Hier könnten Dashboard-Informationen angezeigt werden.',
            style: GoogleFonts.inter(fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

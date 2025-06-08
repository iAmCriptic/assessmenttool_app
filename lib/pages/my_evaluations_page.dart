import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MyEvaluationsPage extends StatelessWidget {
  final String serverAddress;
  const MyEvaluationsPage({super.key, required this.serverAddress});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Meine Bewertungen',
          style: GoogleFonts.inter(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Dies ist die Seite "Meine Bewertungen".',
                style: GoogleFonts.inter(fontSize: 20),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Verbunden mit Server: $serverAddress',
                style: GoogleFonts.inter(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

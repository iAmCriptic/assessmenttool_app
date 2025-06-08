import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../theme_manager.dart'; // Import ThemeNotifier

/// Dummy AdminSetupPage.
/// This page is displayed if the Flask backend requires an initial admin setup.
class AdminSetupPage extends StatelessWidget {
  final String serverAddress;
  const AdminSetupPage({super.key, required this.serverAddress});

  @override
  Widget build(BuildContext context) {
    // Access ThemeNotifier
    final themeNotifier = Provider.of<ThemeNotifier>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Setup'),
        // AppBar colors are now managed by ThemeData
        actions: [
          IconButton(
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            onPressed: () {
              themeNotifier.toggleTheme();
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Admin-Setup erforderlich. Bitte ändere dein Standardpasswort!',
                style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Text(
                'Verbunden mit: $serverAddress',
                style: GoogleFonts.inter(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              // TODO: Here the form fields for new password and display name
              Text(
                'Formular zum Ändern des Admin-Passworts und Anzeigenamens kommt hierher.',
                style: GoogleFonts.inter(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

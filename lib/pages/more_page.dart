import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../auth/login_page.dart'; // Import LoginPage for navigation
// Import AdminSetupPage if needed
import 'package:provider/provider.dart';
import '../theme_manager.dart'; // Import ThemeNotifier

/// The 'More' page, containing additional options like logout and theme toggle.
class MorePage extends StatelessWidget {
  final String serverAddress;
  const MorePage({super.key, required this.serverAddress});

  @override
  Widget build(BuildContext context) {
    // Access ThemeNotifier
    final themeNotifier = Provider.of<ThemeNotifier>(context, listen: false);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Mehr Optionen',
            style: TextStyle(fontSize: 24),
          ),
          const SizedBox(height: 20),
          // Theme Toggle Button
          ElevatedButton.icon(
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode // Sun icon for Dark Mode
                  : Icons.dark_mode, // Moon icon for Light Mode
            ),
            label: Text(
              Theme.of(context).brightness == Brightness.dark
                  ? 'Light Mode'
                  : 'Dark Mode',
            ),
            onPressed: () {
              themeNotifier.toggleTheme(); // Toggle theme
            },
          ),
          const SizedBox(height: 20),
          // Logout button in 'Mehr' tab
          ElevatedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('Abmelden'),
            onPressed: () async {
              // Clear saved credentials on logout by calling a static method on LoginPage.
              await LoginPage.clearSavedCredentials();

              final Uri logoutUrl = Uri.parse('$serverAddress/api/logout');
              try {
                final response = await http.get(logoutUrl);
                if (response.statusCode == 200) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Erfolgreich abgemeldet.'),
                      behavior: SnackBarBehavior.floating,
                      margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10.0, left: 16.0, right: 16.0), // Positions it at the top
                      duration: const Duration(seconds: 2),
                    ),
                  );
                  // After logout, navigate back to the LoginPage
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Fehler beim Abmelden. Status: ${response.statusCode}'),
                      behavior: SnackBarBehavior.floating,
                      margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10.0, left: 16.0, right: 16.0), // Positions it at the top
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Verbindungsfehler beim Abmelden: $e'),
                    behavior: SnackBarBehavior.floating,
                    margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10.0, left: 16.0, right: 16.0), // Positions it at the top
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

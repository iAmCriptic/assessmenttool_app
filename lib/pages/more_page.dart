import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../auth/login_page.dart'; // Import LoginPage for navigation
import '../auth/admin_setup_page.dart'; // Import AdminSetupPage if needed
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
              // Clear saved credentials on logout by calling a static method or a method on LoginPage.
              // Since _clearCredentials is part of LoginPageState, we need a way to trigger it.
              // A common and robust way is to make LoginPage responsible for clearing its own credentials,
              // perhaps by passing a callback or using a GlobalKey, or by having LoginPage itself
              // expose a static method if it manages global state, or by passing it via Navigator arguments
              // or simply calling clear from SharedPreferences directly.
              // For simplicity and directness, we will modify LoginPage to expose the clear function statically.
              await LoginPage.clearSavedCredentials();


              final Uri logoutUrl = Uri.parse('$serverAddress/api/logout');
              try {
                final response = await http.get(logoutUrl);
                if (response.statusCode == 200) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Erfolgreich abgemeldet.')),
                  );
                  // After logout, navigate back to the LoginPage
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Fehler beim Abmelden. Status: ${response.statusCode}')),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Verbindungsfehler beim Abmelden: $e')),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

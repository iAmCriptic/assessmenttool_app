import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../theme_manager.dart'; // Import ThemeNotifier
import '../home/home_page.dart'; // Import HomePage
import 'admin_setup_page.dart'; // Import AdminSetupPage

/// LoginPage is a StatefulWidget that handles user login.
/// It includes fields for server address, username, and password.
/// It supports saving and loading credentials using SharedPreferences for persistent login.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  /// Static method to clear saved credentials from SharedPreferences.
  /// This allows calling it from other parts of the app (e.g., Logout button)
  /// without needing direct access to LoginPageState.
  static Future<void> clearSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('serverAddress');
    await prefs.remove('username');
    await prefs.remove('password');
  }

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _serverAddressController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false; // State to control the loading indicator
  String? _errorMessage; // For error messages

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  /// Loads saved login credentials (server address, username, password) from SharedPreferences.
  /// If credentials are found, it attempts an auto-login.
  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedServerAddress = prefs.getString('serverAddress');
    final String? savedUsername = prefs.getString('username');
    final String? savedPassword = prefs.getString('password');

    if (savedServerAddress != null && savedUsername != null && savedPassword != null) {
      _serverAddressController.text = savedServerAddress;
      _usernameController.text = savedUsername;
      _passwordController.text = savedPassword;

      // Attempt auto-login if credentials are found
      // We wrap this in a Future.microtask to allow the UI to build first,
      // preventing "setState() called during build" errors.
      Future.microtask(() => _login(isAutoLogin: true));
    } else {
      // Set a default IP if no saved credentials are found
      _serverAddressController.text = 'http://10.0.2.2:5000'; // Default for Android Emulator
    }
  }

  /// Saves the provided credentials to SharedPreferences.
  Future<void> _saveCredentials(String serverAddress, String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverAddress', serverAddress);
    await prefs.setString('username', username);
    await prefs.setString('password', password);
  }

  // The _clearCredentials method is now static in LoginPage,
  // so we don't need it here as a private instance method anymore.
  // It's directly accessible via LoginPage.clearSavedCredentials()

  @override
  void dispose() {
    // Dispose controllers to prevent memory leaks
    _serverAddressController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Sends the login request to the Flask API.
  /// `isAutoLogin` is used to suppress error messages for initial missing credentials.
  Future<void> _login({bool isAutoLogin = false}) async {
    if (_isLoading) return; // Prevent multiple login attempts

    setState(() {
      _isLoading = true; // Show loading indicator
      _errorMessage = null; // Clear old error message
    });

    final String serverAddress = _serverAddressController.text.trim();
    final String username = _usernameController.text.trim();
    final String password = _passwordController.text.trim();

    if (serverAddress.isEmpty || username.isEmpty || password.isEmpty) {
      if (isAutoLogin) {
        // If auto-login fails due to missing credentials, don't show error
        // Just let the user fill in the fields manually
      } else {
        setState(() {
          _errorMessage = 'Bitte fülle alle Felder aus.';
        });
      }
      setState(() {
        _isLoading = false; // Hide loading indicator
      });
      return; // End function as inputs are missing
    }

    // Construct the full login URL
    final Uri loginUrl = Uri.parse('$serverAddress/login');

    try {
      final response = await http.post(
        loginUrl,
        headers: <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded', // Flask expects 'application/x-www-form-urlencoded' for form data
        },
        // Send data as form encoding, as your Flask login uses `request.form`
        body: {'username': username, 'password': password},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody = json.decode(response.body);
        if (responseBody['success'] == true) {
          // Login successful!
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(responseBody['message'])),
          );

          // Save credentials after successful login
          await _saveCredentials(serverAddress, username, password);

          if (responseBody['redirect_to_setup'] == true) {
            // If Admin setup is required
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => AdminSetupPage(serverAddress: serverAddress)),
            );
          } else {
            // Normal login
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => HomePage(serverAddress: serverAddress)), // Navigate to the main app page
            );
          }
        } else {
          setState(() {
            _errorMessage = responseBody['message'] ?? 'Login fehlgeschlagen.';
          });
          if (isAutoLogin) await LoginPage.clearSavedCredentials(); // Clear if auto-login failed
        }
      } else {
        // HTTP error (e.g., 401 Unauthorized)
        final Map<String, dynamic> errorBody = json.decode(response.body);
        setState(() {
          _errorMessage = errorBody['message'] ?? 'Ein unerwarteter Fehler ist aufgetreten. Status: ${response.statusCode}';
        });
        print('Login-Fehler: ${response.statusCode} - ${response.body}');
        if (isAutoLogin) await LoginPage.clearSavedCredentials(); // Clear if auto-login failed
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Verbindungsfehler: Bitte überprüfe die Server-URL und deine Internetverbindung. ($e)';
      });
      print('Ausnahme beim Login: $e');
      if (isAutoLogin) await LoginPage.clearSavedCredentials(); // Clear if auto-login failed
    } finally {
      setState(() {
        _isLoading = false; // Hide loading indicator
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Access ThemeNotifier
    final themeNotifier = Provider.of<ThemeNotifier>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anmelden'),
        // AppBar colors are now managed by ThemeData
        actions: [
          IconButton(
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode // Sun icon for Dark Mode
                  : Icons.dark_mode, // Moon icon for Light Mode
            ),
            onPressed: () {
              themeNotifier.toggleTheme(); // Toggle theme
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // Optional: App Logo
              // Add a logo here if you have one.
              // Example: Image.asset('assets/logo.png', height: 150),
              // Or from your Flask app, but note that this address also needs to be entered via the new field
              // Image.network(
              //   '${_serverAddressController.text.trim()}/static/img/logo_V2.png',
              //   height: 150,
              //   errorBuilder: (context, error, stackTrace) => Icon(Icons.business, size: 100), // Fallback icon
              // ),
              const SizedBox(height: 30),
              TextField(
                controller: _serverAddressController,
                decoration: const InputDecoration(
                  labelText: 'Server-Adresse (z.B. http://10.0.2.2:5000)',
                  prefixIcon: Icon(Icons.dns),
                ),
                keyboardType: TextInputType.url,
                style: GoogleFonts.inter(), // Apply Inter font
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Benutzername',
                  prefixIcon: Icon(Icons.person),
                ),
                style: GoogleFonts.inter(), // Apply Inter font
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: true, // Hide password
                decoration: const InputDecoration(
                  labelText: 'Passwort',
                  prefixIcon: Icon(Icons.lock),
                ),
                style: GoogleFonts.inter(), // Apply Inter font
              ),
              const SizedBox(height: 30),
              _isLoading
                  ? const CircularProgressIndicator() // Show loading indicator
                  : ElevatedButton(
                      onPressed: _login,
                      child: const Text('Anmelden'),
                    ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Text(
                    _errorMessage!,
                    style: GoogleFonts.inter(color: Colors.red, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

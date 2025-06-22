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
    await prefs.remove('userRole'); // Clear user role as well
    await prefs.remove('sessionCookie'); // Clear session cookie as well
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

  /// Loads saved login credentials (server address, username, password, user role, session cookie) from SharedPreferences.
  /// If credentials are found, it attempts an auto-login.
  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedServerAddress = prefs.getString('serverAddress');
    final String? savedUsername = prefs.getString('username');
    final String? savedPassword = prefs.getString('password');
    final String? savedUserRole = prefs.getString('userRole'); // Load user role
    final String? savedSessionCookie = prefs.getString('sessionCookie'); // Load session cookie

    if (savedServerAddress != null && savedUsername != null && savedPassword != null && savedUserRole != null && savedSessionCookie != null) {
      _serverAddressController.text = savedServerAddress;
      _usernameController.text = savedUsername;
      _passwordController.text = savedPassword;

      // Attempt auto-login if credentials are found
      // We wrap this in a Future.microtask to allow the UI to build first,
      // preventing "setState() called during build" errors.
      Future.microtask(() => _login(isAutoLogin: true));
    } else {
      // Do nothing, leave the field empty if no saved credentials are found.
    }
  }

  /// Saves the provided credentials and session cookie to SharedPreferences.
  Future<void> _saveCredentials(String serverAddress, String username, String password, String userRole, String? sessionCookie) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverAddress', serverAddress);
    await prefs.setString('username', username);
    await prefs.setString('password', password);
    await prefs.setString('userRole', userRole); // Save user role
    if (sessionCookie != null) {
      await prefs.setString('sessionCookie', sessionCookie); // Save session cookie
    } else {
      await prefs.remove('sessionCookie'); // Remove if null
    }
  }

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
      if (!isAutoLogin) { // Only show error if not auto-login
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

        // Extract Set-Cookie header if present
        String? sessionCookie;
        if (response.headers.containsKey('set-cookie')) {
          sessionCookie = response.headers['set-cookie'];
          // For Flask, the cookie usually looks like 'session=ABCDEF; Path=/; HttpOnly'.
          // We just need the 'session=ABCDEF' part.
          sessionCookie = sessionCookie?.split(';').first;
          print('DEBUG: Received Set-Cookie: $sessionCookie');
        }

        if (responseBody['success'] == true) {
          // Login successful!
          final String userRole = responseBody['user_role'] ?? 'Betrachter'; // Default role if not provided by backend

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(responseBody['message']),
              behavior: SnackBarBehavior.floating, // Makes the SnackBar floating
              margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10.0, left: 16.0, right: 16.0), // Positions it at the top
              duration: const Duration(seconds: 2), // Short display duration
            ),
          );

          // Save credentials and user role, and the session cookie
          await _saveCredentials(serverAddress, username, password, userRole, sessionCookie);

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

  /// Shows a dialog explaining the server address format.
  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Hilfe zur Server-Adresse', style: GoogleFonts.inter()),
          content: Text(
            'Bitte gib hier die Basis-Domäne deines Servers ein, z.B. tool.example.com/ oder http://10.0.2.2:5000. Achte darauf, dass kein /login oder ähnliches am Ende steht.',
            style: GoogleFonts.inter(),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Verstanden', style: GoogleFonts.inter()),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Access ThemeNotifier
    final themeNotifier = Provider.of<ThemeNotifier>(context); // Listen to changes to react to theme toggling

    // Determine gradient colors based on current theme
    final List<Color> gradientColors;
    if (Theme.of(context).brightness == Brightness.dark) {
      gradientColors = [
        const Color(0xFF1A237E), // Dunkelblau
        const Color(0xFFB71C1C), // Dunkelrot
      ];
    } else {
      gradientColors = [
        Colors.green.shade300, // Grün
        Colors.blue.shade300, // Blau
      ];
    }

    // Determine border color based on current theme for input fields
    final Color borderColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withOpacity(0.5) // Light border for dark mode
        : Theme.of(context).colorScheme.onSurface.withOpacity(0.7); // Existing border for light mode

    // Focused border color (blue)
    final Color focusedBorderColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      // AppBar removed as requested

      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
        ),
        child: Stack(
          children: [
            // Title and Subtitle in the top left
            Positioned(
              top: 40.0,
              left: 16.0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bewertungstool',
                    style: GoogleFonts.inter(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onBackground,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Anmeldung',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      color: Theme.of(context).colorScheme.onBackground.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            // Logo in the top right
            Positioned(
              top: 40.0,
              right: 16.0,
              child: Image.asset(
                'assets/logo.png', // Corrected path assuming 'assets' folder is defined in pubspec.yaml
                width: 50, // Adjust size as needed
                height: 50,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.broken_image,
                    size: 50,
                    color: Colors.white,
                  ); // Fallback icon in case image asset is not found
                },
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const SizedBox(height: 180), // Increased space from the top to account for title/subtitle and logo
                    // TextField for Server Address
                    TextField(
                      controller: _serverAddressController,
                      decoration: InputDecoration(
                        labelText: 'Server-Adresse (z.B. http://tool.example.com/)',
                        prefixIcon: Icon(Icons.dns, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8)),
                        enabledBorder: UnderlineInputBorder( // Default state border
                          borderSide: BorderSide(color: borderColor, width: 1.0),
                        ),
                        focusedBorder: UnderlineInputBorder( // Focused state border
                          borderSide: BorderSide(color: focusedBorderColor, width: 2.0),
                        ),
                        labelStyle: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
                        filled: false, // Ensure it's not filled with any color
                      ),
                      keyboardType: TextInputType.url,
                      style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    const SizedBox(height: 20),
                    // TextField for Username
                    TextField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: 'Benutzername',
                        prefixIcon: Icon(Icons.person, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8)),
                        enabledBorder: UnderlineInputBorder( // Default state border
                          borderSide: BorderSide(color: borderColor, width: 1.0),
                        ),
                        focusedBorder: UnderlineInputBorder( // Focused state border
                          borderSide: BorderSide(color: focusedBorderColor, width: 2.0),
                        ),
                        labelStyle: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
                        filled: false, // Ensure it's not filled with any color
                      ),
                      style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    const SizedBox(height: 20),
                    // TextField for Password
                    TextField(
                      controller: _passwordController,
                      obscureText: true, // Hide password
                      decoration: InputDecoration(
                        labelText: 'Passwort',
                        prefixIcon: Icon(Icons.lock, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8)),
                        enabledBorder: UnderlineInputBorder( // Default state border
                          borderSide: BorderSide(color: borderColor, width: 1.0),
                        ),
                        focusedBorder: UnderlineInputBorder( // Focused state border
                          borderSide: BorderSide(color: focusedBorderColor, width: 2.0),
                        ),
                        labelStyle: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
                        filled: false, // Ensure it's not filled with any color
                      ),
                      style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    const SizedBox(height: 30),
                    _isLoading
                        ? const CircularProgressIndicator() // Show loading indicator
                        : ElevatedButton(
                            onPressed: _login,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30.0),
                              ),
                              backgroundColor: Theme.of(context).colorScheme.primary, // Button background color
                              foregroundColor: Theme.of(context).colorScheme.onPrimary, // Button text color
                            ),
                            child: Text(
                              'Anmelden',
                              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
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
            // Dark/Light Mode Toggler in the bottom left
            Positioned(
              bottom: 16.0,
              left: 16.0,
              child: IconButton(
                icon: Icon(
                  Theme.of(context).brightness == Brightness.dark
                      ? Icons.light_mode // Sun icon for Dark Mode
                      : Icons.dark_mode, // Moon icon for Light Mode
                  color: Theme.of(context).colorScheme.onBackground, // Icon color adapts to theme
                  size: 30.0,
                ),
                onPressed: () {
                  themeNotifier.toggleTheme(); // Toggle theme
                },
              ),
            ),
            // Help Icon in the bottom right
            Positioned(
              bottom: 16.0,
              right: 16.0,
              child: FloatingActionButton(
                onPressed: () => _showHelpDialog(context),
                backgroundColor: Theme.of(context).colorScheme.secondary,
                child: Icon(Icons.help_outline, color: Theme.of(context).colorScheme.onSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme_manager.dart'; // Adjust path if necessary
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // For session cookie and user role

/// The page for managing (resetting) various lists/data in the application.
class ManageListsPage extends StatefulWidget {
  final String serverAddress;
  const ManageListsPage({super.key, required this.serverAddress});

  @override
  State<ManageListsPage> createState() => _ManageListsPageState();
}

class _ManageListsPageState extends State<ManageListsPage> {
  // State variables for dynamic gradient colors from server
  Color _gradientColor1 = Colors.blue.shade50; // Default light mode start color
  Color _gradientColor2 = Colors.blue.shade200; // Default light mode end color
  Color _darkGradientColor1 = Colors.black; // Default dark mode start color
  Color _darkGradientColor2 = Colors.blueGrey; // Default dark mode end color

  bool _isLoading = true;
  String? _errorMessage;
  String? _sessionCookie; // Stores the session cookie for authenticated requests
  String? _userRole; // Stores the current user's role

  @override
  void initState() {
    super.initState();
    _loadSessionCookie().then((_) {
      _loadUserRole().then((_) {
        _fetchAppSettings(); // Load data after roles are loaded
      });
    });
  }

  /// Loads the session cookie from SharedPreferences.
  Future<void> _loadSessionCookie() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionCookie = prefs.getString('sessionCookie');
    print('DEBUG (Flutter): Session cookie loaded: $_sessionCookie');
  }

  /// Loads the user's role from SharedPreferences.
  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    _userRole = prefs.getString('userRole');
    print('DEBUG (Flutter): User role loaded: $_userRole');
  }

  /// Checks if the current user has any of the required roles.
  bool _userHasRequiredRole(List<String> requiredRoles) {
    if (_userRole == null) return false;
    return requiredRoles.contains(_userRole);
  }

  /// Converts a hex color string (e.g., "#RRGGBB") to a Flutter Color object.
  Color _hexToColor(String hexString) {
    final String hex = hexString.replaceAll('#', '');
    if (hex.length == 6) {
      return Color(int.parse('ff$hex', radix: 16));
    } else if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    print('WARN (Flutter): Invalid hex color string: $hexString. Returning grey.');
    return Colors.grey; // Default or error color
  }

  /// Helper function to get headers with the session cookie.
  Map<String, String> _getAuthHeaders() {
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
    };
    if (_sessionCookie != null) {
      headers['Cookie'] = _sessionCookie!;
    }
    return headers;
  }

  /// Fetches app settings for background gradients.
  Future<void> _fetchAppSettings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Immediate role check
    if (!_userHasRequiredRole(['Administrator'])) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Sie haben keine Berechtigung, auf diese Seite zuzugreifen.';
      });
      return;
    }

    try {
      final headers = _getAuthHeaders();
      final response = await http.get(Uri.parse('${widget.serverAddress}/api/admin_settings'), headers: headers);

      print('DEBUG (Flutter): Admin Settings API response status: ${response.statusCode}');
      print('DEBUG (Flutter): Admin Settings API response body: ${response.body}');
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] && data.containsKey('settings')) {
          setState(() {
            _gradientColor1 = _hexToColor(data['settings']['bg_gradient_color1'] ?? '#E3F2FD');
            _gradientColor2 = _hexToColor(data['settings']['bg_gradient_color2'] ?? '#BBDEFB');
            _darkGradientColor1 = _hexToColor(data['settings']['dark_bg_gradient_color1'] ?? '#000000');
            _darkGradientColor2 = _hexToColor(data['settings']['dark_bg_gradient_color2'] ?? '#455A64');
          });
        }
      } else {
        print('Error fetching admin settings for gradient: ${response.statusCode}');
      }
    } catch (e) {
      _errorMessage = 'Verbindungsfehler: $e';
      print('Exception fetching app settings: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Handles the reset action for various data types.
  Future<void> _handleResetAction(String actionType, String confirmationMessage) async {
    // First confirmation dialog
    final bool firstConfirm = await _showConfirmationDialog(
      'Aktion bestätigen',
      confirmationMessage,
    );
    if (!firstConfirm) {
      return; // User cancelled
    }

    // Second confirmation dialog
    final bool secondConfirm = await _showConfirmationDialog(
      'Letzte Warnung!',
      'Diese Aktion kann NICHT rückgängig gemacht werden. Sind Sie absolut sicher?',
      isDestructive: true,
    );
    if (!secondConfirm) {
      return; // User cancelled
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final headers = _getAuthHeaders();
    final requestBody = json.encode({'action': actionType});
    print('DEBUG (Flutter): Sending reset action request body: $requestBody');

    try {
      final response = await http.post(
        Uri.parse('${widget.serverAddress}/api/reset_data'),
        headers: headers,
        body: requestBody,
      );

      final Map<String, dynamic> data = json.decode(response.body);
      print('DEBUG (Flutter): Reset action response status: ${response.statusCode}');
      print('DEBUG (Flutter): Reset action response body: ${response.body}');
      if (response.statusCode == 200 && data['success']) {
        _showAlertDialog('Erfolg', data['message']);
      } else {
        _showAlertDialog('Fehler', data['message'] ?? 'Fehler beim Zurücksetzen der Daten.');
      }
    } catch (e) {
      _showAlertDialog('Verbindungsfehler', 'Fehler beim Zurücksetzen der Daten: $e');
      print('ERROR (Flutter): Exception during reset action: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Displays an alert dialog for messages.
  Future<void> _showAlertDialog(String title, String message) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          content: Text(message, style: GoogleFonts.inter()),
          actions: <Widget>[
            TextButton(
              child: Text('OK', style: GoogleFonts.inter()),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// Displays a confirmation dialog and returns true if confirmed, false otherwise.
  Future<bool> _showConfirmationDialog(String title, String message, {bool isDestructive = false}) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              content: Text(message, style: GoogleFonts.inter()),
              actions: <Widget>[
                TextButton(
                  child: Text('Abbrechen', style: GoogleFonts.inter()),
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                ),
                ElevatedButton(
                  child: Text(isDestructive ? 'Löschen' : 'Bestätigen', style: GoogleFonts.inter()),
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDestructive ? Colors.red : Theme.of(context).primaryColor,
                  ),
                ),
              ],
            );
          },
        ) ??
        false; // Returns false if dialog is dismissed
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final Gradient backgroundGradient = isDarkMode
        ? LinearGradient(
            colors: [_darkGradientColor1, _darkGradientColor2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [_gradientColor1, _gradientColor2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    // Initial loading/access denied screen
    if (_isLoading || !_userHasRequiredRole(['Administrator'])) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(gradient: backgroundGradient),
              ),
            ),
            Center(
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Listen verwalten',
                            style: GoogleFonts.inter(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.headlineLarge?.color,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 30),
                          Icon(Icons.lock_outline,
                              size: 60, color: Theme.of(context).disabledColor),
                          const SizedBox(height: 20),
                          Text(
                            'Um hierdrauf zugreifen zu können, brauchst du die Rolle Administrator. Bei Bedarf kannst du diese beim Organisator erfragen.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                                fontSize: 18,
                                color: Theme.of(context).textTheme.bodyLarge?.color),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      );
    }

    // Error screen
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(gradient: backgroundGradient),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Listen verwalten',
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.headlineLarge?.color,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),
                    Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 10),
                    Text(
                      _errorMessage!,
                      style: GoogleFonts.inter(color: Colors.red, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _fetchAppSettings,
                      child: const Text('Erneut versuchen'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Main content when loaded and authorized
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(gradient: backgroundGradient),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back arrow and title in a row
                Padding(
                  padding: const EdgeInsets.only(top: 16.0, bottom: 16.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back,
                            color: Theme.of(context).iconTheme.color),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          'Listen verwalten',
                          style: GoogleFonts.inter(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).textTheme.headlineLarge?.color,
                          ),
                          textAlign: TextAlign.left,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Reset Ranking Card
                _buildResetCard(
                  context,
                  isDarkMode,
                  'Rangliste zurücksetzen',
                  'Alle eingetragenen Bewertungen und die daraus resultierende Rangliste werden unwiderruflich gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.',
                  'reset_ranking',
                  'Rangliste jetzt zurücksetzen',
                ),

                // Reset Room Inspections Card
                _buildResetCard(
                  context,
                  isDarkMode,
                  'Rauminspektionen zurücksetzen',
                  'Alle eingetragenen Rauminspektionen werden unwiderruflich gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.',
                  'reset_room_inspections',
                  'Rauminspektionen jetzt zurücksetzen',
                ),

                // Reset Warnings Card
                _buildResetCard(
                  context,
                  isDarkMode,
                  'Verwarnungen zurücksetzen',
                  'Alle eingetragenen Verwarnungen werden unwiderruflich gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.',
                  'reset_warnings',
                  'Alle Verwarnungen zurücksetzen',
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Helper method to build a consistent reset action card.
  Widget _buildResetCard(
    BuildContext context,
    bool isDarkMode,
    String title,
    String description,
    String actionType,
    String buttonText,
  ) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      color: isDarkMode ? Colors.black : Colors.white,
      margin: const EdgeInsets.only(bottom: 24.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.headlineMedium?.color,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              description,
              style: GoogleFonts.inter(
                fontSize: 16,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _isLoading
                    ? null
                    : () => _handleResetAction(actionType, description), // Pass description for first dialog
                icon: const Icon(Icons.delete_forever),
                label: Text(buttonText, style: GoogleFonts.inter(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

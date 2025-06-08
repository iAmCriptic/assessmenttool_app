import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart'; // For date formatting

/// Represents a single evaluation for display.
class UserEvaluation {
  final int evaluationId;
  final String standName;
  final int totalAchievedScore;
  final String timestamp; // Formatted timestamp from backend

  UserEvaluation({
    required this.evaluationId,
    required this.standName,
    required this.totalAchievedScore,
    required this.timestamp,
  });

  factory UserEvaluation.fromJson(Map<String, dynamic> json) {
    return UserEvaluation(
      evaluationId: json['evaluation_id'],
      standName: json['stand_name'],
      totalAchievedScore: json['total_achieved_score'] ?? 0,
      timestamp: json['timestamp'],
    );
  }
}

/// The 'My Evaluations' page where users can view their past evaluations.
class MyEvaluationsPage extends StatefulWidget {
  final String serverAddress;
  // REMOVED: final String? currentUserRole; // No longer passed from HomePage

  const MyEvaluationsPage({super.key, required this.serverAddress});

  @override
  State<MyEvaluationsPage> createState() => _MyEvaluationsPageState();
}

class _MyEvaluationsPageState extends State<MyEvaluationsPage> {
  String? _sessionCookie;
  String? _userRole; // REINSTATED: User role is now managed internally
  bool _isLoading = true;
  String? _errorMessage;
  List<UserEvaluation> _myEvaluations = [];
  int _evaluatedStandsCount = 0;
  int _totalStandsCount = 0;

  // Neue State-Variablen für dynamische Farbverläufe vom Server
  Color _gradientColor1 = Colors.blue.shade50; // Standard Hellmodus Startfarbe
  Color _gradientColor2 = Colors.blue.shade200; // Standard Hellmodus Endfarbe
  Color _darkGradientColor1 = Colors.black; // Standard Dunkelmodus Startfarbe
  Color _darkGradientColor2 = Colors.blueGrey; // Standard Dunkelmodus Endfarbe


  @override
  void initState() {
    super.initState();
    _loadSessionCookie().then((_) {
      _loadUserRole().then((_) { // Load user role first
        // Check role and fetch data
        if (_userHasRequiredRole(['Administrator', 'Bewerter'])) {
          _fetchPageData(); // Ruft jetzt alle Daten ab (Bewertungen & Einstellungen)
        } else {
          setState(() {
            _isLoading = false; // Stop loading if user has no access
            _errorMessage = 'Sie haben keine Berechtigung, auf diese Seite zuzugreifen.'; // Set error message for unauthorized access
          });
        }
      });
    });
  }

  /// Loads the session cookie from SharedPreferences.
  Future<void> _loadSessionCookie() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionCookie = prefs.getString('sessionCookie');
  }

  /// Loads the user's role from SharedPreferences and updates the state.
  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userRole = prefs.getString('userRole');
    });
  }

  /// Checks if the current user has any of the required roles.
  bool _userHasRequiredRole(List<String> requiredRoles) {
    if (_userRole == null) return false; // Use internal _userRole
    return requiredRoles.contains(_userRole); // Use internal _userRole
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

  /// Konvertiert einen Hex-Farbstring (z.B. "#RRGGBB") in ein Flutter Color-Objekt.
  Color _hexToColor(String hexString) {
    final String hex = hexString.replaceAll('#', '');
    return Color(int.parse('ff$hex', radix: 16));
  }

  /// Fetches all necessary evaluation data concurrently from the Flask backend.
  Future<void> _fetchPageData() async {
    // Reload user role before fetching data, as it might have changed on StartPage
    await _loadUserRole(); 

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Check permissions again just before fetching data in case of dynamic role change
    if (!_userHasRequiredRole(['Administrator', 'Bewerter'])) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Sie haben keine Berechtigung, auf diese Seite zuzugreifen.';
      });
      return;
    }

    try {
      final headers = _getAuthHeaders();

      // Fetch all evaluations for the current user
      final Future<http.Response> evaluationsFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/my_evaluations'), headers: headers);

      // Fetch all stands to get the total count
      final Future<http.Response> allStandsFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/evaluate_initial_data'), headers: headers); // This endpoint also returns all stands
      
      // Fetch admin settings for gradient colors
      final Future<http.Response> adminSettingsFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/admin_settings'), headers: headers);

      final List<http.Response> responses = await Future.wait([
        evaluationsFuture,
        allStandsFuture,
        adminSettingsFuture,
      ]);

      // Process My Evaluations Response
      final evaluationsResponse = responses[0];
      if (evaluationsResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(evaluationsResponse.body);
        if (data['success'] && data['evaluations'] is List) {
          setState(() {
            _myEvaluations = (data['evaluations'] as List)
                .map((e) => UserEvaluation.fromJson(e))
                .toList();
            _evaluatedStandsCount = _myEvaluations.length; // Count of evaluated stands
          });
        } else {
           _errorMessage = data['message'] ?? 'Unbekannter Fehler beim Laden deiner Bewertungen.';
        }
      } else {
        print('Error fetching my evaluations: ${evaluationsResponse.statusCode} - ${evaluationsResponse.body}');
        _errorMessage = 'Fehler beim Laden deiner Bewertungen: ${evaluationsResponse.reasonPhrase}';
      }

      // Process All Stands Response (for total count)
      final allStandsResponse = responses[1];
      if (allStandsResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(allStandsResponse.body);
        if (data['success'] && data['stands'] is List) {
          setState(() {
            _totalStandsCount = (data['stands'] as List).length; // Total count of all stands
          });
        }
      } else {
        print('Error fetching all stands: ${allStandsResponse.statusCode} - ${allStandsResponse.body}');
        // Don't set _errorMessage here if evaluations loaded successfully, just log.
      }

      // Verarbeitung der Admin-Einstellungen (für den Farbverlauf)
      final adminSettingsResponse = responses[2];
      if (adminSettingsResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(adminSettingsResponse.body);
        if (data['success'] && data.containsKey('settings')) {
          setState(() {
            _gradientColor1 = _hexToColor(data['settings']['bg_gradient_color1'] ?? '#E3F2FD');
            _gradientColor2 = _hexToColor(data['settings']['bg_gradient_color2'] ?? '#BBDEFB');
            _darkGradientColor1 = _hexToColor(data['settings']['dark_bg_gradient_color1'] ?? '#000000');
            _darkGradientColor2 = _hexToColor(data['settings']['dark_bg_gradient_color2'] ?? '#455A64');
          });
        }
      } else {
        print('Error fetching admin settings for gradient: ${adminSettingsResponse.statusCode}');
      }


    } catch (e) {
      _errorMessage = 'Verbindungsfehler: $e';
      print('Exception fetching my evaluations data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Displays an alert dialog for messages.
  void _showAlertDialog(String title, String message) {
    showDialog(
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

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Definiere die Farbverläufe basierend auf dem aktuellen Theme-Modus und den abgerufenen Farben
    final Gradient backgroundGradient = isDarkMode
        ? LinearGradient(
            colors: [_darkGradientColor1, _darkGradientColor2], // Verwende abgerufene Dunkelmodus-Farben
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [_gradientColor1, _gradientColor2], // Verwende abgerufene Hellmodus-Farben
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    if (!_userHasRequiredRole(['Administrator', 'Bewerter'])) {
      // Display access denied message
      return Scaffold(
        // Hintergrund transparent setzen, damit der Gradient durchscheint
        backgroundColor: Colors.transparent, 
        body: Stack( // Stack verwenden, um Hintergrund und Inhalt zu schichten
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: backgroundGradient, // Den Farbverlauf anwenden
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Custom Title
                    Text(
                      'Meine Bewertungen',
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.headlineLarge?.color,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),
                    Icon(Icons.lock_outline, size: 60, color: Theme.of(context).disabledColor),
                    const SizedBox(height: 20),
                    Text(
                      'Um hierdrauf zugreifen zu Können, brauchst du die Rolle Bewerter oder Administrator. Bei Bedarf kannst du diese beim Organisator erfragen.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 18, color: Theme.of(context).textTheme.bodyLarge?.color),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return Scaffold(
        // Hintergrund transparent setzen, damit der Gradient durchscheint
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: backgroundGradient,
                ),
              ),
            ),
            const Center(child: CircularProgressIndicator()),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        // Hintergrund transparent setzen, damit der Gradient durchscheint
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: backgroundGradient,
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Custom Title
                    Text(
                      'Meine Bewertungen',
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
                      onPressed: _fetchPageData,
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

    return Scaffold(
      // Hintergrund transparent setzen, damit der Gradient durchscheint
      backgroundColor: Colors.transparent, 
      body: Stack( // Stack verwenden, um Hintergrund und Inhalt zu schichten
        children: [
          // Hintergrund-Gradient-Container (füllt den gesamten Scaffold-Body)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: backgroundGradient, // Den Farbverlauf anwenden
              ),
            ),
          ),
          // Vordergrund-Inhalt (RefreshIndicator und SingleChildScrollView)
          RefreshIndicator(
            onRefresh: _fetchPageData,
            child: LayoutBuilder( // LayoutBuilder verwenden, um Constraints zu erhalten
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    16.0,
                    16.0,
                    16.0,
                    16.0 + MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight, 
                  ),
                  child: ConstrainedBox( // Hinzugefügt, um den Inhalt auf die Mindesthöhe zu zwingen
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - (
                        16.0 + // Top padding
                        16.0 + // Bottom padding
                        MediaQuery.of(context).padding.bottom + // System bottom inset
                        kBottomNavigationBarHeight // Height of BottomAppBar
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Custom Title and Back Button
                        Padding(
                          padding: const EdgeInsets.only(top: 16.0, bottom: 16.0),
                          child: Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.arrow_back, color: Theme.of(context).iconTheme.color),
                                onPressed: () => Navigator.pop(context),
                              ),
                              Expanded(
                                child: Text(
                                  'Meine Bewertungen',
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

                        // Summary of evaluated stands
                        if (_evaluatedStandsCount > 0 || _totalStandsCount > 0)
                          Align(
                            alignment: Alignment.center,
                            child: Card( // Wrap in Card
                              margin: const EdgeInsets.only(bottom: 20.0),
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              color: isDarkMode ? Colors.black : Colors.white, // Card color
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Text(
                                  'Bewertete Stände: $_evaluatedStandsCount von $_totalStandsCount',
                                  style: GoogleFonts.inter(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).textTheme.bodyLarge?.color,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        
                        if (_myEvaluations.isEmpty)
                          Center(
                            child: Text(
                              'Du hast noch keine Bewertungen abgegeben.',
                              style: GoogleFonts.inter(fontSize: 16, color: Colors.grey[600]),
                              textAlign: TextAlign.center,
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _myEvaluations.length,
                            itemBuilder: (context, index) {
                              final evaluation = _myEvaluations[index];
                              
                              // Parse the ISO 8601 string to DateTime object
                              final DateTime parsedTimestamp = DateTime.parse(evaluation.timestamp);
                              // Format the DateTime object to DD.MM.YYYY - HH:mm (corrected format)
                              final String formattedTimestamp = DateFormat('dd.MM.yyyy - HH:mm').format(parsedTimestamp.toLocal());

                              return Card(
                                margin: const EdgeInsets.only(bottom: 16.0),
                                elevation: 4,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                                color: isDarkMode ? Colors.black : Colors.white, // Card color
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        evaluation.standName,
                                        style: GoogleFonts.inter(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).textTheme.headlineMedium?.color,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Erreichte Gesamtpunktzahl: ${evaluation.totalAchievedScore} Punkte',
                                        style: GoogleFonts.inter(fontSize: 16, color: Colors.blueAccent),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Bewertet am: $formattedTimestamp', // Use the formatted timestamp
                                        style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                );
              }
            ),
          ),
        ],
      ),
    );
  }
}

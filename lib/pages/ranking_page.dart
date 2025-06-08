import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart'; // For session cookie and user role

/// Represents a single entry in the ranking.
class RankingEntry {
  final int rank;
  final String standName;
  final String? roomName; // Can be null
  final int totalAchievedScore;
  final int numEvaluators;

  RankingEntry({
    required this.rank,
    required this.standName,
    this.roomName,
    required this.totalAchievedScore,
    required this.numEvaluators,
  });

  factory RankingEntry.fromJson(Map<String, dynamic> json) {
    return RankingEntry(
      rank: json['rank'],
      standName: json['stand_name'],
      roomName: json['room_name'],
      totalAchievedScore: json['total_achieved_score'] ?? 0,
      numEvaluators: json['num_evaluators'] ?? 0,
    );
  }
}

/// The 'Ranking' page, displaying a list of stands by their total scores.
class RankingPage extends StatefulWidget {
  final String serverAddress;

  const RankingPage({super.key, required this.serverAddress});

  @override
  State<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends State<RankingPage> {
  String? _userRole;
  String? _sessionCookie;

  bool _isLoading = true;
  String? _errorMessage;
  List<RankingEntry> _rankings = [];

  // Neue State-Variablen für dynamische Farbverläufe vom Server
  Color _gradientColor1 = Colors.blue.shade50; // Standard Hellmodus Startfarbe
  Color _gradientColor2 = Colors.blue.shade200; // Standard Hellmodus Endfarbe
  Color _darkGradientColor1 = Colors.black; // Standard Dunkelmodus Startfarbe
  Color _darkGradientColor2 = Colors.blueGrey; // Standard Dunkelmodus Endfarbe

  @override
  void initState() {
    super.initState();
    _loadSessionCookie().then((_) {
      _loadUserRole().then((_) {
        // Fetch data only if user has access roles
        if (_userHasRequiredRole(['Administrator', 'Bewerter', 'Betrachter', 'Inspektor', 'Verwarner'])) {
          _fetchPageData(); // Ruft jetzt alle Daten ab (Rankings & Einstellungen)
        } else {
          setState(() {
            _isLoading = false; // Stop loading if user has no access
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

  /// Loads the user's role from SharedPreferences.
  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    _userRole = prefs.getString('userRole');
  }

  /// Checks if the current user has any of the required roles.
  bool _userHasRequiredRole(List<String> requiredRoles) {
    if (_userRole == null) return false;
    return requiredRoles.contains(_userRole);
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

  /// Fetches all necessary data for the page (rankings and app settings).
  Future<void> _fetchPageData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (!_userHasRequiredRole(['Administrator', 'Bewerter', 'Betrachter', 'Inspektor', 'Verwarner'])) {
       setState(() {
         _isLoading = false;
         _errorMessage = 'Sie haben keine Berechtigung, auf diese Seite zuzugreifen.';
       });
       return;
    }

    try {
      final headers = _getAuthHeaders();

      // Rufe beide Endpunkte gleichzeitig ab
      final Future<http.Response> rankingFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/ranking_data'), headers: headers);
      final Future<http.Response> adminSettingsFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/admin_settings'), headers: headers);

      final List<http.Response> responses = await Future.wait([rankingFuture, adminSettingsFuture]);

      // Verarbeitung der Ranking-Daten
      final rankingResponse = responses[0];
      if (rankingResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(rankingResponse.body);
        if (data['success']) {
          setState(() {
            _rankings = (data['rankings'] as List)
                .map((r) => RankingEntry.fromJson(r))
                .toList();
          });
        } else {
          _errorMessage = data['message'] ?? 'Fehler beim Laden der Ranglistendaten.';
        }
      } else {
        _errorMessage = 'Fehler ${rankingResponse.statusCode}: ${rankingResponse.reasonPhrase}';
        print('Error fetching ranking data: ${rankingResponse.statusCode} - ${rankingResponse.body}');
      }

      // Verarbeitung der Admin-Einstellungen (für den Farbverlauf)
      final adminSettingsResponse = responses[1];
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
      print('Exception fetching page data: $e');
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

    if (!_userHasRequiredRole(['Administrator', 'Bewerter', 'Betrachter', 'Inspektor', 'Verwarner'])) {
      return Scaffold(
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
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Rangliste',
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
                      'Um hierdrauf zugreifen zu Können, brauchst du eine entsprechende Rolle. Bei Bedarf kannst du diese beim Organisator erfragen.',
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
                    Text(
                      'Rangliste',
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
          RefreshIndicator(
            onRefresh: _fetchPageData,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    16.0,
                    16.0,
                    16.0,
                    16.0 + MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight,
                  ),
                  child: ConstrainedBox(
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
                                  'Rangliste',
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

                        if (_rankings.isEmpty)
                          Center(
                            child: Text(
                              'Keine Ranglistendaten gefunden.',
                              style: GoogleFonts.inter(fontSize: 16, color: Colors.grey[600]),
                              textAlign: TextAlign.center,
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _rankings.length,
                            itemBuilder: (context, index) {
                              final ranking = _rankings[index];
                              final isDarkMode = Theme.of(context).brightness == Brightness.dark;

                              // Bestimme die Farbe des Rangs basierend auf der Platzierung
                              Color rankColor;
                              if (ranking.rank == 1) {
                                rankColor = Colors.amber; // Gold für Platz 1
                              } else if (ranking.rank == 2) {
                                rankColor = Colors.grey; // Silber für Platz 2
                              } else if (ranking.rank == 3) {
                                rankColor = Colors.brown; // Bronze für Platz 3
                              } else {
                                rankColor = isDarkMode ? Colors.white70 : Colors.black87; // Standardfarbe
                              }

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
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Platz ${ranking.rank}',
                                            style: GoogleFonts.inter(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: rankColor, // Dynamische Farbe für den Rang
                                            ),
                                          ),
                                          Text(
                                            '${ranking.totalAchievedScore} Punkte',
                                            style: GoogleFonts.inter(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blueAccent,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        ranking.standName,
                                        style: GoogleFonts.inter(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context).textTheme.headlineMedium?.color,
                                        ),
                                      ),
                                      if (ranking.roomName != null && ranking.roomName!.isNotEmpty)
                                        Text(
                                          'Raum: ${ranking.roomName}',
                                          style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
                                        ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Bewertet von: ${ranking.numEvaluators} Bewertern',
                                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
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

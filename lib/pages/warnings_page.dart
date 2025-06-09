import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart'; // For date formatting

/// Represents a Stand for the dropdown.
class StandForDropdown {
  final int id;
  final String name;

  StandForDropdown({required this.id, required this.name});

  factory StandForDropdown.fromJson(Map<String, dynamic> json) {
    return StandForDropdown(
      id: json['id'],
      name: json['name'],
    );
  }
}

/// Represents an individual Warning.
class Warning {
  final int id;
  final int standId;
  final String standName;
  final String warnerName;
  final String comment;
  final String timestamp;
  bool isInvalidated; // Can be changed in UI
  String? invalidatedByUserName;
  String? invalidationComment;
  String? invalidationTimestamp;

  Warning({
    required this.id,
    required this.standId,
    required this.standName,
    required this.warnerName,
    required this.comment,
    required this.timestamp,
    this.isInvalidated = false,
    this.invalidatedByUserName,
    this.invalidationComment,
    this.invalidationTimestamp,
  });

  factory Warning.fromJson(Map<String, dynamic> json) {
    return Warning(
      id: json['id'],
      standId: json['stand_id'],
      standName: json['stand_name'],
      warnerName: json['warner_name'] ?? 'Unbekannt',
      comment: json['comment'] ?? 'Kein Kommentar',
      timestamp: json['timestamp'] ?? 'N/A',
      isInvalidated: json['is_invalidated'] == 1, // Backend sends 0/1
      invalidatedByUserName: json['invalidated_by_user_name'],
      invalidationComment: json['invalidation_comment'],
      invalidationTimestamp: json['invalidation_timestamp'],
    );
  }
}

/// Represents a group of warnings for a specific stand.
class GroupedWarning {
  final int standId;
  final String standName;
  int totalWarnings; // Number of valid warnings
  List<Warning> warnings; // List of all warnings for this stand

  GroupedWarning({
    required this.standId,
    required this.standName,
    required this.totalWarnings,
    required this.warnings,
  });
}

/// The 'Warnings' page where users can manage and view warnings.
class WarningsPage extends StatefulWidget {
  final String serverAddress; // Server address is now required in the constructor

  const WarningsPage({super.key, required this.serverAddress});

  @override
  State<WarningsPage> createState() => _WarningsPageState();
}

class _WarningsPageState extends State<WarningsPage> {
  String? _userRole;
  String? _sessionCookie;
  String? _logoFullPath; // Added for the logo

  bool _isLoading = true;
  String? _errorMessage;

  List<StandForDropdown> _standsForDropdown = [];
  List<GroupedWarning> _groupedWarnings = [];

  StandForDropdown? _selectedStandForNewWarning;
  final TextEditingController _newWarningCommentController = TextEditingController();

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
        // Always fetch admin settings for gradient and logo
        _fetchPageData(fetchWarnings: _userHasRequiredRole(['Administrator', 'Verwarner']));
      });
    });
  }

  @override
  void dispose() {
    _newWarningCommentController.dispose();
    super.dispose();
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

  /// Fetches all necessary data for the page (warnings and app settings).
  Future<void> _fetchPageData({bool fetchWarnings = true}) async {
    await _loadUserRole(); // Ensure role is up-to-date

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final headers = _getAuthHeaders();

      final Future<http.Response> warningsFuture = fetchWarnings
          ? http.get(Uri.parse('${widget.serverAddress}/warnings/api/warnings_data'), headers: headers)
          : Future.value(http.Response('{"success": false, "message": "Keine Berechtigung"}', 403)); // Dummy response

      final Future<http.Response> adminSettingsFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/admin_settings'), headers: headers);

      final List<http.Response> responses = await Future.wait([warningsFuture, adminSettingsFuture]);


      // Verarbeitung der Warnungsdaten
      final warningsResponse = responses[0];
      if (warningsResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(warningsResponse.body);
        if (data['success']) {
          setState(() {
            _standsForDropdown = (data['stands_for_dropdown'] as List)
                .map((s) => StandForDropdown.fromJson(s))
                .toList();

            _groupedWarnings.clear();
            (data['grouped_warnings'] as List).forEach((gwData) {
              final List<Warning> warningsList = (gwData['warnings'] as List)
                  .map((w) => Warning.fromJson(w))
                  .toList();
              _groupedWarnings.add(GroupedWarning(
                standId: gwData['stand_id'],
                standName: gwData['stand_name'],
                totalWarnings: gwData['total_warnings'],
                warnings: warningsList,
              ));
            });
          });
        } else {
          _errorMessage = data['message'] ?? 'Fehler beim Laden der Verwarnungsdaten.';
        }
      } else if (warningsResponse.statusCode == 403) {
        _errorMessage = 'Sie haben keine Berechtigung, auf diese Seite zuzugreifen.';
      } else {
        _errorMessage = 'Fehler ${warningsResponse.statusCode}: ${warningsResponse.reasonPhrase}';
        print('Error fetching warnings data: ${warningsResponse.statusCode} - ${warningsResponse.body}');
      }

      // Verarbeitung der Admin-Einstellungen (für den Farbverlauf und Logo)
      final adminSettingsResponse = responses[1];
      if (adminSettingsResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(adminSettingsResponse.body);
        if (data['success'] && data.containsKey('settings')) {
          setState(() {
            _gradientColor1 = _hexToColor(data['settings']['bg_gradient_color1'] ?? '#E3F2FD');
            _gradientColor2 = _hexToColor(data['settings']['bg_gradient_color2'] ?? '#BBDEFB');
            _darkGradientColor1 = _hexToColor(data['settings']['dark_bg_gradient_color1'] ?? '#000000');
            _darkGradientColor2 = _hexToColor(data['settings']['dark_bg_gradient_color2'] ?? '#455A64');

            final String? logoPathFromBackend = data['settings']['logo_path'];
            if (logoPathFromBackend != null && logoPathFromBackend.isNotEmpty) {
              if (logoPathFromBackend.startsWith('http://') || logoPathFromBackend.startsWith('https://')) {
                _logoFullPath = logoPathFromBackend;
              } else {
                String serverAddress = widget.serverAddress;
                String cleanedLogoPath = logoPathFromBackend;
                if (serverAddress.endsWith('/')) {
                  serverAddress = serverAddress.substring(0, serverAddress.length - 1);
                }
                if (cleanedLogoPath.startsWith('/')) {
                  cleanedLogoPath = cleanedLogoPath.substring(1);
                }
                _logoFullPath = '$serverAddress/$cleanedLogoPath';
              }
            } else {
              _logoFullPath = null;
            }
          });
        }
      } else {
        print('Error fetching admin settings for gradient and logo: ${adminSettingsResponse.statusCode}');
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


  /// Submits a new warning.
  Future<void> _submitNewWarning() async {
    if (_selectedStandForNewWarning == null) {
      _showAlertDialog('Fehler', 'Bitte wählen Sie einen Stand aus.');
      return;
    }
    if (_newWarningCommentController.text.trim().isEmpty) {
      _showAlertDialog('Fehler', 'Bitte geben Sie einen Kommentar ein.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final headers = _getAuthHeaders();
      final response = await http.post(
        Uri.parse('${widget.serverAddress}/warnings/'), 
        headers: headers,
        body: json.encode({
          'stand_id': _selectedStandForNewWarning!.id,
          'comment': _newWarningCommentController.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success']) {
          _showAlertDialog('Erfolg', data['message'] ?? 'Verwarnung erfolgreich hinzugefügt!');
          _newWarningCommentController.clear();
          _selectedStandForNewWarning = null; // Clear selected stand after submission
          _fetchPageData(); // Refresh data
        } else {
          _showAlertDialog('Fehler', data['message'] ?? 'Verwarnung konnte nicht hinzugefügt werden.');
        }
      } else {
        final Map<String, dynamic> errorData = json.decode(response.body);
        _showAlertDialog('Fehler', errorData['message'] ?? 'Ein Fehler ist aufgetreten. Status: ${response.statusCode}');
      }
    } catch (e) {
      _showAlertDialog('Verbindungsfehler', 'Fehler beim Senden der Verwarnung: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Shows a dialog to get invalidation comment and then invalidates the warning.
  Future<void> _showInvalidateWarningDialog(Warning warning) async {
    final TextEditingController commentController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Verwarnung ungültig machen', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: commentController,
            decoration: InputDecoration(
              labelText: 'Kommentar zur Ungültigmachung (optional)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            maxLines: 3,
            style: GoogleFonts.inter(),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Abbrechen', style: GoogleFonts.inter()),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: Text('Ungültig machen', style: GoogleFonts.inter()),
              onPressed: () {
                Navigator.of(context).pop();
                _invalidateWarning(warning.id, commentController.text.trim());
              },
            ),
          ],
        );
      },
    );
    commentController.dispose();
  }

  /// Invalidates a specific warning.
  Future<void> _invalidateWarning(int warningId, String comment) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final headers = _getAuthHeaders();
      final response = await http.post(
        Uri.parse('${widget.serverAddress}/warnings/invalidate_warning/$warningId'), 
        headers: headers,
        body: json.encode({'invalidation_comment': comment}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        _showAlertDialog('Erfolg', data['message'] ?? 'Verwarnung erfolgreich als ungültig markiert.');
        _fetchPageData(); // Refresh data
      } else {
        final Map<String, dynamic> errorData = json.decode(response.body);
        _showAlertDialog('Fehler', errorData['message'] ?? 'Verwarnung konnte nicht ungültig gemacht werden.');
      }
    } catch (e) {
      _showAlertDialog('Verbindungsfehler', 'Fehler beim Ungültigmachen der Verwarnung: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Makes a specific warning valid again.
  Future<void> _makeWarningValid(int warningId) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final headers = _getAuthHeaders();
      final response = await http.post(
        Uri.parse('${widget.serverAddress}/warnings/make_warning_valid/$warningId'), 
        headers: headers,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        _showAlertDialog('Erfolg', data['message'] ?? 'Verwarnung erfolgreich als gültig markiert.');
        _fetchPageData(); // Refresh data
      } else {
        final Map<String, dynamic> errorData = json.decode(response.body);
        _showAlertDialog('Fehler', errorData['message'] ?? 'Verwarnung konnte nicht gültig gemacht werden.');
      }
    } catch (e) {
      _showAlertDialog('Verbindungsfehler', 'Fehler beim Gültigmachen der Verwarnung: $e');
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

  // Helper widget for the header with title and logo
  Widget _buildHeaderWithLogo(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0), // Added horizontal padding
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center, // Vertically center
        children: [
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.headlineLarge?.color,
              ),
              textAlign: TextAlign.left,
            ),
          ),
          if (_logoFullPath != null && _logoFullPath!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: Image.network(
                _logoFullPath!,
                height: 80, // Larger logo size
                width: 80,  // Larger logo size
                fit: BoxFit.contain,
                key: ValueKey(_logoFullPath),
                errorBuilder: (context, error, stackTrace) =>
                    Icon(Icons.business, size: 80, color: Theme.of(context).iconTheme.color), // Icon size matches
              ),
            )
          else
            Icon(Icons.business, size: 80, color: Theme.of(context).iconTheme.color),
        ],
      ),
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


    return Scaffold(
      extendBodyBehindAppBar: true, 
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
          // Header (Titel und Logo)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildHeaderWithLogo(context, 'Verwarnungen'), // Use the common header widget
          ),
          // Main content area, pushed down to clear the header
          Padding(
            padding: const EdgeInsets.only(top: 110.0, left: 20.0, right: 20.0), // Consistent top padding for all main content
            child: SafeArea( // Ensure content is within safe area
              child: !_userHasRequiredRole(['Administrator', 'Verwarner'])
                  ? // User DOES NOT have required role (Access Denied)
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center, // Vertically center the content
                      children: [
                        Icon(Icons.lock_outline, size: 60, color: Theme.of(context).disabledColor),
                        const SizedBox(height: 20),
                        Text(
                          'Um hierdrauf zugreifen zu Können, brauchst du die Rolle Verwarner oder Administrator. Bei Bedarf kannst du diese beim Organisator erfragen.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 18, color: Theme.of(context).textTheme.bodyLarge?.color),
                        ),
                      ],
                    )
                  : // User HAS required role (proceed with loading/error/main content)
                    _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _errorMessage != null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center, // Vertically center the content
                              children: [
                                Icon(Icons.error_outline, color: Colors.red, size: 48),
                                const SizedBox(height: 10),
                                Text(
                                  _errorMessage!,
                                  style: GoogleFonts.inter(color: Colors.red, fontSize: 16),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton(
                                  onPressed: () => _fetchPageData(fetchWarnings: true), // Re-fetch all data on retry
                                  child: const Text('Erneut versuchen'),
                                ),
                              ],
                            )
                          : LayoutBuilder( // Hinzugefügter LayoutBuilder
                              builder: (context, constraints) {
                                return SingleChildScrollView( // Main content if user has role and no error
                                  child: ConstrainedBox( // Hinzugefügte ConstrainedBox
                                    constraints: BoxConstraints(
                                      minHeight: constraints.maxHeight - 100.0, // Mindesthöhe = Bildschirmhöhe - Headerhöhe - Padding
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Section for adding new warning
                                        Card(
                                          margin: const EdgeInsets.only(bottom: 24.0),
                                          elevation: 4,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                                          color: isDarkMode ? Colors.black : Colors.white, // Hintergrundfarbe der Karte
                                          child: Padding(
                                            padding: const EdgeInsets.all(16.0),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Neue Verwarnung hinzufügen',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                    color: Theme.of(context).textTheme.headlineMedium?.color,
                                                  ),
                                                ),
                                                const SizedBox(height: 16),
                                                DropdownButtonFormField<StandForDropdown>(
                                                  value: _selectedStandForNewWarning,
                                                  decoration: InputDecoration(
                                                    labelText: 'Stand auswählen:',
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                                    filled: true,
                                                    fillColor: isDarkMode
                                                        ? Colors.black.withOpacity(0.7)
                                                        : Colors.white.withOpacity(0.7),
                                                    labelStyle: GoogleFonts.inter(
                                                      color: isDarkMode ? Colors.white70 : Colors.black87,
                                                    ),
                                                    hintStyle: GoogleFonts.inter(
                                                      color: isDarkMode ? Colors.white54 : Colors.black54,
                                                    ),
                                                  ),
                                                  hint: Text('Bitte Stand auswählen', style: GoogleFonts.inter()),
                                                  isExpanded: true,
                                                  items: _standsForDropdown.map((stand) {
                                                    return DropdownMenuItem<StandForDropdown>(
                                                      value: stand,
                                                      child: Text(stand.name, style: GoogleFonts.inter()),
                                                    );
                                                  }).toList(),
                                                  onChanged: (StandForDropdown? newValue) {
                                                    setState(() {
                                                      _selectedStandForNewWarning = newValue;
                                                    });
                                                  },
                                                ),
                                                const SizedBox(height: 16),
                                                TextField(
                                                  controller: _newWarningCommentController,
                                                  decoration: InputDecoration(
                                                    labelText: 'Kommentar für die Verwarnung',
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                    isDense: true,
                                                    filled: true,
                                                    fillColor: isDarkMode
                                                        ? Colors.black.withOpacity(0.7)
                                                        : Colors.white.withOpacity(0.7),
                                                    labelStyle: GoogleFonts.inter(
                                                      color: isDarkMode ? Colors.white70 : Colors.black87,
                                                    ),
                                                    hintStyle: GoogleFonts.inter(
                                                      color: isDarkMode ? Colors.white54 : Colors.black54,
                                                    ),
                                                  ),
                                                  maxLines: 3,
                                                  style: GoogleFonts.inter(),
                                                ),
                                                const SizedBox(height: 16),
                                                Center(
                                                  child: ElevatedButton(
                                                    onPressed: _isLoading ? null : _submitNewWarning,
                                                    child: const Text('Verwarnung hinzufügen'),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),

                                        // Section for all warnings
                                        Text(
                                          'Alle Verwarnungen',
                                          style: GoogleFonts.inter(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context).textTheme.headlineLarge?.color,
                                          ),
                                        ),
                                        const SizedBox(height: 20),

                                        if (_groupedWarnings.isEmpty)
                                          Center(
                                            child: Text(
                                              'Keine Verwarnungen gefunden.',
                                              style: GoogleFonts.inter(fontSize: 16, color: Colors.grey[600]),
                                            ),
                                          )
                                        else
                                          ListView.builder(
                                            shrinkWrap: true,
                                            physics: const NeverScrollableScrollPhysics(),
                                            itemCount: _groupedWarnings.length,
                                            itemBuilder: (context, index) {
                                              final groupedWarning = _groupedWarnings[index];
                                              return Card(
                                                margin: const EdgeInsets.only(bottom: 16.0),
                                                elevation: 4,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                                                color: isDarkMode ? Colors.black : Colors.white, // Hintergrundfarbe der Karte
                                                child: Padding(
                                                  padding: const EdgeInsets.all(16.0),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        '${groupedWarning.standName} (${groupedWarning.totalWarnings} gültige Verwarnungen)',
                                                        style: GoogleFonts.inter(
                                                          fontSize: 20,
                                                          fontWeight: FontWeight.bold,
                                                          color: Theme.of(context).textTheme.headlineMedium?.color,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 16),
                                                      // List individual warnings for this stand
                                                      if (groupedWarning.warnings.isEmpty)
                                                        Padding(
                                                          padding: const EdgeInsets.only(left: 8.0),
                                                          child: Text(
                                                            'Keine spezifischen Verwarnungen.',
                                                            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
                                                          ),
                                                        )
                                                      else
                                                        ...groupedWarning.warnings.map((warning) {
                                                          // Format the warning timestamp
                                                          String formattedTimestamp = 'N/A';
                                                          try {
                                                            final DateTime parsedTimestamp = DateTime.parse(warning.timestamp);
                                                            formattedTimestamp = DateFormat('dd.MM.yyyy - HH:mm').format(parsedTimestamp.toLocal()); // Corrected format
                                                          } catch (e) {
                                                            print('Error parsing warning timestamp: $e');
                                                            formattedTimestamp = 'Ungültiges Datum';
                                                          }

                                                          // Format the invalidation timestamp
                                                          String formattedInvalidationTimestamp = 'N/A';
                                                          if (warning.invalidationTimestamp != null) {
                                                            try {
                                                              final DateTime parsedInvalidationTimestamp = DateTime.parse(warning.invalidationTimestamp!);
                                                              formattedInvalidationTimestamp = DateFormat('dd.MM.yyyy - HH:mm').format(parsedInvalidationTimestamp.toLocal()); // Corrected format
                                                            } catch (e) {
                                                              print('Error parsing invalidation timestamp: $e');
                                                              formattedInvalidationTimestamp = 'Ungültiges Datum';
                                                            }
                                                          }


                                                          return Padding(
                                                            padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                Row(
                                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                                  children: [
                                                                    Expanded(
                                                                      child: Text(
                                                                        'Verwarner: ${warning.warnerName} am $formattedTimestamp', // Use formattedTimestamp
                                                                        style: GoogleFonts.inter(
                                                                          fontSize: 14,
                                                                          fontWeight: FontWeight.w600,
                                                                          color: warning.isInvalidated ? Colors.grey : Theme.of(context).textTheme.bodyLarge?.color,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    if (warning.isInvalidated)
                                                                      Icon(Icons.check_circle_outline, color: Colors.grey, size: 18),
                                                                    if (!warning.isInvalidated && _userHasRequiredRole(['Administrator', 'Verwarner']))
                                                                      PopupMenuButton<String>(
                                                                        onSelected: (String result) {
                                                                          if (result == 'invalidate') {
                                                                            _showInvalidateWarningDialog(warning);
                                                                          }
                                                                        },
                                                                        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                                                          PopupMenuItem<String>(
                                                                            value: 'invalidate',
                                                                            child: Text('Ungültig machen', style: GoogleFonts.inter()),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    if (warning.isInvalidated && _userHasRequiredRole(['Administrator', 'Verwarner']))
                                                                      PopupMenuButton<String>(
                                                                        onSelected: (String result) {
                                                                          if (result == 'make_valid') {
                                                                            _makeWarningValid(warning.id);
                                                                          }
                                                                        },
                                                                        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                                                          PopupMenuItem<String>(
                                                                            value: 'make_valid',
                                                                            child: Text('Gültig machen', style: GoogleFonts.inter()),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                  ],
                                                                ),
                                                                const SizedBox(height: 4),
                                                                Text(
                                                                  'Kommentar: ${warning.comment}',
                                                                  style: GoogleFonts.inter(
                                                                    fontSize: 14,
                                                                    fontStyle: warning.isInvalidated ? FontStyle.italic : FontStyle.normal,
                                                                    color: warning.isInvalidated ? Colors.grey : Theme.of(context).textTheme.bodyMedium?.color,
                                                                  ),
                                                                ),
                                                                if (warning.isInvalidated)
                                                                  Column(
                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                    children: [
                                                                      const SizedBox(height: 4),
                                                                      Text(
                                                                        'Ungültig gemacht von: ${warning.invalidatedByUserName ?? 'N/A'}',
                                                                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
                                                                      ),
                                                                      Text(
                                                                        'Kommentar zur Ungültigmachung: ${warning.invalidationComment ?? 'N/A'}',
                                                                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
                                                                      ),
                                                                      Text(
                                                                        'Ungültig gemacht am: $formattedInvalidationTimestamp', // Use formattedInvalidationTimestamp
                                                                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                const Divider(height: 16),
                                                              ],
                                                            ),
                                                          );
                                                        }).toList(),
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
          ),
        ],
      ),
    );
  }
}
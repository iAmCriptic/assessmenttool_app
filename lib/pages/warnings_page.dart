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

  bool _isLoading = true;
  String? _errorMessage;

  List<StandForDropdown> _standsForDropdown = [];
  List<GroupedWarning> _groupedWarnings = [];

  StandForDropdown? _selectedStandForNewWarning;
  final TextEditingController _newWarningCommentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSessionCookie().then((_) {
      _loadUserRole().then((_) {
        if (_userHasRequiredRole(['Administrator', 'Verwarner'])) {
          _fetchWarningsData();
        } else {
          setState(() {
            _isLoading = false;
          });
        }
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

  /// Fetches warning data from the Flask backend.
  Future<void> _fetchWarningsData() async {
    await _loadUserRole(); // Ensure role is up-to-date

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (!_userHasRequiredRole(['Administrator', 'Verwarner'])) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Sie haben keine Berechtigung, auf diese Seite zuzugreifen.';
      });
      return;
    }

    try {
      final headers = _getAuthHeaders();
      // CORRECTED URL: Added '/warnings' blueprint prefix
      final response = await http.get(
        Uri.parse('${widget.serverAddress}/warnings/api/warnings_data'), // Corrected URL
        headers: headers,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
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
      } else {
        _errorMessage = 'Fehler ${response.statusCode}: ${response.reasonPhrase}';
      }
    } catch (e) {
      _errorMessage = 'Verbindungsfehler: $e';
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
      // URL is already correct for the blueprint root, so no change needed here
      final response = await http.post(
        Uri.parse('${widget.serverAddress}/warnings/'), // This is correct, as per warnings.py route '/'
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
          _fetchWarningsData(); // Refresh data
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
      // CORRECTED URL: Added '/warnings' blueprint prefix
      final response = await http.post(
        Uri.parse('${widget.serverAddress}/warnings/invalidate_warning/$warningId'), // Corrected URL
        headers: headers,
        body: json.encode({'invalidation_comment': comment}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        _showAlertDialog('Erfolg', data['message'] ?? 'Verwarnung erfolgreich als ungültig markiert.');
        _fetchWarningsData(); // Refresh data
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
      // CORRECTED URL: Added '/warnings' blueprint prefix
      final response = await http.post(
        Uri.parse('${widget.serverAddress}/warnings/make_warning_valid/$warningId'), // Corrected URL
        headers: headers,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        _showAlertDialog('Erfolg', data['message'] ?? 'Verwarnung erfolgreich als gültig markiert.');
        _fetchWarningsData(); // Refresh data
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

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    if (!_userHasRequiredRole(['Administrator', 'Verwarner'])) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Verwarnungen',
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
                  'Um hierdrauf zugreifen zu Können, brauchst du die Rolle Verwarner oder Administrator. Bei Bedarf kannst du diese beim Organisator erfragen.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 18, color: Theme.of(context).textTheme.bodyLarge?.color),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isLoading) {
      return Scaffold(
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Verwarnungen',
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
                  onPressed: _fetchWarningsData,
                  child: const Text('Erneut versuchen'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _fetchWarningsData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
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
                        'Verwarnungen',
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

              // Section for adding new warning
              Card(
                margin: const EdgeInsets.only(bottom: 24.0),
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                color: isDarkMode ? Colors.black : Theme.of(context).cardColor,
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
                      color: isDarkMode ? Colors.black : Theme.of(context).cardColor,
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
                                              'Verwarner: ${warning.warnerName} am ${warning.timestamp}',
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
                                              'Ungültig gemacht am: ${warning.invalidationTimestamp ?? 'N/A'}',
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
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme_manager.dart'; // Adjust path if necessary
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // For session cookie and user role

/// Represents a Criterion for display and management.
class Criterion {
  final int id;
  final String name;
  final int maxScore;
  final String? description;

  Criterion({
    required this.id,
    required this.name,
    required this.maxScore,
    this.description,
  });

  factory Criterion.fromJson(Map<String, dynamic> json) {
    return Criterion(
      id: json['id'],
      name: json['name'],
      maxScore: json['max_score'],
      description: json['description'],
    );
  }
}

/// The page for managing criteria.
class ManageCriteriaPage extends StatefulWidget {
  final String serverAddress;
  const ManageCriteriaPage({super.key, required this.serverAddress});

  @override
  State<ManageCriteriaPage> createState() => _ManageCriteriaPageState();
}

class _ManageCriteriaPageState extends State<ManageCriteriaPage> {
  // State variables for dynamic gradient colors from server
  Color _gradientColor1 = Colors.blue.shade50; // Default light mode start color
  Color _gradientColor2 = Colors.blue.shade200; // Default light mode end color
  Color _darkGradientColor1 = Colors.black; // Default dark mode start color
  Color _darkGradientColor2 = Colors.blueGrey; // Default dark mode end color

  bool _isLoading = true;
  String? _errorMessage;
  List<Criterion> _criteria = [];
  String? _sessionCookie; // Stores the session cookie for authenticated requests
  String? _userRole; // Stores the current user's role

  // Controllers for creating a new criterion
  final TextEditingController _newCriterionNameController = TextEditingController();
  final TextEditingController _newMaxScoreController = TextEditingController();
  final TextEditingController _newCriterionDescriptionController = TextEditingController();

  // Controllers for editing an existing criterion
  final TextEditingController _editCriterionNameController = TextEditingController();
  final TextEditingController _editMaxScoreController = TextEditingController();
  final TextEditingController _editCriterionDescriptionController = TextEditingController();
  Criterion? _criterionToEdit; // Stores the criterion currently being edited

  @override
  void initState() {
    super.initState();
    _loadSessionCookie().then((_) {
      _loadUserRole().then((_) {
        _fetchPageData(); // Load data after roles are loaded
      });
    });
  }

  @override
  void dispose() {
    _newCriterionNameController.dispose();
    _newMaxScoreController.dispose();
    _newCriterionDescriptionController.dispose();
    _editCriterionNameController.dispose();
    _editMaxScoreController.dispose();
    _editCriterionDescriptionController.dispose();
    super.dispose();
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

  /// Fetches all necessary data for the page (criteria and app settings).
  Future<void> _fetchPageData() async {
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

      final Future<http.Response> criteriaFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/criteria'), headers: headers);
      final Future<http.Response> adminSettingsFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/admin_settings'), headers: headers);

      final List<http.Response> responses =
          await Future.wait([criteriaFuture, adminSettingsFuture]);

      // Process Criteria Response
      final criteriaResponse = responses[0];
      print('DEBUG (Flutter): Criteria API response status: ${criteriaResponse.statusCode}');
      print('DEBUG (Flutter): Criteria API response body: ${criteriaResponse.body}');
      if (criteriaResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(criteriaResponse.body);
        if (data['success']) {
          _criteria = (data['criteria'] as List).map((c) => Criterion.fromJson(c)).toList();
        } else {
          _errorMessage = data['message'] ?? 'Fehler beim Laden der Kriterien.';
        }
      } else {
        _errorMessage =
            'Fehler ${criteriaResponse.statusCode}: ${criteriaResponse.reasonPhrase}';
        print('Error fetching criteria: ${criteriaResponse.statusCode} - ${criteriaResponse.body}');
      }

      // Process Admin Settings Response
      final adminSettingsResponse = responses[1];
      print('DEBUG (Flutter): Admin Settings API response status: ${adminSettingsResponse.statusCode}');
      print('DEBUG (Flutter): Admin Settings API response body: ${adminSettingsResponse.body}');
      if (adminSettingsResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(adminSettingsResponse.body);
        if (data['success'] && data.containsKey('settings')) {
          setState(() {
            _gradientColor1 =
                _hexToColor(data['settings']['bg_gradient_color1'] ?? '#E3F2FD');
            _gradientColor2 =
                _hexToColor(data['settings']['bg_gradient_color2'] ?? '#BBDEFB');
            _darkGradientColor1 =
                _hexToColor(data['settings']['dark_bg_gradient_color1'] ?? '#000000');
            _darkGradientColor2 =
                _hexToColor(data['settings']['dark_bg_gradient_color2'] ?? '#455A64');
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

  /// Creates a new criterion.
  Future<void> _createCriterion() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (_newCriterionNameController.text.isEmpty || _newMaxScoreController.text.isEmpty) {
      _showAlertDialog('Fehler', 'Bitte gib einen Kriteriennamen und eine maximale Punktzahl ein.');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final int? maxScore = int.tryParse(_newMaxScoreController.text.trim());
    if (maxScore == null) {
      _showAlertDialog('Fehler', 'Maximale Punktzahl muss eine gültige Zahl sein.');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final headers = _getAuthHeaders();
    final requestBody = json.encode({
      'name': _newCriterionNameController.text.trim(),
      'max_score': maxScore,
      'description': _newCriterionDescriptionController.text.trim(),
    });
    print('DEBUG (Flutter): Sending create criterion request body: $requestBody');

    try {
      final response = await http.post(
        Uri.parse('${widget.serverAddress}/api/criteria'),
        headers: headers,
        body: requestBody,
      );

      final Map<String, dynamic> data = json.decode(response.body);
      print('DEBUG (Flutter): Create criterion response status: ${response.statusCode}');
      print('DEBUG (Flutter): Create criterion response body: ${response.body}');
      if (response.statusCode == 201 && data['success']) {
        _showAlertDialog('Erfolg', data['message']);
        _newCriterionNameController.clear();
        _newMaxScoreController.clear();
        _newCriterionDescriptionController.clear();
        _fetchPageData(); // Refresh criterion list
      } else {
        _showAlertDialog('Fehler', data['message'] ?? 'Fehler beim Anlegen des Kriteriums.');
      }
    } catch (e) {
      _showAlertDialog('Verbindungsfehler', 'Fehler beim Anlegen des Kriteriums: $e');
      print('ERROR (Flutter): Exception creating criterion: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Edits an existing criterion.
  Future<void> _editCriterion() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (_criterionToEdit == null || _editCriterionNameController.text.isEmpty || _editMaxScoreController.text.isEmpty) {
      _showAlertDialog('Fehler', 'Bitte gib einen Kriteriennamen und eine maximale Punktzahl ein.');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final int? maxScore = int.tryParse(_editMaxScoreController.text.trim());
    if (maxScore == null) {
      _showAlertDialog('Fehler', 'Maximale Punktzahl muss eine gültige Zahl sein.');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final headers = _getAuthHeaders();
    final requestBody = json.encode({
      'name': _editCriterionNameController.text.trim(),
      'max_score': maxScore,
      'description': _editCriterionDescriptionController.text.trim(),
    });
    print('DEBUG (Flutter): Sending edit criterion request body: $requestBody');

    try {
      final response = await http.put(
        Uri.parse('${widget.serverAddress}/api/criteria/${_criterionToEdit!.id}'),
        headers: headers,
        body: requestBody,
      );

      final Map<String, dynamic> data = json.decode(response.body);
      print('DEBUG (Flutter): Edit criterion response status: ${response.statusCode}');
      print('DEBUG (Flutter): Edit criterion response body: ${response.body}');
      if (response.statusCode == 200 && data['success']) {
        _showAlertDialog('Erfolg', data['message']).then((_) {
          Navigator.of(context).pop(); // Close modal after alert is dismissed
        });
        _fetchPageData(); // Refresh criterion list
      } else {
        _showAlertDialog('Fehler', data['message'] ?? 'Fehler beim Aktualisieren des Kriteriums.');
      }
    } catch (e) {
      _showAlertDialog('Verbindungsfehler', 'Fehler beim Aktualisieren des Kriteriums: $e');
      print('ERROR (Flutter): Exception editing criterion: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Deletes a criterion.
  Future<void> _deleteCriterion(int criterionId, String criterionName) async {
    final bool confirmDelete = await _showConfirmationDialog(
        'Kriterium löschen', 'Möchten Sie das Kriterium "$criterionName" wirklich löschen?');
    if (!confirmDelete) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final headers = _getAuthHeaders();
    print('DEBUG (Flutter): Sending delete criterion request for ID: $criterionId');

    try {
      final response = await http.delete(
        Uri.parse('${widget.serverAddress}/api/criteria/$criterionId'),
        headers: headers,
      );

      final Map<String, dynamic> data = json.decode(response.body);
      print('DEBUG (Flutter): Delete criterion response status: ${response.statusCode}');
      print('DEBUG (Flutter): Delete criterion response body: ${response.body}');
      if (response.statusCode == 200 && data['success']) {
        _showAlertDialog('Erfolg', data['message']);
        _fetchPageData(); // Refresh criterion list
      } else {
        _showAlertDialog('Fehler', data['message'] ?? 'Fehler beim Löschen des Kriteriums.');
      }
    } catch (e) {
      _showAlertDialog('Verbindungsfehler', 'Fehler beim Löschen des Kriteriums: $e');
      print('ERROR (Flutter): Exception deleting criterion: $e');
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
  Future<bool> _showConfirmationDialog(String title, String message) async {
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
                  child: Text('Bestätigen', style: GoogleFonts.inter()),
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            );
          },
        ) ??
        false; // Returns false if dialog is dismissed
  }

  /// Shows the edit criterion modal with pre-filled data.
  void _showEditCriterionModal(Criterion criterion) {
    setState(() {
      _criterionToEdit = criterion;
      _editCriterionNameController.text = criterion.name;
      _editMaxScoreController.text = criterion.maxScore.toString();
      _editCriterionDescriptionController.text = criterion.description ?? '';
    });

    showDialog(
      context: context,
      builder: (BuildContext context) {
        final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDarkMode ? Colors.black : Colors.white,
          title: Text(
              'Kriterium bearbeiten: ${criterion.name}',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.headlineMedium?.color)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _editCriterionNameController,
                  decoration: InputDecoration(
                    labelText: 'Kriterienname',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  style: GoogleFonts.inter(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _editMaxScoreController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Max. Punktzahl',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  style: GoogleFonts.inter(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _editCriterionDescriptionController,
                  decoration: InputDecoration(
                    labelText: 'Beschreibung (optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  maxLines: 3, // Multiple lines for description
                  style: GoogleFonts.inter(),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 100, // Fixed width
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: Text('Abbrechen',
                            style: GoogleFonts.inter(
                                fontSize: 14,
                                color: isDarkMode ? Colors.white70 : Colors.black87)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100, // Fixed width
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _editCriterion,
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          textStyle: GoogleFonts.inter(fontSize: 14),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                            : Text('Speichern', style: GoogleFonts.inter(fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Displays a modal for the full description.
  void _showFullDescriptionModal(String description) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDarkMode ? Colors.black : Colors.white,
          title: Text('Vollständige Beschreibung',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.headlineMedium?.color)),
          content: SingleChildScrollView(
            child: Text(
              description,
              style: GoogleFonts.inter(
                  color: Theme.of(context).textTheme.bodyLarge?.color),
            ),
          ),
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
                            'Kriterienverwaltung',
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
                      'Kriterienverwaltung',
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
          RefreshIndicator(
            onRefresh: _fetchPageData,
            child: SingleChildScrollView(
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
                            'Kriterienverwaltung',
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

                  // Section "Create New Criterion"
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0)),
                    color: isDarkMode ? Colors.black : Colors.white,
                    margin: const EdgeInsets.only(bottom: 24.0),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Neues Kriterium anlegen',
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.headlineMedium?.color,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _newCriterionNameController,
                            decoration: InputDecoration(
                              labelText: 'Kriterienname',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            style: GoogleFonts.inter(),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _newMaxScoreController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Max. Punktzahl',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            style: GoogleFonts.inter(),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _newCriterionDescriptionController,
                            decoration: InputDecoration(
                              labelText: 'Beschreibung (optional)',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            maxLines: 3,
                            style: GoogleFonts.inter(),
                          ),
                          const SizedBox(height: 24),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : _createCriterion,
                              icon: const Icon(Icons.add_circle_outline),
                              label: Text('Kriterium anlegen',
                                  style: GoogleFonts.inter(fontSize: 16)),
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Section "Existing Criteria"
                  Text(
                    'Vorhandene Kriterien',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.headlineLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_criteria.isEmpty)
                    Center(
                      child: Text(
                        'Keine Kriterien gefunden.',
                        style: GoogleFonts.inter(fontSize: 16, color: Colors.grey[600]),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _criteria.length,
                      itemBuilder: (context, index) {
                        final criterion = _criteria[index];
                        String displayDescription = criterion.description ?? 'N/A';
                        bool needsReadMore = false;
                        const int maxChars = 50; // Max characters for truncated display

                        if (displayDescription.length > maxChars) {
                          displayDescription = displayDescription.substring(0, maxChars) + '...';
                          needsReadMore = true;
                        }

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12.0),
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10.0)),
                          color: isDarkMode ? Colors.black : Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  criterion.name,
                                  style: GoogleFonts.inter(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).textTheme.headlineMedium?.color,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Max. Punktzahl: ${criterion.maxScore}',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    color: Theme.of(context).textTheme.bodyLarge?.color,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Beschreibung: $displayDescription',
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          color: Theme.of(context).textTheme.bodyLarge?.color,
                                        ),
                                      ),
                                    ),
                                    if (needsReadMore)
                                      TextButton(
                                        onPressed: () => _showFullDescriptionModal(criterion.description!),
                                        child: Text(
                                          'Mehr lesen',
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            color: Theme.of(context).primaryColor,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () => _showEditCriterionModal(criterion),
                                      tooltip: 'Kriterium bearbeiten',
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteCriterion(criterion.id, criterion.name),
                                      tooltip: 'Kriterium löschen',
                                    ),
                                  ],
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
          ),
        ],
      ),
    );
  }
}

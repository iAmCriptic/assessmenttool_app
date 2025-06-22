import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart'; // For session cookie and user role
import 'package:intl/intl.dart'; // For date formatting

/// Represents a Stand that can be evaluated.
class Stand {
  final int id;
  final String name;
  final String? roomName;
  final String? description; // Stand description

  Stand({required this.id, required this.name, this.roomName, this.description});

  factory Stand.fromJson(Map<String, dynamic> json) {
    return Stand(
      id: json['id'],
      name: json['name'],
      roomName: json['room_name'],
      description: json['description'], // Parse description
    );
  }
}

/// Represents an evaluation criterion.
class Criterion {
  final int id;
  final String name;
  final String description; // Description can contain simple HTML tags
  final int maxScore;

  Criterion({required this.id, required this.name, required this.description, required this.maxScore});

  factory Criterion.fromJson(Map<String, dynamic> json) {
    return Criterion(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      maxScore: json['max_score'],
    );
  }
}

/// The 'Evaluation' page where users can select a stand and submit scores for criteria.
class EvaluationPage extends StatefulWidget {
  final String serverAddress;

  const EvaluationPage({super.key, required this.serverAddress});

  @override
  State<EvaluationPage> createState() => _EvaluationPageState();
}

class _EvaluationPageState extends State<EvaluationPage> {
  String? _userRole; // Stores the current user's role
  String? _sessionCookie; // Stores the session cookie for authenticated requests
  String? _logoFullPath; // To store the full path to the logo from admin settings

  bool _isLoading = true;
  String? _errorMessage;

  List<Stand> _stands = [];
  List<Criterion> _criteria = [];
  Stand? _selectedStand;
  final Map<int, TextEditingController> _scoreControllers = {}; // Controllers for score inputs
  
  // Stores existing evaluation scores for the selected stand
  final Map<int, int> _existingScores = {}; 
  String? _lastEvaluationTimestamp;

  // State variables for dynamic gradient colors from the server
  Color _gradientColor1 = Colors.blue.shade50; // Default Light Mode Start Color
  Color _gradientColor2 = Colors.blue.shade200; // Default Light Mode End Color
  Color _darkGradientColor1 = Colors.black; // Default Dark Mode Start Color
  Color _darkGradientColor2 = Colors.blueGrey; // Default Dark Mode End Color

  @override
  void initState() {
    super.initState();
    _loadSessionCookie().then((_) {
      _loadUserRole().then((_) { // Load user role on init
        // Fetch initial data only if user has access roles
        // This ensures gradient colors and logo path are fetched even if user has no access initially
        _fetchPageData(); 
      });
    });
  }

  @override
  void dispose() {
    // Remove listeners from controllers before disposing
    _scoreControllers.forEach((id, controller) => controller.removeListener(_updateSubmitButtonState));
    _scoreControllers.forEach((id, controller) => controller.dispose());
    super.dispose();
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

  /// Converts a Hex color string (e.g., "#RRGGBB") to a Flutter Color object.
  Color _hexToColor(String hexString) {
    final String hex = hexString.replaceAll('#', '');
    return Color(int.parse('ff$hex', radix: 16));
  }

  /// Extracts the base host from a given URL, removing protocol, port, and subdomains.
  String _getBaseHost(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;

      if (RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host)) {
        return host;
      }

      final parts = host.split('.');
      if (parts.length >= 2) {
        return '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
      }
      return host;
    } catch (e) {
      print('Error parsing URL for base host: $e');
      return url;
    }
  }

  /// Fetches all necessary data for the page (stands, criteria, and app settings).
  Future<void> _fetchPageData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final headers = _getAuthHeaders();

      final Future<http.Response> initialDataFuture;
      if (_userHasRequiredRole(['Administrator', 'Bewerter'])) {
        initialDataFuture = http.get(Uri.parse('${widget.serverAddress}/api/evaluate_initial_data'), headers: headers);
      } else {
        // Return a dummy response for initialDataFuture if user doesn't have access
        initialDataFuture = Future.value(http.Response('{"success": false, "message": "Keine Berechtigung"}', 403));
      }
      
      final Future<http.Response> adminSettingsFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/admin_settings'), headers: headers);

      final List<http.Response> responses = await Future.wait([initialDataFuture, adminSettingsFuture]);

      // Process Initial Data (Stands and Criteria)
      final initialDataResponse = responses[0];
      if (initialDataResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(initialDataResponse.body);
        if (data['success']) {
          setState(() {
            _stands = (data['stands'] as List).map((s) => Stand.fromJson(s)).toList();
            _criteria = (data['criteria'] as List).map((c) => Criterion.fromJson(c)).toList();
            // Initialize controllers
            _scoreControllers.forEach((id, controller) => controller.removeListener(_updateSubmitButtonState)); // Remove old listeners
            _scoreControllers.clear(); // Clear old controllers if any
            for (var criterion in _criteria) {
              _scoreControllers[criterion.id] = TextEditingController();
              _scoreControllers[criterion.id]?.addListener(_updateSubmitButtonState);
            }
            // Reset selected stand and existing scores
            _selectedStand = null;
            _existingScores.clear();
            _lastEvaluationTimestamp = null;
          });
        } else {
          _errorMessage = data['message'] ?? 'Fehler beim Laden der Initialdaten.';
        }
      } else if (initialDataResponse.statusCode == 403) {
        _errorMessage = 'Sie haben keine Berechtigung, auf diese Seite zuzugreifen.';
      } else {
        _errorMessage = 'Fehler ${initialDataResponse.statusCode}: ${initialDataResponse.reasonPhrase}';
        print('Error fetching initial data: ${initialDataResponse.statusCode} - ${initialDataResponse.body}');
      }

      // Process Admin Settings (for gradient and logo)
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
        _updateSubmitButtonState(); // Initial check for button state
      });
    }
  }

  /// Fetches existing scores for the currently selected stand by the current user.
  Future<void> _fetchExistingScores(int standId) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final headers = _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${widget.serverAddress}/api/evaluations/user_scores/$standId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] && data['exists']) {
          setState(() {
            _existingScores.clear();
            (data['scores'] as Map<String, dynamic>).forEach((key, value) {
              _existingScores[int.parse(key)] = value;
            });
            
            // Parse and format the timestamp, handling different ISO 8601 variations
            if (data['timestamp'] != null) {
              try {
                // Ensure the timestamp is treated as UTC if it comes with +00:00 or Z
                final DateTime parsedTimestamp = DateTime.parse(data['timestamp']).toUtc();
                _lastEvaluationTimestamp = DateFormat('dd.MM.yyyy - HH:mm').format(parsedTimestamp.toLocal());
              } catch (e) {
                print('Warning: Could not parse timestamp directly. Attempting custom parse: $e');
                // Fallback: If parsing fails, display the raw string for debugging
                _lastEvaluationTimestamp = data['timestamp'].toString(); 
              }
            } else {
              _lastEvaluationTimestamp = null;
            }

            // Populate controllers with existing scores
            for (var criterion in _criteria) {
              _scoreControllers[criterion.id]?.text = (_existingScores[criterion.id] ?? '').toString();
            }
          });
        } else {
          // No existing evaluation found for this stand
          setState(() {
            _existingScores.clear();
            _lastEvaluationTimestamp = null;
            // Clear all controllers when a new stand is selected or no existing evaluation
            for (var criterion in _criteria) {
              _scoreControllers[criterion.id]?.clear();
            }
          });
        }
      } else {
        _errorMessage = 'Fehler beim Laden bestehender Bewertungen: ${response.statusCode} - ${response.reasonPhrase}';
        print('Error fetching existing scores: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _errorMessage = 'Verbindungsfehler beim Laden bestehender Bewertungen: $e';
      print('Exception fetching existing scores: $e');
    } finally {
      setState(() {
        _isLoading = false;
        _updateSubmitButtonState(); // Update button state after fetching scores
      });
    }
  }

  /// Checks if all required fields are filled for the submit button to be enabled.
  bool _canSubmitEvaluation() {
    if (_selectedStand == null) {
      return false;
    }
    // Check if all score fields are filled and valid
    for (final criterion in _criteria) {
      final text = _scoreControllers[criterion.id]?.text;
      if (text == null || text.trim().isEmpty) {
        return false; // Field is empty
      }
      final score = int.tryParse(text);
      if (score == null || score < 0 || score > criterion.maxScore) {
        return false; // Invalid score (e.g., not a number, or out of range)
      }
    }
    return true;
  }

  /// Updates the state to enable/disable the submit button.
  void _updateSubmitButtonState() {
    // This will trigger a rebuild and re-evaluate _canSubmitEvaluation()
    setState(() {}); 
  }

  /// Submits the evaluation scores to the Flask backend.
  Future<void> _submitEvaluation() async {
    if (!_canSubmitEvaluation()) {
      _showAlertDialog('Fehler', 'Bitte fülle alle Bewertungsfelder korrekt aus.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final Map<String, int> scoresToSubmit = {};
    for (var criterion in _criteria) {
      final text = _scoreControllers[criterion.id]?.text;
      if (text != null && text.isNotEmpty) {
        final score = int.tryParse(text);
        if (score != null && score >= 0 && score <= criterion.maxScore) {
          scoresToSubmit[criterion.id.toString()] = score;
        } else {
          _scoreControllers[criterion.id]?.clear(); 
        }
      }
    }

    try {
      final headers = _getAuthHeaders();
      final response = await http.post(
        Uri.parse('${widget.serverAddress}/evaluate'),
        headers: headers,
        body: json.encode({
          'stand_id': _selectedStand!.id,
          'scores': scoresToSubmit,
        }),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success']) {
          _showAlertDialog('Erfolg', data['message'] ?? 'Bewertung erfolgreich gespeichert!');
          _fetchExistingScores(_selectedStand!.id); 
        } else {
          _showAlertDialog('Fehler', data['message'] ?? 'Bewertung fehlgeschlagen.');
        }
      } else {
        final Map<String, dynamic> errorData = json.decode(response.body);
        _showAlertDialog('Fehler', errorData['message'] ?? 'Ein Fehler ist aufgetreten. Status: ${response.statusCode}');
        print('Error submitting evaluation: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _showAlertDialog('Verbindungsfehler', 'Fehler beim Senden der Bewertung: $e');
      print('Exception submitting evaluation: $e');
    } finally {
      setState(() {
        _isLoading = false;
        _updateSubmitButtonState(); // Update button state after submission attempt
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
          content: RichText( // Use RichText to display parsed HTML content
            text: _parseSimpleHtmlToTextSpan(message, GoogleFonts.inter()),
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

  /// Parses a simple HTML string to a list of TextSpan for rich text display.
  /// Supports <b>, <i>, <u> tags.
  TextSpan _parseSimpleHtmlToTextSpan(String htmlText, TextStyle defaultStyle) {
    final List<TextSpan> spans = [];
    final RegExp tagRegExp = RegExp(r'<(b|i|u)>(.*?)<\/(b|i|u)>'); // Regex to find b, i, u tags

    int lastMatchEnd = 0;

    for (RegExpMatch match in tagRegExp.allMatches(htmlText)) {
      // Add text before the current tag
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: htmlText.substring(lastMatchEnd, match.start), style: defaultStyle));
      }

      final String tag = match.group(1)!;
      final String content = match.group(2)!;
      TextStyle currentStyle = defaultStyle;

      switch (tag) {
        case 'b':
          currentStyle = currentStyle.copyWith(fontWeight: FontWeight.bold);
          break;
        case 'i':
          currentStyle = currentStyle.copyWith(fontStyle: FontStyle.italic);
          break;
        case 'u':
          currentStyle = currentStyle.copyWith(decoration: TextDecoration.underline);
          break;
      }
      spans.add(TextSpan(text: content, style: currentStyle));
      lastMatchEnd = match.end;
    }

    // Add any remaining text after the last tag
    if (htmlText.length > lastMatchEnd) {
      spans.add(TextSpan(text: htmlText.substring(lastMatchEnd), style: defaultStyle));
    }

    return TextSpan(children: spans);
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
    // Determine if dark mode is enabled
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Define the gradients based on current theme brightness using fetched colors
    final Gradient backgroundGradient = isDarkMode
        ? LinearGradient(
            colors: [_darkGradientColor1, _darkGradientColor2], // Use fetched dark mode colors
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [_gradientColor1, _gradientColor2], // Use fetched light mode colors
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    // No AppBar is used anymore, the title and logo are directly in the body.
    // The Scaffold background will be the gradient.

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
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildHeaderWithLogo(context, 'Bewertung'), // Use the common header widget
          ),
          // Main content area, pushed down to clear the header
          Padding(
            padding: const EdgeInsets.only(top: 110.0, left: 20.0, right: 20.0), // Consistent top padding for all main content
            child: SafeArea( // Ensure content is within safe area
              child: !_userHasRequiredRole(['Administrator', 'Bewerter'])
                  ? // User DOES NOT have required role (Access Denied)
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center, // Vertically center the content
                      children: [
                        Icon(Icons.lock_outline, size: 60, color: Theme.of(context).disabledColor),
                        const SizedBox(height: 20),
                        Text(
                          'Um hierdrauf zugreifen zu Können, brauchst du die Rolle Bewerter. Bei Bedarf kannst du diese beim Organisator erfragen.',
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
                                  onPressed: _fetchPageData, 
                                  child: const Text('Try again'),
                                ),
                              ],
                            )
                          : SingleChildScrollView( // Main content if user has role and no error
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Stand Selection
                                  DropdownButtonFormField<Stand>(
                                    value: _selectedStand,
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
                                    items: _stands.map((stand) {
                                      return DropdownMenuItem<Stand>(
                                        value: stand,
                                        child: Text(
                                          '${stand.name} (${stand.roomName ?? "Kein Raum"})',
                                          style: GoogleFonts.inter(
                                            color: isDarkMode ? Colors.white : Colors.black87, 
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (Stand? newValue) {
                                      setState(() {
                                        _selectedStand = newValue;
                                        _existingScores.clear();
                                        _lastEvaluationTimestamp = null;
                                        for (var criterion in _criteria) {
                                          _scoreControllers[criterion.id]?.clear();
                                        }

                                        if (newValue != null) {
                                          _fetchExistingScores(newValue.id); 
                                        }
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 20),

                                  // Stand Description
                                  if (_selectedStand != null)
                                    Card(
                                      margin: EdgeInsets.zero, 
                                      elevation: 2,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      color: isDarkMode ? Colors.black : Colors.white, 
                                      child: Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (_selectedStand!.description != null && _selectedStand!.description!.trim().isNotEmpty)
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Beschreibung:',
                                                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).textTheme.bodyLarge?.color),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  RichText(
                                                    text: _parseSimpleHtmlToTextSpan(
                                                      _selectedStand!.description!,
                                                      GoogleFonts.inter(fontSize: 14, color: Theme.of(context).textTheme.bodyLarge?.color),
                                                    ),
                                                  ),
                                                ],
                                              )
                                            else
                                              Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 10.0),
                                                child: Text(
                                                  'Keine Beschreibung für diesen Stand verfügbar.',
                                                  style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
                                                ),
                                              ),
                                            
                                            if (_lastEvaluationTimestamp != null) ...[
                                              const SizedBox(height: 16), 
                                              Text(
                                                'Zuletzt bewertet: $_lastEvaluationTimestamp',
                                                style: GoogleFonts.inter(fontSize: 14, color: Colors.blueAccent),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 20),

                                  // Criteria Inputs
                                  ListView.builder(
                                    shrinkWrap: true, 
                                    physics: const NeverScrollableScrollPhysics(), 
                                    itemCount: _criteria.length,
                                    itemBuilder: (context, index) {
                                      final criterion = _criteria[index];
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 16.0), 
                                        child: Card(
                                          elevation: 2,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          color: isDarkMode ? Colors.black : Colors.white, 
                                          child: Padding(
                                            padding: const EdgeInsets.all(12.0),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        '${criterion.name} (1-${criterion.maxScore}):',
                                                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                                                        overflow: TextOverflow.ellipsis, 
                                                        maxLines: 2, 
                                                      ),
                                                    ),
                                                    IconButton( 
                                                      icon: Icon(Icons.info_outline, size: 20, color: Theme.of(context).iconTheme.color),
                                                      onPressed: () {
                                                        _showAlertDialog(
                                                          criterion.name, 
                                                          criterion.description, 
                                                        );
                                                      },
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                SizedBox( 
                                                  height: 65, 
                                                  child: TextField(
                                                    controller: _scoreControllers[criterion.id],
                                                    keyboardType: TextInputType.number,
                                                    decoration: InputDecoration(
                                                      hintText: 'Punkte',
                                                      isDense: false, 
                                                      contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10), 
                                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                    ),
                                                    style: GoogleFonts.inter(),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  // Add some bottom padding to ensure content above the FAB is visible when scrolled
                                  const SizedBox(height: 100), 
                                ],
                              ),
                            ),
            ),
          ),
          // Floating Action Button - repositioned to match the screenshot
          // Only show the FAB if the user has the required role AND can submit evaluation
          if (_userHasRequiredRole(['Administrator', 'Bewerter']))
            Positioned(
              bottom: 70 +  kBottomNavigationBarHeight, // Adjust based on bottom safe area and nav bar
              right: 20, // Adjust from the right edge
              child: FloatingActionButton.extended(
                onPressed: _canSubmitEvaluation() && !_isLoading ? _submitEvaluation : null, // Disable if not all fields are filled or loading
                label: const Text('Speichern'), 
                icon: const Icon(Icons.save),
                backgroundColor: _canSubmitEvaluation() && !_isLoading ? Colors.blueAccent : Colors.grey, // Visual feedback for disabled
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)), // Rounded corners for FAB
                elevation: 6.0,
              ),
            ),
        ],
      ),
    );
  }
}

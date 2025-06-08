import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart'; // For session cookie and user role

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

  bool _isLoading = true;
  String? _errorMessage;

  List<Stand> _stands = [];
  List<Criterion> _criteria = [];
  Stand? _selectedStand;
  Map<int, TextEditingController> _scoreControllers = {}; // Controllers for score inputs
  
  // Stores existing evaluation scores for the selected stand
  Map<int, int> _existingScores = {}; 
  String? _lastEvaluationTimestamp;

  @override
  void initState() {
    super.initState();
    _loadSessionCookie().then((_) {
      _loadUserRole().then((_) {
        // Fetch initial data only if user has access roles
        if (_userHasRequiredRole(['Administrator', 'Bewerter'])) {
          _fetchInitialData();
        } else {
          setState(() {
            _isLoading = false; // Stop loading if user has no access
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _scoreControllers.forEach((id, controller) => controller.dispose());
    super.dispose();
  }

  /// Loads the session cookie from SharedPreferences.
  Future<void> _loadSessionCookie() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionCookie = prefs.getString('sessionCookie');
    // print('DEBUG (Flutter): EvaluationPage - Session cookie loaded: $_sessionCookie'); // Debug removed
  }

  /// Loads the user's role from SharedPreferences.
  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    _userRole = prefs.getString('userRole');
    // print('DEBUG (Flutter): EvaluationPage - User role loaded: $_userRole'); // Debug removed
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

  /// Fetches initial data (stands and criteria) from the Flask backend.
  Future<void> _fetchInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final headers = _getAuthHeaders();
      // print('DEBUG (Flutter): Fetching initial data from ${widget.serverAddress}/api/evaluate_initial_data with headers: $headers'); // Debug removed
      final response = await http.get(
        Uri.parse('${widget.serverAddress}/api/evaluate_initial_data'),
        headers: headers,
      );
      // print('DEBUG (Flutter): Initial data response status: ${response.statusCode}'); // Debug removed
      // print('DEBUG (Flutter): Initial data response body: ${response.body}'); // Debug removed

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            _stands = (data['stands'] as List).map((s) => Stand.fromJson(s)).toList();
            _criteria = (data['criteria'] as List).map((c) => Criterion.fromJson(c)).toList();
            // Initialize controllers
            _scoreControllers.clear(); // Clear old controllers if any
            _criteria.forEach((criterion) {
              _scoreControllers[criterion.id] = TextEditingController();
            });
            // Reset selected stand and existing scores
            _selectedStand = null;
            _existingScores.clear();
            _lastEvaluationTimestamp = null;
          });
        } else {
          _errorMessage = data['message'] ?? 'Fehler beim Laden der Initialdaten.';
        }
      } else {
        _errorMessage = 'Fehler ${response.statusCode}: ${response.reasonPhrase}';
        // print('Error fetching initial data: ${response.statusCode} - ${response.body}'); // Debug removed
      }
    } catch (e) {
      _errorMessage = 'Verbindungsfehler: $e';
      // print('Exception fetching initial data: $e'); // Debug removed
    } finally {
      setState(() {
        _isLoading = false;
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
      // print('DEBUG (Flutter): Fetching existing scores for stand $standId from ${widget.serverAddress}/api/evaluations/user_scores/$standId with headers: $headers'); // Debug removed
      final response = await http.get(
        Uri.parse('${widget.serverAddress}/api/evaluations/user_scores/$standId'),
        headers: headers,
      );
      // print('DEBUG (Flutter): Existing scores response status: ${response.statusCode}'); // Debug removed
      // print('DEBUG (Flutter): Existing scores response body: ${response.body}'); // Debug removed


      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] && data['exists']) {
          setState(() {
            _existingScores.clear();
            (data['scores'] as Map<String, dynamic>).forEach((key, value) {
              _existingScores[int.parse(key)] = value;
            });
            _lastEvaluationTimestamp = data['timestamp'];

            // Populate controllers with existing scores
            _criteria.forEach((criterion) {
              _scoreControllers[criterion.id]?.text = (_existingScores[criterion.id] ?? '').toString();
            });
            // print('DEBUG (Flutter): Loaded existing scores: $_existingScores'); // Debug removed
          });
        } else {
          // No existing evaluation found for this stand
          setState(() {
            _existingScores.clear();
            _lastEvaluationTimestamp = null;
            // Clear all controllers when a new stand is selected or no existing evaluation
            _criteria.forEach((criterion) {
              _scoreControllers[criterion.id]?.clear();
            });
            // print('DEBUG (Flutter): No existing scores found for stand $standId.'); // Debug removed
          });
        }
      } else {
        _errorMessage = 'Fehler beim Laden bestehender Bewertungen: ${response.statusCode} - ${response.reasonPhrase}';
        // print('Error fetching existing scores: ${response.statusCode} - ${response.body}'); // Debug removed
      }
    } catch (e) {
      _errorMessage = 'Verbindungsfehler beim Laden bestehender Bewertungen: $e';
      // print('Exception fetching existing scores: $e'); // Debug removed
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Submits the evaluation scores to the Flask backend.
  Future<void> _submitEvaluation() async {
    if (_selectedStand == null) {
      _showAlertDialog('Fehler', 'Bitte wähle zuerst einen Stand aus.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final Map<String, int> scoresToSubmit = {};
    _criteria.forEach((criterion) {
      final text = _scoreControllers[criterion.id]?.text;
      if (text != null && text.isNotEmpty) {
        final score = int.tryParse(text);
        if (score != null && score >= 0 && score <= criterion.maxScore) {
          scoresToSubmit[criterion.id.toString()] = score;
        } else {
          // If score is invalid, it won't be submitted, but we should clear it if it was there
          _scoreControllers[criterion.id]?.clear(); 
        }
      }
    });

    // print('DEBUG (Flutter): Submitting evaluation for stand ${_selectedStand!.id} with scores: $scoresToSubmit'); // Debug removed
    // print('DEBUG (Flutter): Target URL: ${widget.serverAddress}/evaluate'); // Debug removed

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
      // print('DEBUG (Flutter): Submit evaluation response status: ${response.statusCode}'); // Debug removed
      // print('DEBUG (Flutter): Submit evaluation response body: ${response.body}'); // Debug removed


      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success']) {
          _showAlertDialog('Erfolg', data['message'] ?? 'Bewertung erfolgreich gespeichert!');
          // Refresh existing scores after submission
          _fetchExistingScores(_selectedStand!.id); 
        } else {
          _showAlertDialog('Fehler', data['message'] ?? 'Bewertung fehlgeschlagen.');
        }
      } else {
        final Map<String, dynamic> errorData = json.decode(response.body);
        _showAlertDialog('Fehler', errorData['message'] ?? 'Ein Fehler ist aufgetreten. Status: ${response.statusCode}');
        // print('Error submitting evaluation: ${response.statusCode} - ${response.body}'); // Debug removed
      }
    } catch (e) {
      _showAlertDialog('Verbindungsfehler', 'Fehler beim Senden der Bewertung: $e');
      // print('Exception submitting evaluation: $e'); // Debug removed
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


  @override
  Widget build(BuildContext context) {
    // Determine if dark mode is enabled
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    if (!_userHasRequiredRole(['Administrator', 'Bewerter'])) {
      // Display access denied message
      return Scaffold(
        // Removed AppBar here
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Added a custom title
                Text(
                  'Bewertung',
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
                  'Um hierdrauf zugreifen zu Können, brauchst du die Rolle Bewerter. Bei Bedarf kannst du diese beim Organisator erfragen.',
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
        // Removed AppBar here
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        // Removed AppBar here
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Added a custom title
                Text(
                  'Bewertung',
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
                  onPressed: _fetchInitialData,
                  child: const Text('Erneut versuchen'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      // Removed AppBar here
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Added a custom title
            Padding(
              padding: const EdgeInsets.only(top: 16.0, bottom: 16.0), // Add padding for the title
              child: Text(
                'Bewertung',
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.headlineLarge?.color,
                ),
                textAlign: TextAlign.left,
              ),
            ),
            const SizedBox(height: 20), // Add space after the new title

            // Stand Selection
            DropdownButtonFormField<Stand>(
              value: _selectedStand,
              decoration: InputDecoration(
                labelText: 'Stand auswählen:',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              hint: Text('Bitte Stand auswählen', style: GoogleFonts.inter()),
              isExpanded: true,
              items: _stands.map((stand) {
                return DropdownMenuItem<Stand>(
                  value: stand,
                  child: Text('${stand.name} (${stand.roomName ?? "Kein Raum"})', style: GoogleFonts.inter()),
                );
              }).toList(),
              onChanged: (Stand? newValue) {
                setState(() {
                  _selectedStand = newValue;
                  // Debug removed: print('DEBUG (Flutter): Selected Stand Description: ${newValue?.description}');
                  // Clear controllers and existing scores when selecting a new stand
                  _existingScores.clear();
                  _lastEvaluationTimestamp = null;
                  _criteria.forEach((criterion) {
                    _scoreControllers[criterion.id]?.clear();
                  });

                  if (newValue != null) {
                    _fetchExistingScores(newValue.id); // Fetch scores when stand changes
                  }
                });
              },
            ),
            const SizedBox(height: 20),

            // Stand Description
            // Now directly uses _selectedStand.description if available
            if (_selectedStand != null && _selectedStand!.description != null && _selectedStand!.description!.trim().isNotEmpty)
              Card(
                margin: EdgeInsets.zero, // Remove card margin to fit nicely
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                color: isDarkMode ? Colors.black : Theme.of(context).cardColor, // Adjusted card color for dark mode
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Beschreibung:',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).textTheme.bodyLarge?.color), // Explicitly set color
                      ),
                      const SizedBox(height: 8),
                      // Use RichText to display stand description, if it also uses HTML
                      RichText( // Changed from Text to RichText
                        text: _parseSimpleHtmlToTextSpan(
                          _selectedStand!.description!,
                          GoogleFonts.inter(fontSize: 14, color: Theme.of(context).textTheme.bodyLarge?.color), // Explicitly set color
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Updated condition for "No description available."
            // This condition will now catch null, empty, or whitespace-only descriptions.
            if (_selectedStand != null && (_selectedStand!.description == null || _selectedStand!.description!.trim().isEmpty))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10.0),
                child: Text(
                  'Keine Beschreibung für diesen Stand verfügbar.',
                  style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
                ),
              ),
            const SizedBox(height: 20),

            // Last Evaluation Timestamp
            if (_lastEvaluationTimestamp != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: Text(
                  'Zuletzt bewertet: $_lastEvaluationTimestamp',
                  style: GoogleFonts.inter(fontSize: 14, color: Colors.blueAccent),
                ),
              ),

            // Criteria Inputs
            ListView.builder(
              shrinkWrap: true, // Important to prevent unbounded height
              physics: const NeverScrollableScrollPhysics(), // Disable scrolling of ListView
              itemCount: _criteria.length,
              itemBuilder: (context, index) {
                final criterion = _criteria[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0), // Add spacing between items
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    color: isDarkMode ? Colors.black : Theme.of(context).cardColor, // Adjusted card color for dark mode
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
                                  overflow: TextOverflow.ellipsis, // Handle long names
                                  maxLines: 2, // Allow up to 2 lines for criterion name
                                ),
                              ),
                              IconButton( // Changed from Tooltip to IconButton to open dialog
                                icon: Icon(Icons.info_outline, size: 20, color: Theme.of(context).iconTheme.color),
                                onPressed: () {
                                  _showAlertDialog(
                                    criterion.name, // Title of the dialog is the criterion name
                                    criterion.description, // Content is the description
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox( // Wrapped TextField in SizedBox for explicit height
                            height: 65, // Increased height for input field (original was implicitly smaller)
                            child: TextField(
                              controller: _scoreControllers[criterion.id],
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: 'Punkte',
                                isDense: false, // Make input field taller (from isDense: true)
                                contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10), // Increased vertical padding
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
            const SizedBox(height: 16),

            // Submit Button
            Center(
              child: ElevatedButton(
                onPressed: _submitEvaluation,
                child: const Text('Bewertung speichern'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

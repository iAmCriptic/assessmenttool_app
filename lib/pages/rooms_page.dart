import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart'; // For session cookie and user role
import 'package:intl/intl.dart'; // For date formatting

/// Represents a Room with its inspection status.
class RoomInspection {
  final int roomId;
  final String roomName;
  final int standsInRoomCount; // Calculated from the 'stands' list from backend
  String inspectionStatus; // "Offen", "Sauber", "Nicht sauber"
  bool? isClean; // true for sauber, false for nicht sauber, null for offen
  String lastInspectedBy;
  String? inspectionTimestamp;
  String comment;
  
  // A controller for the comment TextField in each card
  TextEditingController commentController;

  RoomInspection({
    required this.roomId,
    required this.roomName,
    required this.standsInRoomCount,
    required this.inspectionStatus,
    this.isClean,
    required this.lastInspectedBy,
    this.inspectionTimestamp,
    required this.comment,
  }) : commentController = TextEditingController(text: comment); // Initialize controller with comment

  factory RoomInspection.fromJson(Map<String, dynamic> json) {
    bool? cleanStatus;
    // Check if 'is_clean' is present and convert to bool
    // Backend sends 1 for true, 0 for false. If null, it means no inspection.
    if (json.containsKey('is_clean') && json['is_clean'] != null) {
      cleanStatus = json['is_clean'] == 1; 
    }

    // Calculate standsInRoomCount from the 'stands' list provided by inspections.py (if available)
    // The backend inspections.py returns a list of stands within the room object, so we count them.
    final List<dynamic>? standsList = json['stands'] as List<dynamic>?;
    final int calculatedStandsInRoomCount = standsList?.length ?? 0;

    return RoomInspection(
      roomId: json['room_id'],
      roomName: json['room_name'],
      standsInRoomCount: calculatedStandsInRoomCount, // Use calculated count
      inspectionStatus: cleanStatus == null 
          ? 'Offen' 
          : (cleanStatus == true ? 'Sauber' : 'Nicht sauber'), // Derive status from isClean
      isClean: cleanStatus,
      lastInspectedBy: json['inspector_display_name'] ?? 'N/A',
      inspectionTimestamp: json['inspection_timestamp'],
      comment: json['comment'] ?? 'Kein Kommentar',
    );
  }

  // Don't forget to dispose the controller when the object is no longer needed
  void dispose() {
    commentController.dispose();
  }
}

/// The page to manage room inspections (now replacing the general RoomsPage).
class RoomsPage extends StatefulWidget { // Changed from StatelessWidget to StatefulWidget
  final String serverAddress;

  const RoomsPage({super.key, required this.serverAddress});

  @override
  State<RoomsPage> createState() => _RoomsPageState(); // Changed state class name
}

class _RoomsPageState extends State<RoomsPage> { // Changed state class name
  String? _userRole; // Stores the current user's role
  String? _sessionCookie; // Stores the session cookie for authenticated requests

  bool _isLoading = true;
  String? _errorMessage;
  List<RoomInspection> _roomInspections = [];

  @override
  void initState() {
    super.initState();
    _loadSessionCookie().then((_) {
      _loadUserRole().then((_) {
        // Fetch data only if user has access roles
        if (_userHasRequiredRole(['Administrator', 'Inspektor'])) {
          _fetchRoomInspections();
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
    // Dispose all TextEditingControllers
    for (var inspection in _roomInspections) {
      inspection.dispose(); // Call dispose method on each RoomInspection object
    }
    super.dispose();
  }

  /// Loads the session cookie from SharedPreferences.
  Future<void> _loadSessionCookie() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionCookie = prefs.getString('sessionCookie');
    print('DEBUG (Flutter): RoomsPage (Inspections) - Session cookie loaded: $_sessionCookie');
  }

  /// Loads the user's role from SharedPreferences.
  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    _userRole = prefs.getString('userRole');
    print('DEBUG (Flutter): RoomsPage (Inspections) - User role loaded: $_userRole');
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

  /// Fetches room inspection data from the Flask backend using /api/room_inspections.
  Future<void> _fetchRoomInspections() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final headers = _getAuthHeaders();
      print('DEBUG (Flutter): Fetching room inspections from ${widget.serverAddress}/api/room_inspections with headers: $headers');
      final response = await http.get(
        Uri.parse('${widget.serverAddress}/api/room_inspections'),
        headers: headers,
      );
      print('DEBUG (Flutter): Room inspections response status: ${response.statusCode}');
      print('DEBUG (Flutter): Room inspections response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            // Dispose old controllers before re-initializing
            for (var inspection in _roomInspections) {
              inspection.dispose(); // Call dispose method on each RoomInspection object
            }
            _roomInspections = (data['room_inspections'] as List)
                .map((r) => RoomInspection.fromJson(r))
                .toList();
          });
        } else {
          _errorMessage = data['message'] ?? 'Fehler beim Laden der Rauminspektionen.';
        }
      } else {
        _errorMessage = 'Fehler ${response.statusCode}: ${response.reasonPhrase}';
        print('Error fetching room inspections: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _errorMessage = 'Verbindungsfehler: $e';
      print('Exception fetching room inspections: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Updates the inspection status of a room by POSTing to /api/room_inspections.
  Future<void> _updateRoomStatus(RoomInspection roomToUpdate, bool isClean, String comment) async {
    setState(() {
      _isLoading = true; // Show loading indicator during update
    });
    try {
      final headers = _getAuthHeaders();
      final body = json.encode({
        'room_id': roomToUpdate.roomId, // Send room_id in the body for POST /api/room_inspections
        'is_clean': isClean ? 1 : 0, // Convert bool to int (1 or 0) for backend
        'comment': comment,
      });
      print('DEBUG (Flutter): Updating room status for room ${roomToUpdate.roomId} with body: $body');
      
      // POST to /api/room_inspections as per inspections.py
      final response = await http.post(
        Uri.parse('${widget.serverAddress}/api/room_inspections'), 
        headers: headers,
        body: body,
      );
      print('DEBUG (Flutter): Update room status response status: ${response.statusCode}');
      print('DEBUG (Flutter): Update room status response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success']) {
          _showAlertDialog('Erfolg', data['message'] ?? 'Raumstatus erfolgreich aktualisiert.');
          // Refresh data after update to show current state from server
          _fetchRoomInspections(); 
        } else {
          _showAlertDialog('Fehler', data['message'] ?? 'Raumstatus-Aktualisierung fehlgeschlagen.');
        }
      } else {
        final Map<String, dynamic> errorData = json.decode(response.body);
        _showAlertDialog('Fehler', errorData['message'] ?? 'Ein Fehler ist aufgetreten. Status: ${response.statusCode}');
      }
    } catch (e) {
      _showAlertDialog('Verbindungsfehler', 'Fehler beim Aktualisieren des Raumstatus: $e');
      print('Exception updating room status: $e');
    } finally {
      setState(() {
        _isLoading = false; // Hide loading indicator
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
    // Determine if dark mode is enabled for card colors
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    if (!_userHasRequiredRole(['Administrator', 'Inspektor'])) {
      // Display access denied message
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Custom Title
                Text(
                  'Rauminspektionen',
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
                  'Um hierdrauf zugreifen zu Können, brauchst du die Rolle Inspektor oder Administrator. Bei Bedarf kannst du diese beim Organisator erfragen.',
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
                // Custom Title
                Text(
                  'Rauminspektionen',
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
                  onPressed: _fetchRoomInspections,
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
        onRefresh: _fetchRoomInspections,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Custom Title
              Padding(
                padding: const EdgeInsets.only(top: 16.0, bottom: 16.0),
                child: Text(
                  'Rauminspektionen',
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.headlineLarge?.color,
                  ),
                  textAlign: TextAlign.left,
                ),
              ),
              const SizedBox(height: 20),

              if (_roomInspections.isEmpty)
                Center(
                  child: Text(
                    'Keine Räume zur Inspektion gefunden.',
                    style: GoogleFonts.inter(fontSize: 16, color: Colors.grey[600]),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _roomInspections.length,
                  itemBuilder: (context, index) {
                    final room = _roomInspections[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16.0),
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                      color: isDarkMode ? Colors.black : Theme.of(context).cardColor, // Dark mode color
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room.roomName,
                              style: GoogleFonts.inter(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).textTheme.headlineMedium?.color,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Stände im Raum: ${room.standsInRoomCount}',
                              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  'Status: ',
                                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  room.inspectionStatus,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: room.inspectionStatus == 'Sauber'
                                        ? Colors.green
                                        : (room.inspectionStatus == 'Nicht sauber' ? Colors.red : Colors.orange),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            if (room.inspectionTimestamp != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Zuletzt inspiziert: ${room.inspectionTimestamp} von ${room.lastInspectedBy}',
                                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
                              ),
                            ],
                            const SizedBox(height: 16),
                            TextField(
                              controller: room.commentController, // Use the specific controller for this room
                              decoration: InputDecoration(
                                labelText: 'Kommentar',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                isDense: true,
                              ),
                              maxLines: null, // Allow multiline input
                              style: GoogleFonts.inter(),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly, // Distribute space evenly
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _isLoading ? null : () { // Disable button while loading
                                      _updateRoomStatus(room, true, room.commentController.text);
                                    },
                                    icon: const Icon(Icons.check_circle_outline),
                                    label: const Text('Sauber'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green[600],
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      textStyle: GoogleFonts.inter(fontSize: 14), // Smaller font size to fit
                                      padding: const EdgeInsets.symmetric(vertical: 12), // Adjust padding
                                      minimumSize: const Size.fromHeight(40), // Ensure minimum height to prevent squishing
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10), // Space between buttons
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _isLoading ? null : () { // Disable button while loading
                                      _updateRoomStatus(room, false, room.commentController.text);
                                    },
                                    icon: const Icon(Icons.cancel_outlined),
                                    label: const Text('Nicht sauber'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red[600],
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      textStyle: GoogleFonts.inter(fontSize: 14), // Smaller font size to fit
                                      padding: const EdgeInsets.symmetric(vertical: 12), // Adjust padding
                                      minimumSize: const Size.fromHeight(40), // Ensure minimum height to prevent squishing
                                    ),
                                  ),
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
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart'; // Still needed for session cookie
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
    // Check if 'is_clean' is present and convert to bool:
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
class RoomsPage extends StatefulWidget { 
  final String serverAddress;
  final String? currentUserRole; // New: Pass the current user's role

  const RoomsPage({super.key, required this.serverAddress, this.currentUserRole});

  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  String? _userRole; // Stores the current user's role
  String? _sessionCookie; 
  bool _isLoading = true;
  String? _errorMessage;
  List<RoomInspection> _roomInspections = [];

  // Neue State-Variablen für dynamische Farbverläufe vom Server
  Color _gradientColor1 = Colors.blue.shade50; // Standard Hellmodus Startfarbe
  Color _gradientColor2 = Colors.blue.shade200; // Standard Hellmodus Endfarbe
  Color _darkGradientColor1 = Colors.black; // Standard Dunkelmodus Startfarbe
  Color _darkGradientColor2 = Colors.blueGrey; // Standard Dunkelmodus Endfarbe

  String? _logoFullPath; // Pfad zum Logo

  @override
  void initState() {
    super.initState();
    _loadSessionCookie().then((_) {
      _loadUserRole().then((_) { // Lade Benutzerrolle zuerst
        // Ruft jetzt alle Daten ab (Inspektionen & Einstellungen), unabhängig von der Rolle
        // Die Berechtigungsprüfung erfolgt innerhalb von _fetchPageData
        _fetchPageData(); 
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

  /// Konvertiert einen Hex-Farbstring (z.B. "#RRGGBB") in ein Flutter Color-Objekt.
  Color _hexToColor(String hexString) {
    final String hex = hexString.replaceAll('#', '');
    return Color(int.parse('ff$hex', radix: 16));
  }

  /// Fetches all necessary data for the page (room inspections and app settings).
  Future<void> _fetchPageData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final headers = _getAuthHeaders();

      // Rufe beide Endpunkte gleichzeitig ab
      // Die API für Rauminspektionen wird nur aufgerufen, wenn der Benutzer die Berechtigung hat
      Future<http.Response> roomsFuture;
      if (_userHasRequiredRole(['Administrator', 'Inspektor'])) {
        roomsFuture = http.get(Uri.parse('${widget.serverAddress}/api/room_inspections'), headers: headers);
      } else {
        // Wenn keine Berechtigung, einen Future mit leerer/fehlerhafter Antwort erstellen
        roomsFuture = Future.value(http.Response('{"success": false, "message": "Keine Berechtigung"}', 403));
      }
      
      final Future<http.Response> adminSettingsFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/admin_settings'), headers: headers);

      final List<http.Response> responses = await Future.wait([roomsFuture, adminSettingsFuture]);

      // Verarbeitung der Rauminspektionsdaten
      final roomInspectionsResponse = responses[0];
      if (roomInspectionsResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(roomInspectionsResponse.body);
        if (data['success']) {
          // Alte Controller vor der Neuinitialisierung entsorgen
          for (var inspection in _roomInspections) {
            inspection.dispose();
          }
          _roomInspections = (data['room_inspections'] as List)
              .map((r) => RoomInspection.fromJson(r))
              .toList();
        } else {
          _errorMessage = data['message'] ?? 'Fehler beim Laden der Rauminspektionen.';
        }
      } else if (roomInspectionsResponse.statusCode == 403) {
        // Explizite Behandlung für "Zugriff verweigert"
        _errorMessage = 'Sie haben keine Berechtigung, auf diese Seite zuzugreifen.';
      } else {
        _errorMessage = 'Fehler ${roomInspectionsResponse.statusCode}: ${roomInspectionsResponse.reasonPhrase}';
        print('Error fetching room inspections: ${roomInspectionsResponse.statusCode} - ${roomInspectionsResponse.body}');
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

            // Logo-Pfad wie in MorePage laden
            final String? logoPathFromBackend = data['settings']['logo_path'];
            if (logoPathFromBackend != null && logoPathFromBackend.isNotEmpty) {
              String serverAddress = widget.serverAddress;
              String cleanedLogoPath = logoPathFromBackend;

              if (serverAddress.endsWith('/')) {
                serverAddress = serverAddress.substring(0, serverAddress.length - 1);
              }
              if (cleanedLogoPath.startsWith('/')) {
                cleanedLogoPath = cleanedLogoPath.substring(1);
              }
              _logoFullPath = '$serverAddress/$cleanedLogoPath';
            } else {
              _logoFullPath = null; // No logo path provided
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


  /// Updates the inspection status of a room by POSTing to /api/room_inspections.
  Future<void> _updateRoomStatus(RoomInspection roomToUpdate, bool isClean, String comment) async {
    // Re-check role before submitting to ensure no changes in between
    if (!_userHasRequiredRole(['Administrator', 'Inspektor'])) {
       _showAlertDialog('Zugriff verweigert', 'Ihre Rolle hat sich möglicherweise geändert. Sie haben keine Berechtigung, diesen Vorgang durchzuführen.');
       // Optionally, refresh the page to show the access denied message
       _fetchPageData(); // Will trigger re-check and show access denied message
       return;
    }

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
          _fetchPageData(); // Gesamte Seitendaten neu laden
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

    // Gemeinsamer Aufbau für alle Zustände (Zugriff verweigert, Ladezustand, Fehler, Inhalt)
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
          // Always display the header with logo
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildHeaderWithLogo(context, 'Rauminspektionen'),
          ),
          // Conditional content based on loading, error, or access denied state
          Padding(
            padding: const EdgeInsets.only(top: 100.0), // Add padding to not overlap with the fixed header
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null && _errorMessage == 'Sie haben keine Berechtigung, auf diese Seite zuzugreifen.'
                    ? Center( // Zugriff verweigert Meldung
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // _buildHeaderWithLogo(context, 'Rauminspektionen'), // Header mit Logo -> moved out of here
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
                      )
                    : _errorMessage != null // Andere Fehlermeldungen
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // _buildHeaderWithLogo(context, 'Rauminspektionen'), // Header mit Logo -> moved out of here
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
                          )
                        : RefreshIndicator( // Normaler Inhalt
                            onRefresh: _fetchPageData, 
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  physics: const AlwaysScrollableScrollPhysics(), 
                                  padding: EdgeInsets.fromLTRB(
                                    16.0,
                                    16.0,
                                    16.0,
                                    16.0 + MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight, 
                                  ),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: constraints.maxHeight - (
                                        kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.start,
                                      children: [
                                        // _buildHeaderWithLogo(context, 'Rauminspektionen'), // Header mit Logo -> moved out of here
                                        const SizedBox(height: 20),

                                        if (_roomInspections.isEmpty)
                                          Expanded( 
                                            child: Center(
                                              child: Text(
                                                'Keine Räume zur Inspektion gefunden.',
                                                style: GoogleFonts.inter(fontSize: 16, color: Colors.grey[600]),
                                              ),
                                            ),
                                          )
                                        else
                                          ListView.builder(
                                            shrinkWrap: true,
                                            physics: const NeverScrollableScrollPhysics(),
                                            itemCount: _roomInspections.length,
                                            itemBuilder: (context, index) {
                                              final room = _roomInspections[index];
                                              
                                              String formattedInspectionTimestamp = 'N/A';
                                              if (room.inspectionTimestamp != null) {
                                                try {
                                                  final DateTime parsedTimestamp = DateTime.parse(room.inspectionTimestamp!);
                                                  formattedInspectionTimestamp = DateFormat('dd.MM.yyyy - HH:mm').format(parsedTimestamp.toLocal());
                                                } catch (e) {
                                                  print('Error parsing inspection timestamp: $e');
                                                  formattedInspectionTimestamp = 'Ungültiges Datum';
                                                }
                                              }

                                              return Card(
                                                margin: const EdgeInsets.only(bottom: 16.0),
                                                elevation: 4,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                                                color: isDarkMode ? Colors.black : Colors.white, 
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
                                                          'Zuletzt inspiziert: $formattedInspectionTimestamp von ${room.lastInspectedBy}',
                                                          style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
                                                        ),
                                                      ],
                                                      const SizedBox(height: 16),
                                                      TextField(
                                                        controller: room.commentController, 
                                                        decoration: InputDecoration(
                                                          labelText: 'Kommentar',
                                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                          isDense: true,
                                                        ),
                                                        maxLines: null, 
                                                        style: GoogleFonts.inter(),
                                                      ),
                                                      const SizedBox(height: 16),
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceEvenly, 
                                                        children: [
                                                          Expanded(
                                                            child: ElevatedButton.icon(
                                                              onPressed: _isLoading ? null : () { 
                                                                _updateRoomStatus(room, true, room.commentController.text);
                                                              },
                                                              icon: const Icon(Icons.check_circle_outline),
                                                              label: const Text('Sauber'),
                                                              style: ElevatedButton.styleFrom(
                                                                backgroundColor: Colors.green[600],
                                                                foregroundColor: Colors.white,
                                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                                textStyle: GoogleFonts.inter(fontSize: 14), 
                                                                padding: const EdgeInsets.symmetric(vertical: 12), 
                                                                minimumSize: const Size.fromHeight(40), 
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(width: 10), 
                                                          Expanded(
                                                            child: ElevatedButton.icon(
                                                              onPressed: _isLoading ? null : () { 
                                                                _updateRoomStatus(room, false, room.commentController.text);
                                                              },
                                                              icon: const Icon(Icons.cancel_outlined),
                                                              label: const Text('Nicht sauber'),
                                                              style: ElevatedButton.styleFrom(
                                                                backgroundColor: Colors.red[600],
                                                                foregroundColor: Colors.white,
                                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                                textStyle: GoogleFonts.inter(fontSize: 14), 
                                                                padding: const EdgeInsets.symmetric(vertical: 12), 
                                                                minimumSize: const Size.fromHeight(40), 
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
                                ); 
                              }
                            ), 
                          ), 
          ),
        ],
      ), 
    ); 
  }

  // Hilfs-Widget für den Header mit Titel und Logo
  Widget _buildHeaderWithLogo(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0), // Added horizontal padding
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center, // Vertikal zentrieren
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
                height: 80,
                width: 80,
                fit: BoxFit.contain,
                key: ValueKey(_logoFullPath),
                errorBuilder: (context, error, stackTrace) =>
                    Icon(Icons.business, size: 80, color: Theme.of(context).iconTheme.color),
              ),
            )
          else
            Icon(Icons.business, size: 80, color: Theme.of(context).iconTheme.color),
        ],
      ),
    );
  }
}

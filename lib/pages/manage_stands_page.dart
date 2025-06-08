import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme_manager.dart'; // Pfad anpassen, falls nötig
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // Für Session-Cookie und Benutzerrolle

/// Repräsentiert einen Stand für die Anzeige und Verwaltung.
class Stand {
  final int id;
  final String name;
  final String? description;
  final int? roomId;
  final String? roomName;

  Stand({
    required this.id,
    required this.name,
    this.description,
    this.roomId,
    this.roomName,
  });

  factory Stand.fromJson(Map<String, dynamic> json) {
    return Stand(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      roomId: json['room_id'],
      roomName: json['room_name'],
    );
  }
}

/// Repräsentiert einen Raum für die Auswahl in Dropdowns.
class Room {
  final int id;
  final String name;

  Room({required this.id, required this.name});

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'],
      name: json['name'],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Room && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Die Seite zur Verwaltung von Ständen.
class ManageStandsPage extends StatefulWidget {
  final String serverAddress;
  const ManageStandsPage({super.key, required this.serverAddress});

  @override
  State<ManageStandsPage> createState() => _ManageStandsPageState();
}

class _ManageStandsPageState extends State<ManageStandsPage> {
  // Zustandsvariablen für dynamische Farbverläufe vom Server
  Color _gradientColor1 = Colors.blue.shade50; // Standard Hellmodus Startfarbe
  Color _gradientColor2 = Colors.blue.shade200; // Standard Hellmodus Endfarbe
  Color _darkGradientColor1 = Colors.black; // Standard Dunkelmodus Startfarbe
  Color _darkGradientColor2 = Colors.blueGrey; // Standard Dunkelmodus Endfarbe

  bool _isLoading = true;
  String? _errorMessage;
  List<Stand> _stands = [];
  List<Room> _rooms = []; // Liste der verfügbaren Räume
  String? _sessionCookie; // Speichert das Session-Cookie für authentifizierte Anfragen
  String? _userRole; // Speichert die Rolle des aktuellen Benutzers

  // Controller zum Anlegen eines neuen Standes
  final TextEditingController _newStandNameController = TextEditingController();
  final TextEditingController _newStandDescriptionController = TextEditingController();
  Room? _selectedNewRoom; // Für Dropdown-Auswahl

  // Controller zum Bearbeiten eines bestehenden Standes
  final TextEditingController _editStandNameController = TextEditingController();
  final TextEditingController _editStandDescriptionController = TextEditingController();
  Room? _selectedEditRoom; // Für Dropdown-Auswahl
  Stand? _standToEdit; // Speichert den aktuell bearbeiteten Stand

  @override
  void initState() {
    super.initState();
    _loadSessionCookie().then((_) {
      _loadUserRole().then((_) {
        _fetchPageData(); // Daten laden, nachdem Rollen geladen wurden
      });
    });
  }

  @override
  void dispose() {
    _newStandNameController.dispose();
    _newStandDescriptionController.dispose();
    _editStandNameController.dispose();
    _editStandDescriptionController.dispose();
    super.dispose();
  }

  /// Lädt das Session-Cookie aus SharedPreferences.
  Future<void> _loadSessionCookie() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionCookie = prefs.getString('sessionCookie');
    print('DEBUG (Flutter): Session-Cookie geladen: $_sessionCookie');
  }

  /// Lädt die Benutzerrolle aus SharedPreferences.
  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    _userRole = prefs.getString('userRole');
    print('DEBUG (Flutter): Benutzerrolle geladen: $_userRole');
  }

  /// Überprüft, ob der aktuelle Benutzer eine der erforderlichen Rollen besitzt.
  bool _userHasRequiredRole(List<String> requiredRoles) {
    if (_userRole == null) return false;
    return requiredRoles.contains(_userRole);
  }

  /// Konvertiert einen Hex-Farbstring (z.B. "#RRGGBB") in ein Flutter Color-Objekt.
  Color _hexToColor(String hexString) {
    final String hex = hexString.replaceAll('#', '');
    if (hex.length == 6) {
      return Color(int.parse('ff$hex', radix: 16));
    } else if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    print('WARN (Flutter): Ungültiger Hex-Farbstring: $hexString. Grau wird zurückgegeben.');
    return Colors.grey; // Standard- oder Fehlerfarbe
  }

  /// Hilfsfunktion zum Abrufen von Headern mit dem Session-Cookie.
  Map<String, String> _getAuthHeaders() {
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
    };
    if (_sessionCookie != null) {
      headers['Cookie'] = _sessionCookie!;
    }
    return headers;
  }

  /// Ruft alle erforderlichen Daten für die Seite ab (Stände, Räume und App-Einstellungen).
  Future<void> _fetchPageData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Sofortige Rollenprüfung
    if (!_userHasRequiredRole(['Administrator'])) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Sie haben keine Berechtigung, auf diese Seite zuzugreifen.';
      });
      return;
    }

    try {
      final headers = _getAuthHeaders();

      final Future<http.Response> standsFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/stands'), headers: headers);
      final Future<http.Response> roomsFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/rooms'), headers: headers);
      final Future<http.Response> adminSettingsFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/admin_settings'), headers: headers);

      final List<http.Response> responses =
          await Future.wait([standsFuture, roomsFuture, adminSettingsFuture]);

      // Stände-Antwort verarbeiten
      final standsResponse = responses[0];
      print('DEBUG (Flutter): Stände API-Antwortstatus: ${standsResponse.statusCode}');
      print('DEBUG (Flutter): Stände API-Antwortkörper: ${standsResponse.body}');
      if (standsResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(standsResponse.body);
        if (data['success']) {
          _stands = (data['stands'] as List).map((s) => Stand.fromJson(s)).toList();
        } else {
          _errorMessage = data['message'] ?? 'Fehler beim Laden der Stände.';
        }
      } else {
        _errorMessage =
            'Fehler ${standsResponse.statusCode}: ${standsResponse.reasonPhrase}';
        print('Fehler beim Abrufen der Stände: ${standsResponse.statusCode} - ${standsResponse.body}');
      }

      // Räume-Antwort verarbeiten
      final roomsResponse = responses[1];
      print('DEBUG (Flutter): Räume API-Antwortstatus: ${roomsResponse.statusCode}');
      print('DEBUG (Flutter): Räume API-Antwortkörper: ${roomsResponse.body}');
      if (roomsResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(roomsResponse.body);
        if (data['success']) {
          _rooms = (data['rooms'] as List).map((r) => Room.fromJson(r)).toList();
        } else {
          _errorMessage =
              (_errorMessage ?? '') + (data['message'] ?? 'Fehler beim Laden der Räume.');
        }
      } else {
        _errorMessage = (_errorMessage ?? '') +
            'Fehler ${roomsResponse.statusCode}: ${roomsResponse.reasonPhrase}';
        print('Fehler beim Abrufen der Räume: ${roomsResponse.statusCode} - ${roomsResponse.body}');
      }

      // Admin-Einstellungen-Antwort verarbeiten
      final adminSettingsResponse = responses[2];
      print('DEBUG (Flutter): Admin-Einstellungen API-Antwortstatus: ${adminSettingsResponse.statusCode}');
      print('DEBUG (Flutter): Admin-Einstellungen API-Antwortkörper: ${adminSettingsResponse.body}');
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
        print('Fehler beim Abrufen der Admin-Einstellungen für den Farbverlauf: ${adminSettingsResponse.statusCode}');
      }
    } catch (e) {
      _errorMessage = 'Verbindungsfehler: $e';
      print('Ausnahme beim Abrufen der Seitendaten: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Legt einen neuen Stand an.
  Future<void> _createStand() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (_newStandNameController.text.isEmpty) {
      _showAlertDialog('Fehler', 'Bitte gib einen Standnamen ein.');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final headers = _getAuthHeaders();
    final requestBody = json.encode({
      'name': _newStandNameController.text.trim(),
      'description': _newStandDescriptionController.text.trim(),
      'room_id': _selectedNewRoom?.id, // Sende null, wenn kein Raum ausgewählt ist
    });
    print('DEBUG (Flutter): Sende Anfrage zum Anlegen des Standes: $requestBody');

    try {
      final response = await http.post(
        Uri.parse('${widget.serverAddress}/api/stands'),
        headers: headers,
        body: requestBody,
      );

      final Map<String, dynamic> data = json.decode(response.body);
      print('DEBUG (Flutter): Stand anlegen Antwortstatus: ${response.statusCode}');
      print('DEBUG (Flutter): Stand anlegen Antwortkörper: ${response.body}');
      if (response.statusCode == 201 && data['success']) {
        _showAlertDialog('Erfolg', data['message']);
        _newStandNameController.clear();
        _newStandDescriptionController.clear();
        setState(() {
          _selectedNewRoom = null; // Auswahl zurücksetzen
        });
        _fetchPageData(); // Ständeliste aktualisieren
      } else {
        _showAlertDialog('Fehler', data['message'] ?? 'Fehler beim Anlegen des Standes.');
      }
    } catch (e) {
      _showAlertDialog('Verbindungsfehler', 'Fehler beim Anlegen des Standes: $e');
      print('FEHLER (Flutter): Ausnahme beim Anlegen des Standes: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Bearbeitet einen bestehenden Stand.
  Future<void> _editStand() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (_standToEdit == null || _editStandNameController.text.isEmpty) {
      _showAlertDialog('Fehler', 'Bitte gib einen Standnamen ein.');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final headers = _getAuthHeaders();
    final requestBody = json.encode({
      'name': _editStandNameController.text.trim(),
      'description': _editStandDescriptionController.text.trim(),
      'room_id': _selectedEditRoom?.id, // Sende null, wenn kein Raum ausgewählt ist
    });
    print('DEBUG (Flutter): Sende Anfrage zum Bearbeiten des Standes: $requestBody');

    try {
      final response = await http.put(
        Uri.parse('${widget.serverAddress}/api/stands/${_standToEdit!.id}'),
        headers: headers,
        body: requestBody,
      );

      final Map<String, dynamic> data = json.decode(response.body);
      print('DEBUG (Flutter): Stand bearbeiten Antwortstatus: ${response.statusCode}');
      print('DEBUG (Flutter): Stand bearbeiten Antwortkörper: ${response.body}');
      if (response.statusCode == 200 && data['success']) {
        _showAlertDialog('Erfolg', data['message']).then((_) {
          Navigator.of(context).pop(); // Modal nach Bestätigung schließen
        });
        _fetchPageData(); // Ständeliste aktualisieren
      } else {
        _showAlertDialog('Fehler', data['message'] ?? 'Fehler beim Aktualisieren des Standes.');
      }
    } catch (e) {
      _showAlertDialog('Verbindungsfehler', 'Fehler beim Aktualisieren des Standes: $e');
      print('FEHLER (Flutter): Ausnahme beim Bearbeiten des Standes: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Löscht einen Stand.
  Future<void> _deleteStand(int standId, String standName) async {
    final bool confirmDelete = await _showConfirmationDialog(
        'Stand löschen', 'Möchten Sie den Stand "$standName" wirklich löschen?');
    if (!confirmDelete) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final headers = _getAuthHeaders();
    print('DEBUG (Flutter): Sende Anfrage zum Löschen des Standes mit ID: $standId');

    try {
      final response = await http.delete(
        Uri.parse('${widget.serverAddress}/api/stands/$standId'),
        headers: headers,
      );

      final Map<String, dynamic> data = json.decode(response.body);
      print('DEBUG (Flutter): Stand löschen Antwortstatus: ${response.statusCode}');
      print('DEBUG (Flutter): Stand löschen Antwortkörper: ${response.body}');
      if (response.statusCode == 200 && data['success']) {
        _showAlertDialog('Erfolg', data['message']);
        _fetchPageData(); // Ständeliste aktualisieren
      } else {
        _showAlertDialog('Fehler', data['message'] ?? 'Fehler beim Löschen des Standes.');
      }
    } catch (e) {
      _showAlertDialog('Verbindungsfehler', 'Fehler beim Löschen des Standes: $e');
      print('FEHLER (Flutter): Ausnahme beim Löschen des Standes: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Zeigt ein Alert-Dialog für Nachrichten an.
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

  /// Zeigt einen Bestätigungs-Dialog an und gibt true zurück, wenn bestätigt, sonst false.
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
        false; // Gibt false zurück, wenn der Dialog abgewiesen wird
  }

  /// Zeigt das Bearbeitungs-Modal mit vorausgefüllten Daten an.
  void _showEditStandModal(Stand stand) {
    setState(() {
      _standToEdit = stand;
      _editStandNameController.text = stand.name;
      _editStandDescriptionController.text = stand.description ?? '';
      _selectedEditRoom = _rooms.firstWhere(
        (room) => room.id == stand.roomId,
        orElse: () => _rooms.first, // Fallback, falls Raum nicht gefunden oder keiner zugewiesen
      );
      // Wenn der Raum null ist, setzen Sie _selectedEditRoom auf null
      if (stand.roomId == null) {
        _selectedEditRoom = null;
      }
    });

    showDialog(
      context: context,
      builder: (BuildContext context) {
        final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDarkMode ? Colors.black : Colors.white,
          title: Text(
              'Stand bearbeiten: ${stand.name}',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.headlineMedium?.color)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _editStandNameController,
                  decoration: InputDecoration(
                    labelText: 'Standname',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  style: GoogleFonts.inter(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _editStandDescriptionController,
                  decoration: InputDecoration(
                    labelText: 'Beschreibung',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  maxLines: 3, // Mehrere Zeilen für die Beschreibung
                  style: GoogleFonts.inter(),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<Room>(
                  value: _selectedEditRoom,
                  decoration: InputDecoration(
                    labelText: 'Raum',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: [
                    const DropdownMenuItem<Room>(
                      value: null,
                      child: Text('(Kein Raum)'),
                    ),
                    ..._rooms.map((room) {
                      return DropdownMenuItem<Room>(
                        value: room,
                        child: Text(room.name),
                      );
                    }).toList(),
                  ],
                  onChanged: (Room? newValue) {
                    setState(() { // Update state in the main page
                      _selectedEditRoom = newValue;
                    });
                    // This is crucial: Also update the state within the dialog itself
                    // to reflect the change visually without rebuilding the whole page.
                    (context as Element).markNeedsBuild(); // Force rebuild of the dialog
                  },
                  style: GoogleFonts.inter(),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 100, // Feste Breite
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
                      width: 100, // Feste Breite
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _editStand,
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

  /// Zeigt ein Modal für die vollständige Beschreibung an.
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

    // Initialer Lade-/Zugriffsverweigerungs-Bildschirm
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
                            'Standverwaltung',
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

    // Fehlerbildschirm
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
                      'Standverwaltung',
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

    // Hauptinhalt, wenn geladen und autorisiert
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
                  // Zurück-Pfeil und Titel in einer Reihe
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
                            'Standverwaltung',
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

                  // Bereich "Neuen Stand anlegen"
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
                            'Neuen Stand anlegen',
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.headlineMedium?.color,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _newStandNameController,
                            decoration: InputDecoration(
                              labelText: 'Standname',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            style: GoogleFonts.inter(),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _newStandDescriptionController,
                            decoration: InputDecoration(
                              labelText: 'Beschreibung (optional)',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            maxLines: 3,
                            style: GoogleFonts.inter(),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<Room>(
                            value: _selectedNewRoom,
                            decoration: InputDecoration(
                              labelText: 'Raum (optional)',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            items: [
                              const DropdownMenuItem<Room>(
                                value: null,
                                child: Text('(Kein Raum)'),
                              ),
                              ..._rooms.map((room) {
                                return DropdownMenuItem<Room>(
                                  value: room,
                                  child: Text(room.name),
                                );
                              }).toList(),
                            ],
                            onChanged: (Room? newValue) {
                              setState(() {
                                _selectedNewRoom = newValue;
                              });
                            },
                            style: GoogleFonts.inter(),
                          ),
                          const SizedBox(height: 24),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : _createStand,
                              icon: const Icon(Icons.add_circle_outline),
                              label: Text('Stand anlegen',
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

                  // Bereich "Vorhandene Stände"
                  Text(
                    'Vorhandene Stände',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.headlineLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_stands.isEmpty)
                    Center(
                      child: Text(
                        'Keine Stände gefunden.',
                        style: GoogleFonts.inter(fontSize: 16, color: Colors.grey[600]),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _stands.length,
                      itemBuilder: (context, index) {
                        final stand = _stands[index];
                        String displayDescription = stand.description ?? 'N/A';
                        bool needsReadMore = false;
                        const int maxChars = 50; // Max. Zeichen für die gekürzte Anzeige

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
                                  stand.name,
                                  style: GoogleFonts.inter(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).textTheme.headlineMedium?.color,
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
                                        onPressed: () => _showFullDescriptionModal(stand.description!),
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
                                const SizedBox(height: 4),
                                Text(
                                  'Raum: ${stand.roomName ?? 'Nicht zugewiesen'}',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () => _showEditStandModal(stand),
                                      tooltip: 'Stand bearbeiten',
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteStand(stand.id, stand.name),
                                      tooltip: 'Stand löschen',
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

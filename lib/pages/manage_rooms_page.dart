import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
// Pfad anpassen, falls nötig
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // Für Session-Cookie und Benutzerrolle

/// Repräsentiert einen Raum für die Anzeige und Verwaltung.
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
}

/// Die Seite zur Verwaltung von Räumen.
class ManageRoomsPage extends StatefulWidget {
  final String serverAddress;
  const ManageRoomsPage({super.key, required this.serverAddress});

  @override
  State<ManageRoomsPage> createState() => _ManageRoomsPageState();
}

class _ManageRoomsPageState extends State<ManageRoomsPage> {
  // Zustandsvariablen für dynamische Farbverläufe vom Server
  Color _gradientColor1 = Colors.blue.shade50; // Standard Hellmodus Startfarbe
  Color _gradientColor2 = Colors.blue.shade200; // Standard Hellmodus Endfarbe
  Color _darkGradientColor1 = Colors.black; // Standard Dunkelmodus Startfarbe
  Color _darkGradientColor2 = Colors.blueGrey; // Standard Dunkelmodus Endfarbe

  bool _isLoading = true;
  String? _errorMessage;
  List<Room> _rooms = [];
  String? _sessionCookie; // Speichert das Session-Cookie für authentifizierte Anfragen
  String? _userRole; // Speichert die Rolle des aktuellen Benutzers

  // Controller zum Anlegen/Bearbeiten eines Raumes
  final TextEditingController _roomNameController = TextEditingController();
  Room? _roomToEdit; // Speichert den aktuell bearbeiteten Raum

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
    _roomNameController.dispose();
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

  /// Ruft alle erforderlichen Daten für die Seite ab (Räume und App-Einstellungen).
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

      final Future<http.Response> roomsFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/rooms'), headers: headers);
      final Future<http.Response> adminSettingsFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/admin_settings'), headers: headers);

      final List<http.Response> responses =
          await Future.wait([roomsFuture, adminSettingsFuture]);

      // Räume-Antwort verarbeiten
      final roomsResponse = responses[0];
      print('DEBUG (Flutter): Räume API-Antwortstatus: ${roomsResponse.statusCode}');
      print('DEBUG (Flutter): Räume API-Antwortkörper: ${roomsResponse.body}');
      if (roomsResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(roomsResponse.body);
        if (data['success']) {
          _rooms = (data['rooms'] as List).map((r) => Room.fromJson(r)).toList();
        } else {
          _errorMessage = data['message'] ?? 'Fehler beim Laden der Räume.';
        }
      } else {
        _errorMessage =
            'Fehler ${roomsResponse.statusCode}: ${roomsResponse.reasonPhrase}';
        print('Fehler beim Abrufen der Räume: ${roomsResponse.statusCode} - ${roomsResponse.body}');
      }

      // Admin-Einstellungen-Antwort verarbeiten
      final adminSettingsResponse = responses[1];
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

  /// Fügt einen neuen Raum hinzu oder aktualisiert einen bestehenden.
  Future<void> _saveRoom() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (_roomNameController.text.isEmpty) {
      _showAlertDialog('Fehler', 'Bitte gib einen Raumnamen ein.');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final headers = _getAuthHeaders();
    final requestBody = json.encode({
      'name': _roomNameController.text.trim(),
    });
    print('DEBUG (Flutter): Sende Anfrage zum Speichern des Raumes: $requestBody');

    String url;
    String method;

    if (_roomToEdit == null) {
      url = '${widget.serverAddress}/api/rooms';
      method = 'POST';
    } else {
      url = '${widget.serverAddress}/api/rooms/${_roomToEdit!.id}';
      method = 'PUT';
    }

    try {
      final response = await (method == 'POST'
          ? http.post(Uri.parse(url), headers: headers, body: requestBody)
          : http.put(Uri.parse(url), headers: headers, body: requestBody));

      final Map<String, dynamic> data = json.decode(response.body);
      print('DEBUG (Flutter): Raum speichern Antwortstatus: ${response.statusCode}');
      print('DEBUG (Flutter): Raum speichern Antwortkörper: ${response.body}');
      if ((response.statusCode == 201 || response.statusCode == 200) && data['success']) {
        _showAlertDialog('Erfolg', data['message']).then((_) {
          Navigator.of(context).pop(); // Modal nach Bestätigung schließen
        });
        _roomNameController.clear();
        _fetchPageData(); // Raumliste aktualisieren
      } else {
        _showAlertDialog('Fehler', data['message'] ?? 'Fehler beim Speichern des Raumes.');
      }
    } catch (e) {
      _showAlertDialog('Verbindungsfehler', 'Fehler beim Speichern des Raumes: $e');
      print('FEHLER (Flutter): Ausnahme beim Speichern des Raumes: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Löscht einen Raum.
  Future<void> _deleteRoom(int roomId, String roomName) async {
    final bool confirmDelete = await _showConfirmationDialog(
        'Raum löschen', 'Möchten Sie den Raum "$roomName" wirklich löschen? Alle zugeordneten Stände werden ihre Raumzuweisung verlieren.');
    if (!confirmDelete) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final headers = _getAuthHeaders();
    print('DEBUG (Flutter): Sende Anfrage zum Löschen des Raumes mit ID: $roomId');

    try {
      final response = await http.delete(
        Uri.parse('${widget.serverAddress}/api/rooms/$roomId'),
        headers: headers,
      );

      final Map<String, dynamic> data = json.decode(response.body);
      print('DEBUG (Flutter): Raum löschen Antwortstatus: ${response.statusCode}');
      print('DEBUG (Flutter): Raum löschen Antwortkörper: ${response.body}');
      if (response.statusCode == 200 && data['success']) {
        _showAlertDialog('Erfolg', data['message']);
        _fetchPageData(); // Raumliste aktualisieren
      } else {
        _showAlertDialog('Fehler', data['message'] ?? 'Fehler beim Löschen des Raumes.');
      }
    } catch (e) {
      _showAlertDialog('Verbindungsfehler', 'Fehler beim Löschen des Raumes: $e');
      print('FEHLER (Flutter): Ausnahme beim Löschen des Raumes: $e');
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
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: Text('Bestätigen', style: GoogleFonts.inter()),
                ),
              ],
            );
          },
        ) ??
        false; // Gibt false zurück, wenn der Dialog abgewiesen wird
  }

  /// Zeigt das Hinzufügen-/Bearbeiten-Modal an.
  void _showRoomModal({Room? room}) {
    setState(() {
      _roomToEdit = room;
      _roomNameController.text = room?.name ?? '';
    });

    showDialog(
      context: context,
      builder: (BuildContext context) {
        final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDarkMode ? Colors.black : Colors.white,
          title: Text(
              room == null ? 'Neuen Raum hinzufügen' : 'Raum bearbeiten: ${room.name}',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.headlineMedium?.color)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _roomNameController,
                  decoration: InputDecoration(
                    labelText: 'Raumname',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
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
                        onPressed: _isLoading ? null : _saveRoom,
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
                            'Raumverwaltung',
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
                      'Raumverwaltung',
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
                            'Raumverwaltung',
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

                  // Bereich "Neuen Raum hinzufügen"
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
                            'Raum hinzufügen',
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.headlineMedium?.color,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _roomNameController,
                            decoration: InputDecoration(
                              labelText: 'Raumname',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            style: GoogleFonts.inter(),
                          ),
                          const SizedBox(height: 24),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : () => _showRoomModal(),
                              icon: const Icon(Icons.add_circle_outline),
                              label: Text('Raum hinzufügen',
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

                  // Bereich "Vorhandene Räume"
                  Text(
                    'Vorhandene Räume',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.headlineLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_rooms.isEmpty)
                    Center(
                      child: Text(
                        'Keine Räume gefunden.',
                        style: GoogleFonts.inter(fontSize: 16, color: Colors.grey[600]),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _rooms.length,
                      itemBuilder: (context, index) {
                        final room = _rooms[index];

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
                                  room.name,
                                  style: GoogleFonts.inter(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).textTheme.headlineMedium?.color,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () => _showRoomModal(room: room),
                                      tooltip: 'Raum bearbeiten',
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteRoom(room.id, room.name),
                                      tooltip: 'Raum löschen',
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

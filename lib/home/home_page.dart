import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart'; // Für Google Fonts
import 'package:http/http.dart' as http; // Für HTTP-Anfragen
import 'dart:convert'; // Für JSON-Dekodierung
import 'package:package_info_plus/package_info_plus.dart'; // Für das Abrufen der App-Version
import 'package:url_launcher/url_launcher.dart'; // Für das Öffnen von URLs

import '../pages/start_page.dart';
import '../pages/rooms_page.dart';
import '../pages/warnings_page.dart';
import '../pages/more_page.dart';
import '../pages/evaluation_page.dart';

/// Die HomePage ist der Hauptcontainer der App, der die BottomNavigationBar verwaltet
/// und verschiedene Inhaltsseiten anzeigt.
class HomePage extends StatefulWidget {
  final String serverAddress;

  const HomePage({
    super.key,
    required this.serverAddress,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0; // Der Index des aktuell ausgewählten Tabs
  late final List<Widget> _pages; // Liste der Widgets (Seiten) für jeden Tab
  String _currentAppVersion = 'Unbekannt'; // Speichert die aktuelle App-Version

  @override
  void initState() {
    super.initState();
    _pages = <Widget>[
      StartPage(
        serverAddress: widget.serverAddress,
        onTabChangeRequested: _changeTab, // Den Callback hier übergeben
      ),
      RoomsPage(serverAddress: widget.serverAddress),
      EvaluationPage(serverAddress: widget.serverAddress),
      WarningsPage(serverAddress: widget.serverAddress),
      MorePage(serverAddress: widget.serverAddress),
    ];

    // Verzögere die Versionsprüfung um 5 Sekunden, um Kollisionen mit anderen Startmeldungen zu vermeiden
    Future.delayed(const Duration(seconds: 5), () {
      _checkAppVersion();
    });
  }

  /// Callback-Funktion zum Ändern des ausgewählten Tabs
  void _changeTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  /// Hilfsfunktion zum Erstellen eines Navigationselements (nur Icon)
  /// Wird für "Start", "Räume", "Warnungen", "Mehr" verwendet
  Widget _buildNavItem(BuildContext context, IconData icon, int index) {
    final bool isSelected = _selectedIndex == index;
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Bestimme die Farbe des Icons basierend auf dem Modus und der Auswahl
    final Color iconColor;
    if (isDarkMode) { // Dark Mode: Navbar ist schwarz, Icons sollen hell sein
      iconColor = isSelected ? Colors.lightBlueAccent : Colors.white; // Hervorhebung für ausgewähltes Icon
    } else { // Light Mode: Navbar ist weiß, Icons sollen dunkel sein
      iconColor = isSelected ? Colors.blue[900]! : Colors.grey[700]!; // Hervorhebung für ausgewähltes Icon
    }

    return Expanded(
      child: Material( // Verwende Material für den Ink-Splash-Effekt
        color: Colors.transparent, // Transparent machen, damit die Farbe der BottomAppBar durchscheint
        child: InkWell( // Für Tap-Feedback
          onTap: () => _changeTab(index), // _changeTab direkt für die untere Navigation verwenden
          child: SizedBox( // Explizit die Größe für das Element definieren, um Überlauf zu vermeiden
            height: kBottomNavigationBarHeight, // Standardhöhe verwenden
            child: Center( // Das Icon in der SizedBox zentrieren
              child: Icon(icon, color: iconColor, size: 28), // Explizite Icon-Größe
            ),
          ),
        ),
      ),
    );
  }

  /// Überprüft die aktuelle App-Version mit dem neuesten GitHub-Release.
  Future<void> _checkAppVersion() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version;
      setState(() {
        _currentAppVersion = currentVersion;
      });
      print('DEBUG: Aktuelle App-Version: $currentVersion');

      const githubApiUrl = 'https://api.github.com/repos/iAmCriptic/assessmenttool_app/releases/latest';
      final response = await http.get(Uri.parse(githubApiUrl));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        // Sicherstellen, dass tag_name ein String ist und 'v' am Anfang entfernt wird
        final String latestVersion = (data['tag_name'] as String? ?? '').replaceFirst('v', '');
        final String downloadUrl = data['html_url'];

        print('DEBUG: Neueste GitHub-Version: $latestVersion');

        // Einfacher Versionsvergleich (z.B. 1.0.0 < 1.0.1, 1.1.0 < 1.10.0)
        if (_isNewerVersion(latestVersion, currentVersion)) {
          _showUpdateDialog(latestVersion, downloadUrl);
        }
      } else {
        print('FEHLER: GitHub API Anfrage fehlgeschlagen: ${response.statusCode}');
      }
    } catch (e) {
      print('FEHLER beim Überprüfen der App-Version: $e');
    }
  }

  /// Hilfsfunktion zum Vergleichen von Versionen.
  /// Gibt true zurück, wenn newVersion neuer ist als currentVersion.
  bool _isNewerVersion(String newVersion, String currentVersion) {
    // Entferne alle Nicht-Ziffern- oder Punkt-Zeichen
    final cleanNewVersion = newVersion.replaceAll(RegExp(r'[^\d.]'), '');
    final cleanCurrentVersion = currentVersion.replaceAll(RegExp(r'[^\d.]'), '');

    final List<int> newParts = cleanNewVersion.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final List<int> currentParts = cleanCurrentVersion.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    // Fülle kürzere Listen mit Nullen auf, um IndexOutOfBounds zu vermeiden
    final int maxLength = newParts.length > currentParts.length ? newParts.length : currentParts.length;
    while (newParts.length < maxLength) newParts.add(0);
    while (currentParts.length < maxLength) currentParts.add(0);


    for (int i = 0; i < maxLength; i++) {
      if (newParts[i] > currentParts[i]) {
        return true;
      }
      if (newParts[i] < currentParts[i]) {
        return false;
      }
    }
    return false; // Versionen sind gleich
  }

  /// Zeigt einen Dialog an, der den Benutzer zum Aktualisieren der App auffordert.
  void _showUpdateDialog(String latestVersion, String downloadUrl) {
    showDialog(
      context: context,
      barrierDismissible: false, // Benutzer muss eine Schaltfläche antippen, um den Dialog zu schließen
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Neue App-Version verfügbar!', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          content: Text(
            'Eine neue Version (v$latestVersion) ist verfügbar. Bitte aktualisiere die App, um die neuesten Funktionen und Fehlerbehebungen zu erhalten.',
            style: GoogleFonts.inter(),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Später', style: GoogleFonts.inter(color: Colors.grey)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: Text('Herunterladen', style: GoogleFonts.inter()),
              onPressed: () async {
                if (await canLaunchUrl(Uri.parse(downloadUrl))) {
                  await launchUrl(Uri.parse(downloadUrl));
                } else {
                  // Fallback, wenn die URL nicht geöffnet werden kann
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Konnte den Download-Link nicht öffnen.', style: GoogleFonts.inter()),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                Navigator.of(context).pop(); // Dialog schließen, nachdem versucht wurde, die URL zu öffnen
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
    final double appBarContentHeight = 60.0; 

    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBody: true,
      backgroundColor: null, // Verwendet den Standardhintergrund des Themes

      body: _pages[_selectedIndex], // Zeigt den Inhalt der ausgewählten Seite an
      
      bottomNavigationBar: BottomAppBar(
        color: isDarkMode ? Colors.black : Colors.white,
        elevation: 8.0,
        child: SizedBox(
          height: appBarContentHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _buildNavItem(context, Icons.home, 0), // Start
              _buildNavItem(context, Icons.meeting_room, 1), // Räume
              
              // Integrierter Plus-Button anstelle des FAB-Platzhalters
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      _changeTab(2); // Wähle den 'Bewerten'-Tab aus (Index 2)
                    },
                    child: SizedBox(
                      height: kBottomNavigationBarHeight,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isDarkMode ? Colors.white : Colors.black, 
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                spreadRadius: 2,
                                blurRadius: 5,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Icon(Icons.edit_note, size: 28, color: isDarkMode ? Colors.black : Colors.white), 
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              _buildNavItem(context, Icons.warning, 3), // Warnungen
              _buildNavItem(context, Icons.more_horiz, 4), // Mehr
            ],
          ),
        ),
      ),
    );
  }
}

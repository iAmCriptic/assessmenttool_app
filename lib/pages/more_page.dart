import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart'; // Import for GoogleFonts
import 'package:provider/provider.dart';
import 'dart:convert'; // Import for json.decode
import 'package:shared_preferences/shared_preferences.dart'; // For user role access

import '../auth/login_page.dart'; // Import LoginPage for navigation
import '../theme_manager.dart'; // Import ThemeNotifier

// Importiere die neuen Verwaltungsseiten
import '../pages/manage_users_page.dart';
import '../pages/manage_stands_page.dart';
import '../pages/manage_criteria_page.dart';
import '../pages/manage_rooms_page.dart';
import '../pages/manage_lists_page.dart';


/// The 'More' page, containing additional options like logout and theme toggle,
/// and administrative management links.
class MorePage extends StatefulWidget {
  final String serverAddress;
  const MorePage({super.key, required this.serverAddress});

  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  String? _userRole; // To store the current user's role
  bool _isLoadingRole = true;
  String? _logoFullPath; // Changed to _logoFullPath to match StartPage logic
  String _frontendVersion = 'V1.0.0 - Beta'; // Placeholder for frontend version
  String _backendVersion = 'V 2.1.3'; // Placeholder for backend version
  String? _sessionCookie; // Hinzugefügt: Deklaration der _sessionCookie Variable

  // Neue State-Variablen für dynamische Farbverläufe vom Server
  Color _gradientColor1 = Colors.blue.shade50; // Standard Hellmodus Startfarbe
  Color _gradientColor2 = Colors.blue.shade200; // Standard Hellmodus Endfarbe
  Color _darkGradientColor1 = Colors.black; // Standard Dunkelmodus Startfarbe
  Color _darkGradientColor2 = Colors.blueGrey; // Standard Dunkelmodus Endfarbe


  @override
  void initState() {
    super.initState();
    _loadSessionCookie().then((_) {
      _loadUserRole().then((_) { // Load user role on init
        _fetchPageData(); // Ruft jetzt alle Daten ab (Einstellungen & Versionen)
      });
    });
  }

  /// Loads the session cookie from SharedPreferences.
  Future<void> _loadSessionCookie() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionCookie = prefs.getString('sessionCookie');
  }

  /// Loads the user's role from SharedPreferences.
  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userRole = prefs.getString('userRole');
      _isLoadingRole = false;
    });
  }

  /// Checks if the current user has the 'Administrator' role.
  bool _isAdmin() {
    return _userRole == 'Administrator';
  }

  /// Konvertiert einen Hex-Farbstring (z.B. "#RRGGBB") in ein Flutter Color-Objekt.
  Color _hexToColor(String hexString) {
    final String hex = hexString.replaceAll('#', '');
    return Color(int.parse('ff$hex', radix: 16));
  }

  /// Fetches all necessary data for the page (app settings and versions).
  Future<void> _fetchPageData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? sessionCookie = prefs.getString('sessionCookie');

    final headers = <String, String>{};
    if (sessionCookie != null) {
      headers['Cookie'] = sessionCookie;
    }

    try {
      final Future<http.Response> appSettingsFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/admin_settings'), headers: headers);
      final Future<http.Response> versionsFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/versions'), headers: headers);

      final List<http.Response> responses = await Future.wait([appSettingsFuture, versionsFuture]);

      // Verarbeitung der App-Einstellungen (für Logo und Farbverläufe)
      final appSettingsResponse = responses[0];
      if (appSettingsResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(appSettingsResponse.body);
        if (data['success'] && data.containsKey('settings')) {
          setState(() {
            // Get logo_path from backend, similar to StartPage
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
            
            // Abrufen der Farbverläufe
            _gradientColor1 = _hexToColor(data['settings']['bg_gradient_color1'] ?? '#E3F2FD');
            _gradientColor2 = _hexToColor(data['settings']['bg_gradient_color2'] ?? '#BBDEFB');
            _darkGradientColor1 = _hexToColor(data['settings']['dark_bg_gradient_color1'] ?? '#000000');
            _darkGradientColor2 = _hexToColor(data['settings']['dark_bg_gradient_color2'] ?? '#455A64');
          });
        }
      } else {
        print('Error fetching app settings HTTP: ${appSettingsResponse.statusCode} - ${appSettingsResponse.reasonPhrase}');
      }

      // Verarbeitung der Versionsinformationen
      final versionsResponse = responses[1];
      if (versionsResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(versionsResponse.body);
        if (data['success']) {
          setState(() {
            _frontendVersion = data['frontend_version'] ?? 'N/A';
            _backendVersion = data['backend_version'] ?? 'N/A';
          });
        }
      } else {
        print('Error fetching versions: ${versionsResponse.statusCode}');
      }

    } catch (e) {
      print('Exception fetching page data: $e');
    }
  }


  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context, listen: false);
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


    if (_isLoadingRole) {
      return Scaffold(
        // Hintergrund transparent setzen, damit der Gradient durchscheint
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
            const Center(child: CircularProgressIndicator()),
          ],
        ),
      );
    }

    return Scaffold(
      // Hintergrund transparent setzen, damit der Gradient durchscheint
      backgroundColor: Colors.transparent, 
      body: Stack( // Stack verwenden, um Hintergrund und Inhalt zu schichten
        children: [
          // Hintergrund-Gradient-Container (füllt den gesamten Scaffold-Body)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: backgroundGradient, // Den Farbverlauf anwenden
              ),
            ),
          ),
          // Vordergrund-Inhalt (SingleChildScrollView)
          LayoutBuilder( // LayoutBuilder verwenden, um Constraints zu erhalten
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16.0,
                  16.0,
                  16.0,
                  // Angepasster Bottom-Padding für die BottomAppBar und System-Insets
                  16.0 + MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight, 
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Custom Title "Weiteres" and Logo
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0, bottom: 24.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Weiteres',
                            style: GoogleFonts.inter(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.headlineLarge?.color,
                            ),
                          ),
                          // Dynamically loaded Logo
                          if (_logoFullPath != null && _logoFullPath!.isNotEmpty) // Use _logoFullPath directly
                            Image.network(
                              _logoFullPath!, // Use the constructed full URL
                              width: 50,
                              height: 50,
                              fit: BoxFit.contain, // Ensures image fits without cropping
                              key: ValueKey(_logoFullPath), // Add ValueKey to force image reload
                              errorBuilder: (context, error, stackTrace) {
                                print('DEBUG (MorePage): Image.network error for $_logoFullPath: $error, stack: $stackTrace'); // Debug print
                                return Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Icon(Icons.business, size: 30, color: Colors.grey[700]),
                                  ),
                                );
                              },
                            )
                          else // Fallback if _logoFullPath is null or empty
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Icon(Icons.business, size: 30, color: Colors.grey[700]),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Management Options Section
                    Text(
                      'Verwaltung',
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.headlineLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Each management option is now its own Card
                    _buildManagementTile(
                      context,
                      'Benutzer verwalten',
                      icon: Icons.people_alt,
                      isComingSoon: false, // Geändert auf false, da Seite existiert
                      showOnlyAdmin: true,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ManageUsersPage(serverAddress: widget.serverAddress)),
                        );
                      },
                    ),
                    _buildManagementTile(
                      context,
                      'Stände verwalten',
                      icon: Icons.store,
                      isComingSoon: false, // Geändert auf false, da Seite existiert
                      showOnlyAdmin: true,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ManageStandsPage(serverAddress: widget.serverAddress)),
                        );
                      },
                    ),
                    _buildManagementTile(
                      context,
                      'Kriterien verwalten',
                      icon: Icons.rule,
                      isComingSoon: false, // Geändert auf false, da Seite existiert
                      showOnlyAdmin: true,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ManageCriteriaPage(serverAddress: widget.serverAddress)),
                        );
                      },
                    ),
                    _buildManagementTile(
                      context,
                      'Räume verwalten',
                      icon: Icons.meeting_room,
                      isComingSoon: false, // Geändert auf false, da Seite existiert
                      showOnlyAdmin: true,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ManageRoomsPage(serverAddress: widget.serverAddress)),
                        );
                      },
                    ),
                    _buildManagementTile(
                      context,
                      'Listen verwalten',
                      icon: Icons.list_alt,
                      isComingSoon: false, // Geändert auf false, da Seite existiert
                      showOnlyAdmin: true,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ManageListsPage(serverAddress: widget.serverAddress)),
                        );
                      },
                    ),
                    const SizedBox(height: 40), // More space before buttons

                    // Logout and Darkmode Buttons (side-by-side)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.logout),
                            label: Text('Abmelden', style: GoogleFonts.inter(fontSize: 16)),
                            onPressed: () async {
                              await LoginPage.clearSavedCredentials();
                              final Uri logoutUrl = Uri.parse('${widget.serverAddress}/api/logout');
                              try {
                                final response = await http.get(logoutUrl);
                                if (response.statusCode == 200) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('Erfolgreich abgemeldet.'),
                                      behavior: SnackBarBehavior.floating,
                                      margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10.0, left: 16.0, right: 16.0),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(builder: (context) => const LoginPage()),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Fehler beim Abmelden. Status: ${response.statusCode}'),
                                      behavior: SnackBarBehavior.floating,
                                      margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10.0, left: 16.0, right: 16.0),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Verbindungsfehler beim Abmelden: $e'),
                                    behavior: SnackBarBehavior.floating,
                                    margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10.0, left: 16.0, right: 16.0),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              backgroundColor: Colors.redAccent, // Make logout button distinct
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16), // Space between buttons
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(
                              Theme.of(context).brightness == Brightness.dark
                                  ? Icons.light_mode
                                  : Icons.dark_mode,
                            ),
                            label: Text(
                              Theme.of(context).brightness == Brightness.dark
                                  ? 'Light Mode'
                                  : 'Dark Mode',
                              style: GoogleFonts.inter(fontSize: 16),
                            ),
                            onPressed: () {
                              themeNotifier.toggleTheme();
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              backgroundColor: isDarkMode ? Colors.blueGrey[700] : Colors.indigoAccent, // Different color for theme toggle
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Version Information Section
                    Align(
                      alignment: Alignment.center,
                      child: Card( // Added Card for background
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        color: isDarkMode 
                            ? Colors.black.withOpacity(0.7) // Semi-transparent black for dark mode
                            : Colors.white.withOpacity(0.7), // Semi-transparent white for light mode
                        child: Padding(
                          padding: const EdgeInsets.all(12.0), // Added padding inside the card
                          child: Column(
                            children: [
                              Text(
                                'Erstellt von Enrico R. Matzke',
                                style: GoogleFonts.inter(
                                  fontSize: 14, 
                                  color: isDarkMode ? Colors.white70 : Colors.black87, // Adjusted text color for readability
                                ),
                                textAlign: TextAlign.center,
                              ),
                              Text(
                                'Frontend version: $_frontendVersion',
                                style: GoogleFonts.inter(
                                  fontSize: 14, 
                                  color: isDarkMode ? Colors.white70 : Colors.black87, // Adjusted text color for readability
                                ),
                                textAlign: TextAlign.center,
                              ),
                              Text(
                                'Backend version: $_backendVersion',
                                style: GoogleFonts.inter(
                                  fontSize: 14, 
                                  color: isDarkMode ? Colors.white70 : Colors.black87, // Adjusted text color for readability
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20), // Space above bottom nav bar (if any)
                  ],
                ),
              );
            }
          ),
        ],
      ),
    );
  }

  // Helper method to build a management tile (now returns a Card)
  Widget _buildManagementTile(
    BuildContext context,
    String title, {
    IconData? icon,
    bool isComingSoon = false,
    bool showOnlyAdmin = false,
    VoidCallback? onTap, // Added onTap callback
  }) {
    // Only show the tile if conditions are met
    if (showOnlyAdmin && !_isAdmin()) {
      return const SizedBox.shrink(); // Hide if not admin and showOnlyAdmin is true
    }

    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0), // Add padding between cards
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        color: isDarkMode ? Colors.black : Colors.white, // Hintergrundfarbe der Karte
        child: ListTile(
          leading: icon != null ? Icon(icon, color: Theme.of(context).iconTheme.color) : null,
          title: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: isComingSoon && !_isAdmin() ? Colors.grey : Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          trailing: isComingSoon
              ? Text(
                  'Coming Soon',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: Colors.orange, // Highlight "Coming Soon"
                  ),
                )
              : null,
          onTap: isComingSoon
              ? null // Disable tap if coming soon
              : onTap, // Use the provided onTap callback
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart'; // Import for GoogleFonts
import 'package:provider/provider.dart';
import 'dart:convert'; // Import for json.decode
import 'package:shared_preferences/shared_preferences.dart'; // For user role access

import '../auth/login_page.dart'; // Import LoginPage for navigation
import '../theme_manager.dart'; // Import ThemeNotifier

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


  @override
  void initState() {
    super.initState();
    _loadUserRole().then((_) { // Load user role on init
      _fetchAppSettings(); // Fetch app settings (including logo path)
      _fetchVersions(); // Fetch frontend and backend versions
    });
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

  /// Fetches app settings, including logo path, from the backend.
  Future<void> _fetchAppSettings() async {
    try {
      // CORRECTED URL: Removed '/admin_settings' blueprint prefix
      final response = await http.get(Uri.parse('${widget.serverAddress}/api/admin_settings'));
      print('DEBUG (MorePage): App settings response status: ${response.statusCode}'); // Debug print
      print('DEBUG (MorePage): App settings response body: ${response.body}'); // Debug print

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] && data.containsKey('settings')) {
          setState(() {
            // Get logo_path from backend, similar to StartPage
            final String? logoPathFromBackend = data['settings']['logo_path']; 
            print('DEBUG (MorePage): Fetched logoPathFromBackend: $logoPathFromBackend'); // Debug print

            if (logoPathFromBackend != null && logoPathFromBackend.isNotEmpty) {
              // Check if the path is already an absolute URL
              if (logoPathFromBackend.startsWith('http://') || logoPathFromBackend.startsWith('https://')) {
                _logoFullPath = logoPathFromBackend;
              } else {
                // If it's a relative path (e.g., img/logo.png or /static/img/logo.png)
                // Ensure there's exactly one slash between serverAddress and logoPathFromBackend
                String serverAddress = widget.serverAddress;
                String cleanedLogoPath = logoPathFromBackend;

                // Remove trailing slash from serverAddress if present
                if (serverAddress.endsWith('/')) {
                  serverAddress = serverAddress.substring(0, serverAddress.length - 1);
                }
                // Remove leading slash from logoPathFromBackend if present (if it's /static/...)
                if (cleanedLogoPath.startsWith('/')) {
                  cleanedLogoPath = cleanedLogoPath.substring(1);
                }
                _logoFullPath = '$serverAddress/$cleanedLogoPath';
              }
            } else {
              _logoFullPath = null; // No logo path provided
            }
            print('DEBUG (MorePage): Final _logoFullPath for display: $_logoFullPath'); // Debug print
          });
        } else {
          print('DEBUG (MorePage): App settings API returned success=false or missing settings. Message: ${data['message']}'); // Debug print
        }
      } else {
        print('DEBUG (MorePage): Error fetching app settings HTTP: ${response.statusCode} - ${response.reasonPhrase}'); // Debug print
      }
    } catch (e) {
      // Handle error, e.g., show a snackbar or log it
      print('DEBUG (MorePage): Exception fetching app settings: $e'); // Debug print
    }
  }

  /// Fetches frontend and backend versions from the backend.
  Future<void> _fetchVersions() async {
    try {
      final response = await http.get(Uri.parse('${widget.serverAddress}/api/versions'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            _frontendVersion = data['frontend_version'] ?? 'N/A';
            _backendVersion = data['backend_version'] ?? 'N/A';
          });
        }
      }
    } catch (e) {
      print('Error fetching versions: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context, listen: false);
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    if (_isLoadingRole) {
      return const Center(child: CircularProgressIndicator());
    }

    // Determine the final URL for the logo
    // This logic is now handled in _fetchAppSettings, _logoFullPath will be the final URL
    // String? finalLogoUrl;
    // if (_logoUrl != null) {
    //   // If the URL is relative (starts with / but not http/https), prepend serverAddress
    //   if (!_logoUrl!.startsWith('http://') && !_logoUrl!.startsWith('https://') && _logoUrl!.startsWith('/')) {
    //     finalLogoUrl = '${widget.serverAddress}${_logoUrl!}';
    //   } else {
    //     finalLogoUrl = _logoUrl; // Otherwise, use it as is (assumed to be a full URL)
    //   }
    // }

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
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
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
              color: isDarkMode ? Colors.black : Theme.of(context).cardColor,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildManagementTile(
                      context,
                      'Benutzer verwalten',
                      icon: Icons.people_alt,
                      isComingSoon: true,
                      showOnlyAdmin: true,
                      // Implement onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => UserManagementPage(serverAddress: widget.serverAddress))),
                    ),
                    _buildManagementTile(
                      context,
                      'Stände verwalten',
                      icon: Icons.store,
                      isComingSoon: true,
                      showOnlyAdmin: true,
                      // Implement onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => StandManagementPage(serverAddress: widget.serverAddress))),
                    ),
                    _buildManagementTile(
                      context,
                      'Kriterien verwalten',
                      icon: Icons.rule,
                      isComingSoon: true,
                      showOnlyAdmin: true,
                      // Implement onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => CriterionManagementPage(serverAddress: widget.serverAddress))),
                    ),
                    _buildManagementTile(
                      context,
                      'Räume verwalten',
                      icon: Icons.meeting_room,
                      isComingSoon: true,
                      showOnlyAdmin: true,
                      // Implement onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => RoomManagementPage(serverAddress: widget.serverAddress))),
                    ),
                    _buildManagementTile(
                      context,
                      'Listen verwalten',
                      icon: Icons.list_alt,
                      isComingSoon: true,
                      showOnlyAdmin: true,
                      // Implement onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ListManagementPage(serverAddress: widget.serverAddress))),
                    ),
                  ],
                ),
              ),
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
              child: Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: Column(
                  children: [
                    Text(
                      'Erstellt von Enrico R. Matzke',
                      style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      'Frontend version: $_frontendVersion',
                      style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      'Backend version: $_backendVersion',
                      style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20), // Space above bottom nav bar (if any)
          ],
        ),
      ),
    );
  }

  // Helper method to build a management tile
  Widget _buildManagementTile(
    BuildContext context,
    String title, {
    IconData? icon,
    bool isComingSoon = false,
    bool showOnlyAdmin = false,
  }) {
    // Only show the tile if conditions are met
    if (showOnlyAdmin && !_isAdmin()) {
      return const SizedBox.shrink(); // Hide if not admin and showOnlyAdmin is true
    }

    return Column(
      children: [
        ListTile(
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
              : () {
                  // TODO: Implement navigation to specific management pages
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$title - Funktion in Kürze verfügbar!'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
        ),
        const Divider(height: 1, indent: 16, endIndent: 16), // Separator
      ],
    );
  }
}

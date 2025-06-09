import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart'; // For date and time formatting
import 'package:shared_preferences/shared_preferences.dart'; // Import for SharedPreferences

// WICHTIG: Sicherstellen, dass diese Pfade korrekt sind und die Dateien existieren
import '../pages/my_evaluations_page.dart'; // Direct import from pages
import '../pages/ranking_page.dart'; // Direct import from pages
// Direct import from pages

/// The 'Start' page, displayed as the first tab in the bottom navigation.
/// It fetches and displays dashboard information like app title, logo,
/// user's evaluation count, current date/time, top rankings, and open rooms.
class StartPage extends StatefulWidget {
  final String serverAddress;
  // New: Callback function to request a tab change in HomePage
  final Function(int) onTabChangeRequested; 

  const StartPage({
    super.key, 
    required this.serverAddress,
    required this.onTabChangeRequested, // Add to constructor
  });

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  // State variables for fetched data
  String _appTitle = 'Stand App'; // Default value, will be updated from server
  String? _logoFullPath; // Changed to store the full path from server, not relative
  int _myEvaluationsCount = 0;
  List<dynamic> _topRankings = [];
  int _openRoomsCount = 0; // Number of rooms that haven't been inspected (timestamp is null)
  String? _userRole; // New state variable for user role
  String? _sessionCookie; // New state variable for session cookie

  bool _isLoading = true;
  String? _errorMessage;

  // New state variables for dynamic gradient colors
  Color _gradientColor1 = Colors.blue.shade50; // Default light mode start color
  Color _gradientColor2 = Colors.blue.shade200; // Default light mode end color
  Color _darkGradientColor1 = Colors.black; // Default dark mode start color
  Color _darkGradientColor2 = Colors.blueGrey; // Default dark mode end color

  @override
  void initState() {
    super.initState();
    _loadSessionCookie().then((_) { // Load cookie first
      _fetchDashboardData(); // Then fetch dashboard data (which now includes role loading)
    });
  }

  /// Loads the user's role from SharedPreferences.
  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userRole = prefs.getString('userRole');
      print('DEBUG: User role loaded: $_userRole'); // Debug print
    });
  }

  /// Loads the session cookie from SharedPreferences.
  Future<void> _loadSessionCookie() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sessionCookie = prefs.getString('sessionCookie');
      print('DEBUG: Session cookie loaded: $_sessionCookie'); // Debug print
    });
  }

  /// Helper function to get headers with the session cookie.
  Map<String, String> _getAuthHeaders() {
    final Map<String, String> headers = {};
    if (_sessionCookie != null) {
      headers['Cookie'] = _sessionCookie!;
    }
    return headers;
  }

  /// Converts a hex color string (e.g., "#RRGGBB") to a Flutter Color object.
  Color _hexToColor(String hexString) {
    // Remove '#' if present
    final String hex = hexString.replaceAll('#', '');
    // Parse the hex string to an integer, then create a Color object
    // Add 'ff' for full opacity if not already present
    return Color(int.parse('ff$hex', radix: 16));
  }

  /// Extracts the base host from a given URL, removing protocol, port, and subdomains.
  /// Examples:
  /// "http://192.168.188.118:5000" -> "192.168.188.118"
  /// "https://site1.example.com/path" -> "example.com"
  /// "iamcriptic.eu.pythonanywhere.com" -> "pythonanywhere.com"
  String _getBaseHost(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;

      // Check if it's an IP address (simple check, might need more robust regex for full validation)
      if (RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host)) {
        return host; // It's an IP, return as is
      }

      // For domain names, extract the base domain (e.g., example.com from site1.example.com)
      final parts = host.split('.');
      if (parts.length >= 2) {
        return '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
      }
      return host; // Fallback if less than 2 parts or unexpected format
    } catch (e) {
      print('Error parsing URL for base host: $e');
      return url; // Return original URL on error
    }
  }

  /// Fetches all necessary dashboard data concurrently from the Flask backend.
  Future<void> _fetchDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // FIRST: Reload user role to ensure the most current permissions
    await _loadUserRole();

    try {
      final headers = _getAuthHeaders(); // Get headers with cookie

      // Fetch data concurrently with headers
      final Future<http.Response> adminSettingsFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/admin_settings'), headers: headers);
      final Future<http.Response> myEvaluationsFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/my_evaluations'), headers: headers);
      final Future<http.Response> rankingDataFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/ranking_data'), headers: headers);
      final Future<http.Response> roomInspectionsFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/room_inspections'), headers: headers);

      // Wait for all futures to complete
      final List<http.Response> responses = await Future.wait([
        adminSettingsFuture,
        myEvaluationsFuture,
        rankingDataFuture,
        roomInspectionsFuture,
      ]);

      // Process Admin Settings
      final adminSettingsResponse = responses[0];
      if (adminSettingsResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(adminSettingsResponse.body);
        if (data['success']) {
          setState(() {
            _appTitle = data['settings']['index_title_text'] ?? 'Stand App';
            final String? logoPathFromBackend = data['settings']['logo_path'];

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
                // Remove leading slash from logoPathFromBackend if present
                if (cleanedLogoPath.startsWith('/')) {
                  cleanedLogoPath = cleanedLogoPath.substring(1);
                }
                _logoFullPath = '$serverAddress/$cleanedLogoPath';
              }
            } else {
              _logoFullPath = null; // No logo path provided
            }
            print('DEBUG: Generated logo URL: $_logoFullPath'); // Debug output for the final URL

            // Update gradient colors from backend settings
            _gradientColor1 = _hexToColor(data['settings']['bg_gradient_color1'] ?? '#E3F2FD'); // Default to light blue
            _gradientColor2 = _hexToColor(data['settings']['bg_gradient_color2'] ?? '#BBDEFB'); // Default to lighter blue
            _darkGradientColor1 = _hexToColor(data['settings']['dark_bg_gradient_color1'] ?? '#000000'); // Default to black
            _darkGradientColor2 = _hexToColor(data['settings']['dark_bg_gradient_color2'] ?? '#455A64'); // Default to dark blue grey
          });
        }
      } else {
        print('Error fetching admin settings: ${adminSettingsResponse.statusCode}');
      }

      // Process My Evaluations
      final myEvaluationsResponse = responses[1];
      if (myEvaluationsResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(myEvaluationsResponse.body);
        if (data['success'] && data['evaluations'] is List) {
          setState(() {
            _myEvaluationsCount = data['evaluations'].length;
          });
        }
      } else {
        print('Error fetching my evaluations: ${myEvaluationsResponse.statusCode}');
      }

      // Process Ranking Data
      final rankingDataResponse = responses[2];
      if (rankingDataResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(rankingDataResponse.body);
        if (data['success'] && data['rankings'] is List) {
          setState(() {
            // Take top 3 rankings
            _topRankings = data['rankings'].take(3).toList();
          });
        }
      } else {
        print('Error fetching ranking data: ${rankingDataResponse.statusCode}');
      }

      // Process Room Inspections
      final roomInspectionsResponse = responses[3];
      if (roomInspectionsResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(roomInspectionsResponse.body);
        if (data['success'] && data['room_inspections'] is List) {
          setState(() {
            _openRoomsCount = data['room_inspections'].where((room) => room['inspection_timestamp'] == null).length;
          });
        }
      } else {
        print('Error fetching room inspections: ${roomInspectionsResponse.statusCode}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Fehler beim Laden der Daten: $e';
      });
      print('Dashboard data fetch error: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Helper widget to display a dashboard card
  Widget _buildDashboardCard({
    required BuildContext context,
    required String title,
    required Widget content,
    VoidCallback? onTap,
    double? flexValue, // New parameter for flex value
  }) {
    // Determine card background color based on theme
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color cardBackgroundColor = isDarkMode ? Colors.black : Colors.white; // Fixed to black/white

    return Expanded( // Always wrap in Expanded to ensure proper layout
      flex: (flexValue ?? 1).toInt(), // Use provided flexValue or default to 1
      child: Card(
        margin: const EdgeInsets.all(8.0),
        color: cardBackgroundColor, // Apply the determined card background color
        elevation: 4.0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12.0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 14, // Reduced font size for card titles
                    fontWeight: FontWeight.bold,
                    // Text color adapted to theme
                    color: Theme.of(context).textTheme.headlineSmall?.color, 
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(child: Center(child: content)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Checks if the current user has any of the required roles.
  bool _userHasRequiredRole(List<String> requiredRoles) {
    print('DEBUG: Checking role. Current role: $_userRole, Required roles: $requiredRoles'); // Debug print
    if (_userRole == null) return false;
    return requiredRoles.contains(_userRole);
  }

  @override
  Widget build(BuildContext context) {
    // Current date and time
    final String currentDateTime = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());

    // Get the display version of the server address
    final String displayServerAddress = _getBaseHost(widget.serverAddress);

    // Define the gradients based on current theme brightness using fetched colors
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
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

    return Scaffold(
      // Set Scaffold's background color to transparent to allow the gradient to show through
      backgroundColor: Colors.transparent, 
      body: Stack( // Use Stack to layer the background and content
        children: [
          // Background Gradient Container (fills the entire Scaffold body)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: backgroundGradient, // Apply the determined gradient
              ),
            ),
          ),
          // Foreground Content (RefreshIndicator and SingleChildScrollView)
          RefreshIndicator(
            onRefresh: _fetchDashboardData, // This will now reload the role as well
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(), // Allow pull-to-refresh
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight, // Ensure it takes full height
                              ),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
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
                                        onPressed: _fetchDashboardData,
                                        child: const Text('Erneut versuchen'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                      )
                    : LayoutBuilder( // Use LayoutBuilder to get constraints
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(), // Allow pull-to-refresh even if content is small
                            child: ConstrainedBox( // Ensures content takes full height
                              constraints: BoxConstraints(
                                // Only subtract bottom navigation bar height from max height
                                minHeight: constraints.maxHeight - kBottomNavigationBarHeight,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // App Title & Logo Section
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 16.0), // Padding adjusted
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween, // Distribute title and logo
                                        crossAxisAlignment: CrossAxisAlignment.start, // Align to top
                                        children: [
                                          // App Title (left)
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start, // Align title to start
                                              children: [
                                                Text(
                                                  _appTitle, // Dynamically set from admin settings
                                                  style: GoogleFonts.inter(
                                                    fontSize: 28,
                                                    fontWeight: FontWeight.bold,
                                                    color: Theme.of(context).textTheme.headlineLarge?.color,
                                                  ),
                                                  textAlign: TextAlign.left, // Ensure text aligns left
                                                ),
                                                Text(
                                                  'Server: $displayServerAddress', // Use the cleaned display address
                                                  style: GoogleFonts.inter(
                                                    fontSize: 14,
                                                    color: Colors.grey[600],
                                                  ),
                                                  textAlign: TextAlign.left, // Ensure text aligns left
                                                ),
                                              ],
                                            ),
                                          ),
                                          
                                          // Logo Display (right)
                                          if (_logoFullPath != null && _logoFullPath!.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(left: 16.0), // Add left padding to separate from title
                                              child: Image.network(
                                                _logoFullPath!, // Use _logoFullPath directly
                                                height: 80, // Adjust height as needed for top-right placement
                                                width: 80, // Add width for square shape, adjust as needed
                                                fit: BoxFit.contain, // Ensures image fits without cropping
                                                // IMPORTANT: Added a ValueKey to force image reload
                                                key: ValueKey(_logoFullPath), 
                                                errorBuilder: (context, error, stackTrace) =>
                                                    // Fallback if image fails to load
                                                    Icon(Icons.business, size: 80, color: Theme.of(context).iconTheme.color),
                                              ),
                                            )
                                          else
                                            // Default fallback icon if no URL is provided
                                            Icon(Icons.business, size: 80, color: Theme.of(context).iconTheme.color),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 30),

                                    // Row for My Evaluations and Current Date/Time
                                    SizedBox(
                                      height: 150, // Fixed height for this row of cards
                                      child: Row(
                                        children: [
                                          // Conditional display for "Meine Bewertungen"
                                          if (_userHasRequiredRole(['Administrator', 'Bewerter']))
                                          _buildDashboardCard(
                                            context: context,
                                            title: 'Meine Bewertungen',
                                            content: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  'Anzahl',
                                                  style: GoogleFonts.inter(fontSize: 12), // Reduced font size to 12
                                                ),
                                                Text(
                                                  '$_myEvaluationsCount',
                                                  style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold), 
                                                ),
                                              ],
                                            ),
                                            onTap: () {
                                              // Navigate to My Evaluations Page
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => MyEvaluationsPage(serverAddress: widget.serverAddress),
                                                ),
                                              );
                                            },
                                            flexValue: 1, // Set flex to 1 for this card
                                          )
                                          else
                                            // Empty space or placeholder if "Meine Bewertungen" is not shown
                                            const SizedBox.shrink(), // No visible widget if role doesn't match

                                          // Conditionally render the date/time card to take full width
                                          if (_userHasRequiredRole(['Administrator', 'Bewerter']))
                                            _buildDashboardCard(
                                              context: context,
                                              title: 'Aktuelles Datum & Uhrzeit',
                                              content: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    currentDateTime.split(' ')[0], // Date part
                                                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold), 
                                                  ),
                                                  Text(
                                                    currentDateTime.split(' ')[1], // Time part
                                                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold), 
                                                  ),
                                                ],
                                              ),
                                              flexValue: 1, // Set flex to 1 for this card
                                            )
                                          else
                                            // If "Meine Bewertungen" is not shown, make the date/time card take full width
                                            _buildDashboardCard(
                                              context: context,
                                              title: 'Aktuelles Datum & Uhrzeit',
                                              content: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    currentDateTime.split(' ')[0], // Date part
                                                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold), 
                                                  ),
                                                  Text(
                                                    currentDateTime.split(' ')[1], // Time part
                                                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold), 
                                                  ),
                                                ],
                                              ),
                                              flexValue: 2, // Take full width if only one card
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 20),

                                    // Ranking Section
                                    SizedBox(
                                      height: 200, // Fixed height for ranking card
                                      child: _buildDashboardCard(
                                        context: context,
                                        title: 'Rangliste',
                                        content: _topRankings.isEmpty
                                            ? Center(
                                                child: Text(
                                                  'Keine Ranglistendaten verfügbar.',
                                                  style: GoogleFonts.inter(color: Colors.grey),
                                                  textAlign: TextAlign.center,
                                                ),
                                              )
                                            : ListView.builder(
                                                itemCount: _topRankings.length,
                                                itemBuilder: (context, index) {
                                                  final ranking = _topRankings[index];
                                                  return Padding(
                                                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        Text(
                                                          '${ranking['rank']}. ${ranking['stand_name']}',
                                                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
                                                        ),
                                                        Text(
                                                          '${ranking['total_achieved_score']} Punkte',
                                                          style: GoogleFonts.inter(fontSize: 16),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                        onTap: () {
                                          // Navigate to Ranking Page
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => RankingPage(serverAddress: widget.serverAddress),
                                            ),
                                          );
                                        },
                                        flexValue: 1, // Set flex to 1 for this card
                                      ),
                                    ),
                                    const SizedBox(height: 20),

                                    // Conditional display for "Offene Räume"
                                    if (_userHasRequiredRole(['Administrator', 'Inspektor']))
                                    SizedBox(
                                      height: 150, // Fixed height for open rooms card
                                      child: _buildDashboardCard(
                                        context: context,
                                        title: 'Offene Räume',
                                        content: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Anzahl',
                                              style: GoogleFonts.inter(fontSize: 12), // Reduced font size to 12
                                            ),
                                            Text(
                                              '$_openRoomsCount',
                                              style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: _openRoomsCount > 0 ? Colors.red : Theme.of(context).textTheme.headlineLarge?.color), 
                                            ),
                                          ],
                                        ),
                                        onTap: () {
                                          // Changed: Instead of pushing a new route, request HomePage to change tab
                                          widget.onTabChangeRequested(1); // Index 1 is for 'Räume'
                                        },
                                        flexValue: 1, // Set flex to 1 for this card
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                      ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart'; // For date and time formatting
import 'package:shared_preferences/shared_preferences.dart'; // Import for SharedPreferences

// WICHTIG: Sicherstellen, dass diese Pfade korrekt sind und die Dateien existieren
import '../pages/my_evaluations_page.dart'; // Direct import from pages
import '../pages/ranking_page.dart'; // Direct import from pages
import '../pages/rooms_page.dart'; // Direct import from pages

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

  @override
  void initState() {
    super.initState();
    _loadSessionCookie().then((_) { // Load cookie first
      _loadUserRole().then((_) { // Then load user role
        _fetchDashboardData(); // Then fetch dashboard data
      });
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
    Color? backgroundColor,
  }) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      color: backgroundColor ?? Theme.of(context).cardColor,
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
                  color: Theme.of(context).textTheme.headlineSmall?.color,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(child: Center(child: content)),
            ],
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

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _fetchDashboardData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
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
                  )
                : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(), // Allow pull-to-refresh even if content is small
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
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
                                Expanded(
                                  child: _buildDashboardCard(
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
                                  ),
                                ),
                                // Ensure consistent layout even if card is hidden by using Spacer conditionally
                                if (!_userHasRequiredRole(['Administrator', 'Bewerter']))
                                  const Spacer(), // Use Spacer to take up space if first card is not shown

                                Expanded(
                                  child: _buildDashboardCard(
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
                                  ),
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
                            ),
                          ),
                          const SizedBox(height: 20), // Add padding at the bottom of the column
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}

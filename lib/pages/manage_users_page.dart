import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // For SharedPreferences and session cookie

/// Represents a user for display and management.
class User {
  final int id;
  final String username;
  final String displayName;
  final List<String> roleNames;
  final List<int> roleIds;

  User({
    required this.id,
    required this.username,
    required this.displayName,
    required this.roleNames,
    required this.roleIds,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    // Robust parsing for role_names:
    // Checks if json['role_names'] exists and if it's a String or a List.
    // If null or not String/List, an empty list is used.
    List<String> parsedRoleNames = [];
    if (json['role_names'] != null) {
      if (json['role_names'] is String) {
        parsedRoleNames = (json['role_names'] as String)
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList();
      } else if (json['role_names'] is List) {
        // If the backend already provides it as a list (e.g., [] for no roles)
        parsedRoleNames = (json['role_names'] as List)
            .map((e) => e.toString()) // Convert elements to String
            .where((s) => s.isNotEmpty)
            .toList();
      }
    }

    // Robust parsing for role_ids:
    // Checks if json['role_ids'] exists and if it's a String or a List.
    // If null or not String/List, an empty list is used.
    List<int> parsedRoleIds = [];
    if (json['role_ids'] != null) {
      if (json['role_ids'] is String) {
        parsedRoleIds = (json['role_ids'] as String)
            .split(',')
            .where((s) => s.isNotEmpty)
            .map(int.tryParse) // Safely parse and handle null values
            .whereType<int>() // Keep only valid integer values
            .toList();
      } else if (json['role_ids'] is List) {
        // If the backend already provides it as a list
        parsedRoleIds = (json['role_ids'] as List)
            .map((e) => int.tryParse(e.toString())) // Convert elements to String and parse
            .whereType<int>()
            .toList();
      }
    }

    return User(
      id: json['id'],
      username: json['username'],
      displayName: json['display_name'],
      roleNames: parsedRoleNames,
      roleIds: parsedRoleIds,
    );
  }
}

/// Represents a role for display and selection.
class Role {
  final int id;
  final String name;

  Role({required this.id, required this.name});

  factory Role.fromJson(Map<String, dynamic> json) {
    return Role(
      id: json['id'],
      name: json['name'],
    );
  }

  // For use in lists and for comparison (e.g., in ChoiceChip)
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Role && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// The page for managing users.
class ManageUsersPage extends StatefulWidget {
  final String serverAddress;
  const ManageUsersPage({super.key, required this.serverAddress});

  @override
  State<ManageUsersPage> createState() => _ManageUsersPageState();
}

class _ManageUsersPageState extends State<ManageUsersPage> {
  // State variables for dynamic gradient colors from server
  Color _gradientColor1 = Colors.blue.shade50; // Default light mode start color
  Color _gradientColor2 = Colors.blue.shade200; // Default light mode end color
  Color _darkGradientColor1 = Colors.black; // Default dark mode start color
  Color _darkGradientColor2 = Colors.blueGrey; // Default dark mode end color

  bool _isLoading = true;
  String? _errorMessage;
  List<User> _users = [];
  List<Role> _roles = [];
  String? _sessionCookie; // Stores the session cookie for authenticated requests
  String? _userRole; // To store the current user's role

  // Controllers for creating a new user
  final TextEditingController _newUsernameController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _newDisplayNameController = TextEditingController();
  final List<Role> _selectedNewRoles = []; // For multiselect dropdown

  // Controllers for editing an existing user
  final TextEditingController _editDisplayNameController = TextEditingController();
  final TextEditingController _editPasswordController = TextEditingController();
  List<Role> _selectedEditRoles = []; // For multiselect dropdown
  User? _userToEdit; // Stores the user currently being edited

  @override
  void initState() {
    super.initState();
    _loadSessionCookie().then((_) {
      _loadUserRole().then((_) {
        _fetchPageData(); // Fetch all data after roles are loaded
      });
    });
  }

  @override
  void dispose() {
    _newUsernameController.dispose();
    _newPasswordController.dispose();
    _newDisplayNameController.dispose();
    _editDisplayNameController.dispose();
    _editPasswordController.dispose();
    super.dispose();
  }

  /// Loads the session cookie from SharedPreferences.
  Future<void> _loadSessionCookie() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionCookie = prefs.getString('sessionCookie');
    print('DEBUG (Flutter): Session cookie loaded: $_sessionCookie');
  }

  /// Loads the user's role from SharedPreferences.
  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    _userRole = prefs.getString('userRole');
    print('DEBUG (Flutter): User role loaded: $_userRole');
  }

  /// Checks if the current user has any of the required roles.
  bool _userHasRequiredRole(List<String> requiredRoles) {
    if (_userRole == null) return false;
    return requiredRoles.contains(_userRole);
  }

  /// Converts a hex color string (e.g., "#RRGGBB") to a Flutter Color object.
  Color _hexToColor(String hexString) {
    final String hex = hexString.replaceAll('#', '');
    if (hex.length == 6) {
      return Color(int.parse('ff$hex', radix: 16));
    } else if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    print('WARN (Flutter): Invalid hex color string: $hexString. Returning grey.');
    return Colors.grey; // Default or error color
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

  /// Fetches all necessary data for the page (users, roles, and app settings).
  Future<void> _fetchPageData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Check role access immediately
    if (!_userHasRequiredRole(['Administrator'])) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Sie haben keine Berechtigung, auf diese Seite zuzugreifen.';
      });
      return;
    }

    try {
      final headers = _getAuthHeaders();

      final Future<http.Response> usersFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/users'), headers: headers);
      final Future<http.Response> rolesFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/roles'), headers: headers);
      final Future<http.Response> adminSettingsFuture =
          http.get(Uri.parse('${widget.serverAddress}/api/admin_settings'), headers: headers);

      final List<http.Response> responses =
          await Future.wait([usersFuture, rolesFuture, adminSettingsFuture]);

      // Process Users Response
      final usersResponse = responses[0];
      print('DEBUG (Flutter): Users API response status: ${usersResponse.statusCode}');
      print('DEBUG (Flutter): Users API response body: ${usersResponse.body}');
      if (usersResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(usersResponse.body);
        if (data['success']) {
          _users = (data['users'] as List)
              .map((u) => User.fromJson(u))
              .where((user) => user.username != 'admin') // Exclude 'admin' user
              .toList();
        } else {
          _errorMessage = data['message'] ?? 'Fehler beim Laden der Benutzer.';
        }
      } else {
        _errorMessage =
            'Fehler ${usersResponse.statusCode}: ${usersResponse.reasonPhrase}';
        print(
            'Error fetching users: ${usersResponse.statusCode} - ${usersResponse.body}');
      }

      // Process Roles Response
      final rolesResponse = responses[1];
      print('DEBUG (Flutter): Roles API response status: ${rolesResponse.statusCode}');
      print('DEBUG (Flutter): Roles API response body: ${rolesResponse.body}');
      if (rolesResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(rolesResponse.body);
        if (data['success']) {
          _roles = (data['roles'] as List).map((r) => Role.fromJson(r)).toList();
        } else {
          _errorMessage =
              (_errorMessage ?? '') + (data['message'] ?? 'Fehler beim Laden der Rollen.');
        }
      } else {
        _errorMessage = '${_errorMessage ?? ''}Fehler ${rolesResponse.statusCode}: ${rolesResponse.reasonPhrase}';
        print(
            'Error fetching roles: ${rolesResponse.statusCode} - ${rolesResponse.body}');
      }

      // Process Admin Settings Response
      final adminSettingsResponse = responses[2];
      print('DEBUG (Flutter): Admin Settings API response status: ${adminSettingsResponse.statusCode}');
      print('DEBUG (Flutter): Admin Settings API response body: ${adminSettingsResponse.body}');
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
        print(
            'Error fetching admin settings for gradient: ${adminSettingsResponse.statusCode}');
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

  /// Creates a new user.
  Future<void> _createUser() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (_newUsernameController.text.isEmpty ||
        _newPasswordController.text.isEmpty ||
        _newDisplayNameController.text.isEmpty ||
        _selectedNewRoles.isEmpty) {
      _showAlertDialog('Fehler', 'Bitte fülle alle Felder aus und wähle mindestens eine Rolle aus.');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final headers = _getAuthHeaders();
    final requestBody = json.encode({
      'username': _newUsernameController.text.trim(),
      'password': _newPasswordController.text,
      'display_name': _newDisplayNameController.text.trim(),
      'role_ids': _selectedNewRoles.map((role) => role.id).toList(),
    });
    print('DEBUG (Flutter): Sending create user request body: $requestBody');

    try {
      final response = await http.post(
        Uri.parse('${widget.serverAddress}/api/users'),
        headers: headers,
        body: requestBody,
      );

      final Map<String, dynamic> data = json.decode(response.body);
      print('DEBUG (Flutter): Create user response status: ${response.statusCode}');
      print('DEBUG (Flutter): Create user response body: ${response.body}');
      if (response.statusCode == 201 && data['success']) {
        _showAlertDialog('Erfolg', data['message']);
        _newUsernameController.clear();
        _newPasswordController.clear();
        _newDisplayNameController.clear();
        setState(() {
          _selectedNewRoles.clear(); // Clear selected roles in UI
        });
        _fetchPageData(); // Refresh user list
      } else {
        _showAlertDialog('Fehler', data['message'] ?? 'Fehler beim Anlegen des Benutzers.');
      }
    } catch (e) {
      _showAlertDialog('Verbindungsfehler', 'Fehler beim Anlegen des Benutzers: $e');
      print('ERROR (Flutter): Exception creating user: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Edits an existing user.
  Future<void> _editUser() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (_userToEdit == null ||
        _editDisplayNameController.text.isEmpty ||
        _selectedEditRoles.isEmpty) {
      _showAlertDialog('Fehler', 'Bitte fülle alle erforderlichen Felder aus und wähle mindestens eine Rolle aus.');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final headers = _getAuthHeaders();
    final requestBody = json.encode({
      'id': _userToEdit!.id,
      'display_name': _editDisplayNameController.text.trim(),
      'password': _editPasswordController.text.isEmpty
          ? null
          : _editPasswordController.text,
      'role_ids': _selectedEditRoles.map((role) => role.id).toList(),
    });
    print('DEBUG (Flutter): Sending edit user request body: $requestBody');

    try {
      final response = await http.put(
        Uri.parse('${widget.serverAddress}/api/users'),
        headers: headers,
        body: requestBody,
      );

      final Map<String, dynamic> data = json.decode(response.body);
      print('DEBUG (Flutter): Edit user response status: ${response.statusCode}');
      print('DEBUG (Flutter): Edit user response body: ${response.body}');
      if (response.statusCode == 200 && data['success']) {
        // Only close the dialog if the API call was successful
        // We'll show the alert first, then close the dialog when the alert is dismissed
        _showAlertDialog('Erfolg', data['message']).then((_) {
          Navigator.of(context).pop(); // Close modal after alert is dismissed
        });
        _fetchPageData(); // Refresh user list
      } else {
        _showAlertDialog('Fehler', data['message'] ?? 'Fehler beim Aktualisieren des Benutzers.');
      }
    } catch (e) {
      _showAlertDialog('Verbindungsfehler', 'Fehler beim Aktualisieren des Benutzers: $e');
      print('ERROR (Flutter): Exception editing user: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Deletes a user.
  Future<void> _deleteUser(int userId, String username) async {
    if (username == 'admin') {
      _showAlertDialog('Fehler', 'Der "admin"-Benutzer kann nicht gelöscht werden.');
      return;
    }

    final bool confirmDelete = await _showConfirmationDialog(
        'Benutzer löschen', 'Möchten Sie den Benutzer "$username" wirklich löschen?');
    if (!confirmDelete) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final headers = _getAuthHeaders();
    print('DEBUG (Flutter): Sending delete user request for ID: $userId');

    try {
      final response = await http.delete(
        Uri.parse('${widget.serverAddress}/api/users?id=$userId'),
        headers: headers,
      );

      final Map<String, dynamic> data = json.decode(response.body);
      print('DEBUG (Flutter): Delete user response status: ${response.statusCode}');
      print('DEBUG (Flutter): Delete user response body: ${response.body}');
      if (response.statusCode == 200 && data['success']) {
        _showAlertDialog('Erfolg', data['message']);
        _fetchPageData(); // Refresh user list
      } else {
        _showAlertDialog('Fehler', data['message'] ?? 'Fehler beim Löschen des Benutzers.');
      }
    } catch (e) {
      _showAlertDialog('Verbindungsfehler', 'Fehler beim Löschen des Benutzers: $e');
      print('ERROR (Flutter): Exception deleting user: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Displays an alert dialog for messages.
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

  /// Displays a confirmation dialog and returns true if confirmed, false otherwise.
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
        false; // Return false if dialog is dismissed
  }

  /// Shows the edit user modal with pre-filled data.
  void _showEditUserModal(User user) {
    setState(() {
      _userToEdit = user;
      _editDisplayNameController.text = user.displayName;
      _editPasswordController.clear(); // Clear password field for security
      // Ensure that _selectedEditRoles is populated with actual Role objects
      // that match the roleIds of the user being edited.
      _selectedEditRoles = List.from(_roles.where((role) => user.roleIds.contains(role.id)));
    });

    showDialog(
      context: context,
      builder: (BuildContext context) {
        final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor:
              isDarkMode ? Colors.black : Colors.white, // Match app theme
          title: Text(
              'Benutzer bearbeiten: ${user.username}',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.headlineMedium?.color)),
          content: SingleChildScrollView( // Changed to SingleChildScrollView to prevent overflow
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: TextEditingController(
                      text: user.username), // Read-only username
                  decoration: InputDecoration(
                    labelText: 'Benutzername',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabled: false, // Make it non-editable
                    fillColor: isDarkMode ? Colors.grey[900] : Colors.grey[200],
                    filled: true,
                  ),
                  style: GoogleFonts.inter(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _editDisplayNameController,
                  decoration: InputDecoration(
                    labelText: 'Anzeigename',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  style: GoogleFonts.inter(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _editPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Neues Passwort (optional)',
                    hintText: 'Leer lassen für aktuelles Passwort',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  style: GoogleFonts.inter(),
                ),
                const SizedBox(height: 16),
                // Workaround for multi-select dropdown (using Chip system)
                Text(
                  'Rollen (Mehrfachauswahl):',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodyLarge?.color),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8.0, // gap between adjacent chips
                    runSpacing: 4.0, // gap between lines
                    children: _roles.map((role) {
                      // Use a StatefulBuilder to manage the state of the chips locally within the dialog
                      return StatefulBuilder(
                        builder: (BuildContext context, StateSetter dialogSetState) {
                          final bool isSelected = _selectedEditRoles.contains(role);
                          return ChoiceChip(
                            label: Text(
                              role.name,
                              style: GoogleFonts.inter(
                                color: isSelected
                                    ? Colors.white
                                    : (isDarkMode ? Colors.white70 : Colors.black87),
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: Theme.of(context).primaryColor,
                            onSelected: (bool selected) {
                              dialogSetState(() { // Use dialogSetState to update the dialog's state
                                if (selected) {
                                  _selectedEditRoles.add(role);
                                } else {
                                  _selectedEditRoles.removeWhere((r) => r.id == role.id);
                                }
                              });
                            },
                            backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                          );
                        },
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  // Use a fixed width for the buttons to prevent wrapping text and control size
                  children: [
                    SizedBox(
                      width: 100, // Fixed width for "Abbrechen" button
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: Text('Abbrechen',
                            style: GoogleFonts.inter(
                                fontSize: 14, // Smaller font size
                                color: isDarkMode ? Colors.white70 : Colors.black87)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100, // Fixed width for "Speichern" button
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _editUser,
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero, // Remove default padding to allow smaller text
                          textStyle: GoogleFonts.inter(fontSize: 14), // Smaller font size for button text
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) // Smaller loading indicator
                            : Text('Speichern', style: GoogleFonts.inter(fontSize: 14)), // Ensure font size here too
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

    // Initial loading/access denied screen
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
                            'Benutzerverwaltung',
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
                            'Um hierdrauf zugreifen zu Können, brauchst du die Rolle Administrator. Bei Bedarf kannst du diese beim Organisator erfragen.',
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

    // Error message screen
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
                      'Benutzerverwaltung',
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

    // Main content when loaded and authorized
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
                  // Zurück-Pfeil und Titel in einer Row
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
                            'Benutzerverwaltung',
                            style: GoogleFonts.inter(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.headlineLarge?.color,
                            ),
                            textAlign: TextAlign.left, // Left-aligned title
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Create New User Section
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
                            'Neuen Benutzer anlegen',
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color:
                                  Theme.of(context).textTheme.headlineMedium?.color,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _newUsernameController,
                            decoration: InputDecoration(
                              labelText: 'Benutzername',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            style: GoogleFonts.inter(),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _newPasswordController,
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: 'Passwort',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            style: GoogleFonts.inter(),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _newDisplayNameController,
                            decoration: InputDecoration(
                              labelText: 'Anzeigename',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            style: GoogleFonts.inter(),
                          ),
                          const SizedBox(height: 16),
                          // Multi-select for Roles using Chips
                          Text(
                            'Rollen (Mehrfachauswahl):',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).textTheme.bodyLarge?.color),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8.0, // gap between adjacent chips
                            runSpacing: 4.0, // gap between lines
                            children: _roles.map((role) {
                              final bool isSelected = _selectedNewRoles.contains(role);
                              return ChoiceChip(
                                label: Text(
                                  role.name,
                                  style: GoogleFonts.inter(
                                    color: isSelected
                                        ? Colors.white
                                        : (isDarkMode
                                            ? Colors.white70
                                            : Colors.black87),
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: Theme.of(context).primaryColor,
                                onSelected: (bool selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedNewRoles.add(role);
                                    } else {
                                      _selectedNewRoles.removeWhere((r) => r.id == role.id);
                                    }
                                  });
                                },
                                backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : _createUser,
                              icon: const Icon(Icons.add_circle_outline),
                              label: Text('Benutzer anlegen',
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

                  // Existing Users Section
                  Text(
                    'Vorhandene Benutzer',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.headlineLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_users.isEmpty)
                    Center(
                      child: Text(
                        'Keine Benutzer gefunden.',
                        style:
                            GoogleFonts.inter(fontSize: 16, color: Colors.grey[600]),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _users.length,
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12.0), // Space between user cards
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
                                  user.username,
                                  style: GoogleFonts.inter(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).textTheme.headlineMedium?.color,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Anzeigename: ${user.displayName}',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    color: Theme.of(context).textTheme.bodyLarge?.color,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // Display roles: Check if roleNames is not empty before joining
                                Text(
                                  'Rollen: ${user.roleNames.isNotEmpty ? user.roleNames.join(', ') : 'Keine Rollen zugewiesen'}',
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
                                      onPressed: () => _showEditUserModal(user),
                                      tooltip: 'Benutzer bearbeiten',
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteUser(user.id, user.username),
                                      tooltip: 'Benutzer löschen',
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

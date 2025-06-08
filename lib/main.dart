import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For JSON encoding/decoding
import 'package:shared_preferences/shared_preferences.dart'; // For saving settings

// For the "Inter" font
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart'; // IMPORTANT: This import MUST be at the top!


// --- Theme Management ---
// A ChangeNotifier that manages the current ThemeMode
class ThemeNotifier extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system; // Default: System setting
  bool _isInitialized = false;

  ThemeMode get themeMode => _themeMode;

  // Initialize the theme from saved settings
  Future<void> initTheme() async {
    if (_isInitialized) return; // Initialize only once
    final prefs = await SharedPreferences.getInstance();
    final bool? isDarkMode = prefs.getBool('isDarkMode');
    if (isDarkMode != null) {
      _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;
    } else {
      _themeMode = ThemeMode.system; // Or default to Light if nothing is saved
    }
    _isInitialized = true;
    notifyListeners(); // Notify listeners about initialization
  }

  // Toggles the theme (Light/Dark)
  Future<void> toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (_themeMode == ThemeMode.light) {
      _themeMode = ThemeMode.dark;
      await prefs.setBool('isDarkMode', true);
    } else {
      _themeMode = ThemeMode.light;
      await prefs.setBool('isDarkMode', false);
    }
    notifyListeners(); // Notify listeners about the change
  }

  // Explicitly set to Light Mode
  Future<void> setLightMode() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = ThemeMode.light;
    await prefs.setBool('isDarkMode', false);
    notifyListeners();
  }

  // Explicitly set to Dark Mode
  Future<void> setDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = ThemeMode.dark;
    await prefs.setBool('isDarkMode', true);
    notifyListeners();
  }
}

// --- Main function of the App ---
void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensure Flutter is initialized
  final themeNotifier = ThemeNotifier();
  await themeNotifier.initTheme(); // Load the saved theme before starting

  runApp(
    ChangeNotifierProvider( // Allows access to ThemeNotifier throughout the widget tree
      create: (_) => themeNotifier,
      child: const MyApp(),
    ),
  );
}

// MyApp is our top-level widget that defines the Material Design structure
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Listen for changes in ThemeNotifier
    final themeNotifier = Provider.of<ThemeNotifier>(context);

    return MaterialApp(
      title: 'Stand App',
      // Define the Light Theme
      theme: ThemeData(
        primarySwatch: Colors.blue,
        primaryColor: Colors.blue, // Primary color for app bar etc.
        brightness: Brightness.light,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme.apply(
          bodyColor: Colors.grey[800], // Darker text for light mode
          displayColor: Colors.grey[800],
        )),
        scaffoldBackgroundColor: Colors.grey[100], // Background color like bg-gray-100
        cardColor: Colors.white, // Card background like bg-white
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blueAccent, // Match AppBar color
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.grey),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
          ),
          labelStyle: GoogleFonts.inter(color: Colors.grey[700]),
          hintStyle: GoogleFonts.inter(color: Colors.grey[500]),
          contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
            textStyle: GoogleFonts.inter(fontSize: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 5,
          ),
        ),
      ),
      // Define the Dark Theme
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        primaryColor: Colors.blueGrey[900], // Darker primary color for dark mode
        brightness: Brightness.dark,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme.apply(
          bodyColor: const Color(0xFFE2E8F0), // Lighter text like #e2e8f0
          displayColor: const Color(0xFFE2E8F0),
        )),
        scaffoldBackgroundColor: Colors.black, // OLED-optimized black as on the website
        cardColor: Colors.black, // Card background also black
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.blueGrey[900], // Darker AppBar background
          foregroundColor: const Color(0xFFE2E8F0),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF555555)), // Darker border
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.blue[300]!, width: 2),
          ),
          fillColor: const Color(0xFF1C1C1C), // Background color like #1c1c1c
          filled: true,
          labelStyle: GoogleFonts.inter(color: const Color(0xFFA0AEC0)), // Lighter label
          hintStyle: GoogleFonts.inter(color: Colors.grey),
          contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[700], // Darker blue tone for buttons
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
            textStyle: GoogleFonts.inter(fontSize: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 5,
          ),
        ),
      ),
      themeMode: themeNotifier.themeMode, // Use ThemeMode from the Notifier
      home: const LoginPage(),
    );
  }
}


// LoginPage is a StatefulWidget because it will change its state (text fields, loading status)
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _serverAddressController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false; // State to control the loading indicator
  String? _errorMessage; // For error messages
  bool _autoLoginAttempted = false; // To prevent multiple auto-login attempts

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedServerAddress = prefs.getString('serverAddress');
    final String? savedUsername = prefs.getString('username');
    final String? savedPassword = prefs.getString('password');

    if (savedServerAddress != null && savedUsername != null && savedPassword != null) {
      _serverAddressController.text = savedServerAddress;
      _usernameController.text = savedUsername;
      _passwordController.text = savedPassword;

      // Attempt auto-login if credentials are found
      // We wrap this in a Future.microtask to allow the UI to build first,
      // preventing "setState() called during build" errors.
      Future.microtask(() => _login(isAutoLogin: true));
    } else {
      // Set a default IP if no saved credentials are found
      _serverAddressController.text = 'http://10.0.2.2:5000'; // Default for Android Emulator
    }
  }

  Future<void> _saveCredentials(String serverAddress, String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverAddress', serverAddress);
    await prefs.setString('username', username);
    await prefs.setString('password', password);
  }

  Future<void> _clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('serverAddress');
    await prefs.remove('username');
    await prefs.remove('password');
  }

  @override
  void dispose() {
    // Dispose controllers to prevent memory leaks
    _serverAddressController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Function to send the login request to the Flask API
  Future<void> _login({bool isAutoLogin = false}) async {
    if (_isLoading) return; // Prevent multiple login attempts

    setState(() {
      _isLoading = true; // Show loading indicator
      _errorMessage = null; // Clear old error message
      if (isAutoLogin) _autoLoginAttempted = true; // Mark auto-login attempt
    });

    final String serverAddress = _serverAddressController.text.trim();
    final String username = _usernameController.text.trim();
    final String password = _passwordController.text.trim();

    if (serverAddress.isEmpty || username.isEmpty || password.isEmpty) {
      if (isAutoLogin) {
        // If auto-login fails due to missing credentials, don't show error
        // Just let the user fill in the fields manually
      } else {
        setState(() {
          _errorMessage = 'Bitte fülle alle Felder aus.';
        });
      }
      setState(() {
        _isLoading = false; // Hide loading indicator
      });
      return; // End function as inputs are missing
    }

    // Construct the full login URL
    final Uri loginUrl = Uri.parse('$serverAddress/login');

    try {
      final response = await http.post(
        loginUrl,
        headers: <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded', // Flask expects 'application/x-www-form-urlencoded' for form data
        },
        // Send data as form encoding, as your Flask login uses `request.form`
        body: {'username': username, 'password': password},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody = json.decode(response.body);
        if (responseBody['success'] == true) {
          // Login successful!
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(responseBody['message'])),
          );

          // Save credentials after successful login
          await _saveCredentials(serverAddress, username, password);

          if (responseBody['redirect_to_setup'] == true) {
            // If Admin setup is required
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => AdminSetupPage(serverAddress: serverAddress)),
            );
          } else {
            // Normal login
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => HomePage(serverAddress: serverAddress)), // Navigate to the main app page
            );
          }
        } else {
          setState(() {
            _errorMessage = responseBody['message'] ?? 'Login fehlgeschlagen.';
          });
          if (isAutoLogin) await _clearCredentials(); // Clear if auto-login failed
        }
      } else {
        // HTTP error (e.g., 401 Unauthorized)
        final Map<String, dynamic> errorBody = json.decode(response.body);
        setState(() {
          _errorMessage = errorBody['message'] ?? 'Ein unerwarteter Fehler ist aufgetreten. Status: ${response.statusCode}';
        });
        print('Login-Fehler: ${response.statusCode} - ${response.body}');
        if (isAutoLogin) await _clearCredentials(); // Clear if auto-login failed
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Verbindungsfehler: Bitte überprüfe die Server-URL und deine Internetverbindung. ($e)';
      });
      print('Ausnahme beim Login: $e');
      if (isAutoLogin) await _clearCredentials(); // Clear if auto-login failed
    } finally {
      setState(() {
        _isLoading = false; // Hide loading indicator
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Access ThemeNotifier
    final themeNotifier = Provider.of<ThemeNotifier>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anmelden'),
        // AppBar colors are now managed by ThemeData
        actions: [
          IconButton(
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode // Sun icon for Dark Mode
                  : Icons.dark_mode, // Moon icon for Light Mode
            ),
            onPressed: () {
              themeNotifier.toggleTheme(); // Toggle theme
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // Optional: App Logo
              // Add a logo here if you have one.
              // Example: Image.asset('assets/logo.png', height: 150),
              // Or from your Flask app, but note that this address also needs to be entered via the new field
              // Image.network(
              //   '${_serverAddressController.text.trim()}/static/img/logo_V2.png',
              //   height: 150,
              //   errorBuilder: (context, error, stackTrace) => Icon(Icons.business, size: 100), // Fallback icon
              // ),
              const SizedBox(height: 30),
              TextField(
                controller: _serverAddressController,
                decoration: const InputDecoration(
                  labelText: 'Server-Adresse (z.B. http://10.0.2.2:5000)',
                  prefixIcon: Icon(Icons.dns),
                ),
                keyboardType: TextInputType.url,
                style: GoogleFonts.inter(), // Apply Inter font
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Benutzername',
                  prefixIcon: Icon(Icons.person),
                ),
                style: GoogleFonts.inter(), // Apply Inter font
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: true, // Hide password
                decoration: const InputDecoration(
                  labelText: 'Passwort',
                  prefixIcon: Icon(Icons.lock),
                ),
                style: GoogleFonts.inter(), // Apply Inter font
              ),
              const SizedBox(height: 30),
              _isLoading
                  ? const CircularProgressIndicator() // Show loading indicator
                  : ElevatedButton(
                      onPressed: _login,
                      child: const Text('Anmelden'),
                    ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Text(
                    _errorMessage!,
                    style: GoogleFonts.inter(color: Colors.red, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Dummy Home page after successful login
class HomePage extends StatefulWidget {
  final String serverAddress;
  const HomePage({super.key, required this.serverAddress});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0; // The index of the currently selected tab

  // List of widgets (pages) for each tab
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = <Widget>[
      // Placeholder for 'Start' (Index 0)
      Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Willkommen auf der Startseite!',
              style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Verbunden mit: ${widget.serverAddress}',
              style: GoogleFonts.inter(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text(
              'Hier könnten Dashboard-Informationen angezeigt werden.',
              style: GoogleFonts.inter(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      // Placeholder for 'Räume' (Index 1)
      const Center(
        child: Text(
          'Raumkontrolle',
          style: TextStyle(fontSize: 24),
        ),
      ),
      // Placeholder for 'Bewerten' (Index 2, target for FAB)
      const Center(
        child: Text(
          'Bewertungsseite',
          style: TextStyle(fontSize: 24),
        ),
      ),
      // Placeholder for 'Warnungen' (Index 3)
      const Center(
        child: Text(
          'Verwarnungen',
          style: TextStyle(fontSize: 24),
        ),
      ),
      // Placeholder for 'Mehr' (Index 4)
      Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Mehr Optionen',
              style: TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 20),
            // Logout button in 'Mehr' tab
            ElevatedButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Abmelden'),
              onPressed: () async {
                // Clear saved credentials on logout
                await (context.findAncestorStateOfType<_LoginPageState>()?._clearCredentials() ?? Future.value());

                final Uri logoutUrl = Uri.parse('${widget.serverAddress}/api/logout');
                try {
                  final response = await http.get(logoutUrl);
                  if (response.statusCode == 200) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Erfolgreich abgemeldet.')),
                    );
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginPage()),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Fehler beim Abmelden. Status: ${response.statusCode}')),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Verbindungsfehler beim Abmelden: $e')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    ];
  }

  // Helper function to build a navigation item (icon + label)
  Widget _buildNavItem(BuildContext context, IconData icon, String label, int index) {
    final bool isSelected = _selectedIndex == index;
    final Color iconColor = isSelected ? Colors.white : Colors.blue[100]!;
    final Color textColor = isSelected ? Colors.white : Colors.blue[100]!;

    return Expanded(
      child: Material( // Use Material for ink splash effect
        color: Colors.transparent, // Make it transparent so the BottomAppBar color shines through
        child: InkWell( // For tap feedback
          onTap: () => _onItemTapped(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min, // Make column as small as possible
              children: [
                Icon(icon, color: iconColor),
                const SizedBox(height: 4), // Small space between icon and text
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: textColor,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis, // Prevent text from overflowing
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Function to handle tab selection
  void _onItemTapped(int index) {
    // The FAB is now explicitly associated with index 2 ("Bewerten")
    // Tapping its space will also select index 2.
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Access ThemeNotifier
    final themeNotifier = Provider.of<ThemeNotifier>(context, listen: false);

    return Scaffold(
      // No AppBar here, as per user's request for HomePage
      body: _pages[_selectedIndex], // Display the selected page content
      
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Action for the central 'Bewerten' button
          setState(() {
            _selectedIndex = 2; // Select the 'Bewerten' tab when FAB is pressed
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Navigiere zur Bewertungsseite!')),
          );
          // TODO: Here could be the direct navigation to the evaluation page,
          // or a modal could be opened, depending on how you want to start the evaluation.
        },
        backgroundColor: Colors.orange[700], // Orange color like in your web design
        foregroundColor: Colors.white,
        shape: const CircleBorder(), // Make it circular
        elevation: 8.0, // Add some shadow
        child: const Icon(Icons.add), // Plus icon
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(), // Notch for the FAB
        notchMargin: 8.0,
        // Match AppBar color - use theme's primary color or dark-specific color
        color: Theme.of(context).brightness == Brightness.dark ? Colors.blueGrey[900] : Theme.of(context).primaryColor, 
        elevation: 8.0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            _buildNavItem(context, Icons.home, 'Start', 0), // Start
            _buildNavItem(context, Icons.meeting_room, 'Räume', 1), // Räume (New index 1)
            
            // Central placeholder for the FAB and its label
            Expanded( // Use Expanded to give it proper spacing
              child: InkWell( // Make this area tappable
                onTap: () => _onItemTapped(2), // Tapping this area also selects 'Bewerten'
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // Make column as small as possible
                    children: [
                      const SizedBox(height: 24), // Space for the FAB to float above
                      Text(
                        'Bewerten',
                        style: GoogleFonts.inter(
                          color: _selectedIndex == 2 ? Colors.white : Colors.blue[100],
                          fontSize: 12,
                          fontWeight: _selectedIndex == 2 ? FontWeight.bold : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            _buildNavItem(context, Icons.warning, 'Warnungen', 3), // Warnungen (New index 3)
            _buildNavItem(context, Icons.more_horiz, 'Mehr', 4), // Mehr (New index 4)
          ],
        ),
      ),
    );
  }
}

// Dummy-AdminSetupPage (unverändert)
class AdminSetupPage extends StatelessWidget {
  final String serverAddress;
  const AdminSetupPage({super.key, required this.serverAddress});

  @override
  Widget build(BuildContext context) {
    // Access ThemeNotifier
    final themeNotifier = Provider.of<ThemeNotifier>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Setup'),
        // AppBar colors are now managed by ThemeData
        actions: [
          IconButton(
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            onPressed: () {
              themeNotifier.toggleTheme();
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Admin-Setup erforderlich. Bitte ändere dein Standardpasswort!',
                style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Text(
                'Verbunden mit: $serverAddress',
                style: GoogleFonts.inter(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              // TODO: Here the form fields for new password and display name
              Text(
                'Formular zum Ändern des Admin-Passworts und Anzeigenamens kommt hierher.',
                style: GoogleFonts.inter(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

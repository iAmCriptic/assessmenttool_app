import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../theme_manager.dart';
import '../auth/login_page.dart';
import '../pages/start_page.dart';
import '../pages/rooms_page.dart';
import '../pages/warnings_page.dart';
import '../pages/more_page.dart';
import '../pages/evaluation_page.dart';

/// HomePage is the main screen after successful login,
/// featuring a Bottom Navigation Bar and a Floating Action Button.
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

  // Callback to change the selected tab from children
  void _changeTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();
    _pages = <Widget>[
      StartPage(
        serverAddress: widget.serverAddress,
        onTabChangeRequested: _changeTab, // Pass the callback here
      ), // 'Start' page
      RoomsPage(serverAddress: widget.serverAddress), // 'Räume' page - Corrected constructor
      EvaluationPage(serverAddress: widget.serverAddress), // NEW: 'Bewerten' page (index 2)
      WarningsPage(), // 'Warnungen' page - Assuming it doesn't need serverAddress yet
      MorePage(serverAddress: widget.serverAddress), // 'Mehr' page
    ];
  }

  /// Helper function to build a navigation item (icon only)
  /// Used for "Start", "Räume", "Warnungen", "Mehr"
  Widget _buildNavItem(BuildContext context, IconData icon, int index) {
    final bool isSelected = _selectedIndex == index;
    // Determine colors based on selected state and current theme brightness
    final Color iconColor = isSelected ? Colors.white : (Theme.of(context).brightness == Brightness.dark ? Colors.blue[100]! : Colors.blue[800]!);

    return Expanded(
      child: Material( // Use Material for ink splash effect
        color: Colors.transparent, // Make it transparent so the BottomAppBar color shines through
        child: InkWell( // For tap feedback
          onTap: () => _changeTab(index), // Use _changeTab directly for bottom nav
          child: SizedBox( // Explicitly define size for the item to prevent overflow
            height: kBottomNavigationBarHeight, // Use standard height
            child: Center( // Center the icon within the SizedBox
              child: Icon(icon, color: iconColor, size: 28), // Explicit icon size
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep: Access ThemeNotifier
    final themeNotifier = Provider.of<ThemeNotifier>(context, listen: false);

    final double appBarContentHeight = 60.0; 

    return Scaffold(
      // No AppBar here, as per user's request for HomePage
      body: _pages[_selectedIndex], // Display the selected page content
      
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Action for the central 'Bewerten' button
          _changeTab(2); // Select the 'Bewerten' tab when FAB is pressed (index 2)
          // Removed SnackBar message as requested
        },
        backgroundColor: Colors.orange[700], // Orange color like in your web design
        foregroundColor: Colors.white,
        shape: const CircleBorder(), // Make it circular
        elevation: 8.0, // Add some shadow
        child: const Icon(Icons.add, size: 28), // Plus icon, slightly larger
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(), // Notch for the FAB
        notchMargin: 8.0,
        // Match AppBar color - use theme's primary color or dark-specific color
        color: Theme.of(context).brightness == Brightness.dark ? Colors.blueGrey[900] : Theme.of(context).primaryColor, 
        elevation: 8.0,
        child: SizedBox( // Explicitly define the height for the content row
          height: appBarContentHeight, // Apply the slightly larger height
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _buildNavItem(context, Icons.home, 0), // Start
              _buildNavItem(context, Icons.meeting_room, 1), // Räume (New index 1)
              
              // Central placeholder for the FAB without any label
              const Expanded( // Use Expanded to give it proper spacing
                child: SizedBox(height: 1.0), // Minimal height for the expanded slot
              ),

              _buildNavItem(context, Icons.warning, 3), // Warnungen (New index 3)
              _buildNavItem(context, Icons.more_horiz, 4), // Mehr (New index 4)
            ],
          ),
        ),
      ),
    );
  }
}

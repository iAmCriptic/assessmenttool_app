import 'package:flutter/material.dart';

import '../pages/start_page.dart'; // Import StartPage
import '../pages/rooms_page.dart'; // Import RoomsPage - this path is correct now
import '../pages/warnings_page.dart'; // Import WarningsPage
import '../pages/more_page.dart'; // Import MorePage
import '../pages/evaluation_page.dart'; // NEW: Import EvaluationPage

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
      WarningsPage(serverAddress: widget.serverAddress), // 'Warnungen' page - Pass serverAddress
      MorePage(serverAddress: widget.serverAddress), // 'Mehr' page
    ];
  }

  /// Helper function to build a navigation item (icon only)
  /// Used for "Start", "Räume", "Warnungen", "Mehr"
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
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark; // Zugriff auf den aktuellen Theme-Modus
    final double appBarContentHeight = 60.0; 

    return Scaffold(
      // Set resizeToAvoidBottomInset to false to prevent FAB from moving up with keyboard
      resizeToAvoidBottomInset: false, // Prevents keyboard from pushing content up
      // Erweitert den Body hinter die BottomAppBar, damit der Hintergrund ganz nach unten reicht
      extendBody: true, 
      
      // Setzt den Hintergrund des Scaffold auf null, um den Theme-Standard zu verwenden
      backgroundColor: null, 
      
      // No AppBar here, as per user's request for HomePage
      body: _pages[_selectedIndex], // Display the selected page content
      
      bottomNavigationBar: BottomAppBar(
        // Die Notch (Loch) wird entfernt, da der FAB direkt in die Leiste integriert wird
        // shape: const CircularNotchedRectangle(), 
        // notchMargin: 8.0,
        
        // Farbe der BottomAppBar basierend auf dem Theme anpassen
        color: isDarkMode ? Colors.black : Colors.white, 
        elevation: 8.0, // Schatten für die BottomAppBar beibehalten
        child: SizedBox( // Explicitly define the height for the content row
          height: appBarContentHeight, // Apply the slightly larger height
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _buildNavItem(context, Icons.home, 0), // Start
              _buildNavItem(context, Icons.meeting_room, 1), // Räume (New index 1)
              
              // Integrierter Plus-Button anstelle des FAB-Platzhalters
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      _changeTab(2); // Select the 'Bewerten' tab when FAB is pressed (index 2)
                      // Entfernt: ScaffoldMessenger.of(context).showSnackBar(...);
                    },
                    child: SizedBox(
                      height: kBottomNavigationBarHeight,
                      child: Center(
                        child: Container( // Der Plus-Button als Teil der Leiste
                          padding: const EdgeInsets.all(8), // Padding um das Icon für den runden Effekt
                          decoration: BoxDecoration(
                            // Hintergrundfarbe des Plus-Buttons basierend auf dem Theme
                            color: isDarkMode ? Colors.white : Colors.black, 
                            shape: BoxShape.circle, // Rund
                            boxShadow: [ // Schatten wie beim ursprünglichen FAB
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                spreadRadius: 2,
                                blurRadius: 5,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          // Icon und Farbe des Plus-Buttons basierend auf dem Theme
                          child: Icon(Icons.edit_note, size: 28, color: isDarkMode ? Colors.black : Colors.white), 
                        ),
                      ),
                    ),
                  ),
                ),
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

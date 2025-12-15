import 'package:flutter/material.dart';
import 'dashboard.dart';
import 'geomapping.dart';

class ImageDetectionPage extends StatefulWidget {
  const ImageDetectionPage({super.key});

  @override
  State<ImageDetectionPage> createState() => _ImageDetectionPageState();
}

class _ImageDetectionPageState extends State<ImageDetectionPage> {
  final int _selectedIndex = 0; // LENS selected

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;

    if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardPage()),
      );
    } else if (index == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const GeoMappingPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const Center(
        child: Text(
          "Image Detection Page",
          style: TextStyle(fontSize: 24),
        ),
      ),
      bottomNavigationBar: _buildFooter(),
    );
  }

  Widget _buildFooter() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: _onItemTapped,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Colors.white,
      unselectedItemColor: Colors.black,
      items: [
        _item(Icons.camera_alt_outlined, "Lens", 0),
        _item(Icons.home_outlined, "Home", 1),
        _item(Icons.map_outlined, "Map", 2),
      ],
    );
  }

  BottomNavigationBarItem _item(IconData icon, String label, int index) {
    final isSelected = _selectedIndex == index;

    return BottomNavigationBarItem(
      label: "",
      icon: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1FA9A7) : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.black),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

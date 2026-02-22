import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../auth/login_page.dart';

import 'admin_overview_tab.dart';
import 'permits/admin_junkshop_permits_tab.dart';
import 'collectors/admin_collector_requests.dart';
import 'users/admin_users_management_tab.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  int _index = 0;

  final _pages = const [
    AdminOverviewTab(),
    AdminJunkshopPermitsTab(),
    AdminCollectorRequestsTab(),
    AdminUsersManagementTab(),
  ];

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  void _showNotifications() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("No notifications yet.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text("Admin Panel"),
        actions: [
          IconButton(
            tooltip: "Notifications",
            onPressed: _showNotifications,
            icon: const Icon(Icons.notifications_none),
          ),

          // Profile icon -> opens slide panel
          Builder(
            builder: (ctx) => IconButton(
              tooltip: "Profile",
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
              icon: const CircleAvatar(
                radius: 14,
                backgroundColor: Color(0xFF1FA9A7),
                child: Icon(Icons.person, size: 16, color: Color(0xFF0F172A)),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),

      endDrawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: const Color(0xFF0F172A),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Admin Profile",
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(user?.email ?? "Unknown",
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 6),
                    Text("UID: ${user?.uid ?? "-"}",
                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text("Logout"),
                onTap: () async {
                  Navigator.pop(context); // close drawer
                  await _logout();
                },
              ),
            ],
          ),
        ),
      ),

      body: IndexedStack(index: _index, children: _pages),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Overview"),
          BottomNavigationBarItem(icon: Icon(Icons.store), label: "Permits"),
          BottomNavigationBarItem(icon: Icon(Icons.local_shipping), label: "Collectors"),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: "Users"),
        ],
      ),
    );
  }
}
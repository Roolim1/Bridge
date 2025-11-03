import 'package:flutter/material.dart';
import 'package:bridge/server_provider.dart';

/// --- FEATURE 2: NEW WIDGET ---
/// Yeh Drawer UI hai settings ke liye
class SettingsDrawer extends StatelessWidget {
  final ServerProvider server;
  const SettingsDrawer({super.key, required this.server});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Colors.grey[800]),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Settings',
                  style: TextStyle(fontSize: 24, color: Colors.white),
                ),
                SizedBox(height: 8),
                Text(
                  'Receiver Settings',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          ListTile(
            title: const Text(
              'Save Location',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              server.savePath,
              style: TextStyle(color: Colors.grey[400]),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Change Save Location'),
            onTap: () {
              // Server provider se path change function call karein
              server.setCustomSavePath();
              Navigator.pop(context); // Drawer band karein
            },
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Reset to Default'),
            onTap: () {
              // Server provider se path reset function call karein
              server.clearCustomSavePath();
              Navigator.pop(context); // Drawer band karein
            },
          ),
        ],
      ),
    );
  }
}
/// --- END OF FEATURE 2 ---

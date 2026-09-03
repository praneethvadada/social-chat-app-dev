import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettingsScreen extends StatefulWidget {
  /// True when shown as the detail pane of the desktop Settings
  /// index+detail split (`SettingsScreen`) instead of pushed as its own
  /// route — hides the back arrow, which would have nothing to pop.
  final bool embedded;
  const NotificationSettingsScreen({super.key, this.embedded = false});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool notificationsEnabled = true;
  bool soundEnabled = true;
  bool vibrationEnabled = true;
  bool personalizedEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
      soundEnabled = prefs.getBool('soundEnabled') ?? true;
      vibrationEnabled = prefs.getBool('vibrationEnabled') ?? true;
      personalizedEnabled = prefs.getBool('personalizedEnabled') ?? false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notificationsEnabled', notificationsEnabled);
    await prefs.setBool('soundEnabled', soundEnabled);
    await prefs.setBool('vibrationEnabled', vibrationEnabled);
    await prefs.setBool('personalizedEnabled', personalizedEnabled);
  }

  void _onChanged(VoidCallback fn) {
    setState(fn);
    _saveSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: const Text('Notification Settings'),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Enable Notifications'),
            value: notificationsEnabled,
            onChanged: (v) => _onChanged(() => notificationsEnabled = v),
          ),
          SwitchListTile(
            title: const Text('Sound'),
            value: soundEnabled,
            onChanged: notificationsEnabled ? (v) => _onChanged(() => soundEnabled = v) : null,
          ),
          SwitchListTile(
            title: const Text('Vibration'),
            value: vibrationEnabled,
            onChanged: notificationsEnabled ? (v) => _onChanged(() => vibrationEnabled = v) : null,
          ),
          SwitchListTile(
            title: const Text('Personalized Notifications'),
            subtitle: const Text('Only get notifications from people you follow'),
            value: personalizedEnabled,
            onChanged: notificationsEnabled ? (v) => _onChanged(() => personalizedEnabled = v) : null,
          ),
        ],
      ),
    );
  }
}

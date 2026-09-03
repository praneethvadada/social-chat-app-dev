import 'package:flutter/material.dart';
import 'package:social_chat_app/src/theme/colors.dart';
import '../../models/device_session.dart';
import '../../services/api_service.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late Future<List<DeviceSession>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.fetchDevices();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = ApiService.fetchDevices();
    });
    await _future;
  }

  Future<void> _confirmRevoke(DeviceSession device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out this device?'),
        content: Text('${device.displayName} will be signed out immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Log Out', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiService.revokeDevice(device.deviceId);
      messenger.showSnackBar(SnackBar(content: Text('${device.displayName} logged out')));
      await _refresh();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to log out device: $e')));
    }
  }

  IconData _platformIcon(String? platform) {
    switch (platform) {
      case 'ANDROID':
        return Icons.phone_android;
      case 'IOS':
        return Icons.phone_iphone;
      case 'WEB':
        return Icons.language;
      default:
        return Icons.devices_other;
    }
  }

  String _relativeTime(DateTime? time) {
    if (time == null) return '';
    final diff = DateTime.now().toUtc().difference(time.toUtc());
    if (diff.inSeconds < 60) return 'Now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Currently Logged-In Devices')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<DeviceSession>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(child: Text('Failed to load devices: ${snapshot.error}')),
                ],
              );
            }
            final devices = snapshot.data ?? [];
            if (devices.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('No devices found')),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: devices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final device = devices[index];
                return _DeviceTile(
                  device: device,
                  icon: _platformIcon(device.platform),
                  lastActiveLabel: _relativeTime(device.lastActiveAt),
                  onRevoke: device.isCurrentDevice ? null : () => _confirmRevoke(device),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final DeviceSession device;
  final IconData icon;
  final String lastActiveLabel;
  final VoidCallback? onRevoke;

  const _DeviceTile({
    required this.device,
    required this.icon,
    required this.lastActiveLabel,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: device.isCurrentDevice ? AppColors.primary : AppColors.mutedSolid,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        device.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (device.isCurrentDevice) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('This device', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
                if (device.displaySubtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(device.displaySubtitle, style: TextStyle(color: AppColors.mutedSolid, fontSize: 13)),
                ],
                const SizedBox(height: 4),
                Text(
                  device.isActive ? 'Active · Last active $lastActiveLabel' : 'Not active',
                  style: TextStyle(
                    color: device.isActive ? AppColors.success : AppColors.mutedSolid,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (onRevoke != null)
            TextButton(
              onPressed: onRevoke,
              child: Text('Log Out', style: TextStyle(color: AppColors.danger)),
            ),
        ],
      ),
    );
  }
}

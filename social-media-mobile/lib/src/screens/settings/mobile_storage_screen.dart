import 'package:flutter/material.dart';
import 'package:social_chat_app/src/theme/colors.dart';
import '../../models/mobile_storage_status.dart';
import '../../services/api_service.dart';

/// Spec §40: Settings → Security → "Mobile Chat Storage" — shows whether
/// this device is the single active local-storage owner, and lets the user
/// pull ownership onto it when it isn't.
class MobileStorageScreen extends StatefulWidget {
  const MobileStorageScreen({super.key});

  @override
  State<MobileStorageScreen> createState() => _MobileStorageScreenState();
}

class _MobileStorageScreenState extends State<MobileStorageScreen> {
  late Future<MobileStorageStatus> _future;
  bool _transferring = false;

  @override
  void initState() {
    super.initState();
    _future = ApiService.getMobileStorageStatus();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = ApiService.getMobileStorageStatus();
    });
    await _future;
  }

  Future<void> _transfer() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _transferring = true);
    try {
      await ApiService.transferMobileStorage();
      messenger.showSnackBar(const SnackBar(content: Text('Chat storage transferred to this device')));
      await _refresh();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to transfer chat storage: $e')));
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mobile Chat Storage')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<MobileStorageStatus>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(child: Text('Failed to load status: ${snapshot.error}')),
                ],
              );
            }
            final status = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: status.isOwner ? AppColors.success : AppColors.mutedSolid,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          status.isOwner ? Icons.storage : Icons.storage_outlined,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              status.isOwner ? 'Active on this device' : 'Inactive on this device',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              status.isOwner
                                  ? 'Chats are being saved locally on this phone.'
                                  : status.ownerDevice != null
                                      ? 'Chats are being saved on ${status.ownerDevice!.displayName} instead.'
                                      : 'No device currently stores chats locally.'
                              ,
                              style: TextStyle(color: AppColors.mutedSolid, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!status.isOwner) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _transferring ? null : _transfer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _transferring
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Transfer to this device'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Only one phone can store your chats locally at a time. Transferring '
                    "will stop saving new chats on ${status.ownerDevice?.displayName ?? 'the other device'} "
                    'and start saving them here instead.',
                    style: TextStyle(color: AppColors.mutedSolid, fontSize: 12),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

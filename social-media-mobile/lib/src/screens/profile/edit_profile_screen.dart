import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'profile_image_cropper.dart';
import '../../components/custom_text_field.dart';
import '../../theme/colors.dart';
import '../../services/api_service.dart';

class EditProfileScreen extends StatefulWidget {
  final String currentFullName;
  final String currentUsername;
  final String? currentBio;
  final String? currentProfilePicUrl;
  
  const EditProfileScreen({
    super.key,
    required this.currentFullName,
    required this.currentUsername,
    this.currentBio,
    this.currentProfilePicUrl,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _fullNameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _bioCtrl;
  bool _isLoading = false;
  File? _selectedImage;
  String? _profilePicUrl;
  bool _isUploadingImage = false;

  @override
  void initState() {
    super.initState();
    _fullNameCtrl = TextEditingController(text: widget.currentFullName);
    _usernameCtrl = TextEditingController(text: widget.currentUsername);
    _bioCtrl = TextEditingController(text: widget.currentBio ?? '');
    _profilePicUrl = widget.currentProfilePicUrl;
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage() async {
    final snack = ScaffoldMessenger.of(context);
    try {
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Choose Image Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );

      if (pickedFile == null) return;

      // Read bytes and open in-app cropper (pure Dart, no platform crashes)
      final originalBytes = await pickedFile.readAsBytes();
      final croppedBytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (_) => ProfileImageCropper(imageBytes: originalBytes),
        ),
      );

      if (croppedBytes == null) return; // user canceled

      // Save cropped bytes to temp file for upload
      final tempDir = await getTemporaryDirectory();
      final croppedPath = '${tempDir.path}/profile_cropped_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final croppedFile = File(croppedPath);
      await croppedFile.writeAsBytes(croppedBytes, flush: true);

      setState(() {
        _selectedImage = croppedFile;
        _isUploadingImage = true;
      });

      final uploadedUrl = await ApiService.uploadImage(croppedFile.path);
      
      if (mounted) {
        setState(() {
          _profilePicUrl = uploadedUrl;
          _isUploadingImage = false;
        });
        snack.showSnackBar(const SnackBar(content: Text('Profile picture uploaded')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingImage = false);
        snack.showSnackBar(SnackBar(content: Text('Failed to upload image: ${e.toString()}')));
      }
    }
  }

  Future<void> _saveProfile() async {
    final snack = ScaffoldMessenger.of(context);
    if (_fullNameCtrl.text.trim().isEmpty) {
      snack.showSnackBar(const SnackBar(content: Text('Full name is required')));
      return;
    }
    
    if (_usernameCtrl.text.trim().isEmpty) {
      snack.showSnackBar(const SnackBar(content: Text('Username is required')));
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      final updatedProfile = await ApiService.updateMyProfile(
        username: _usernameCtrl.text.trim(),
        fullName: _fullNameCtrl.text.trim(),
        bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
        profilePictureUrl: _profilePicUrl,
      );
      
      // Update cached profile info
      await ApiService.updateStoredProfile(
        username: updatedProfile['username'],
        fullName: updatedProfile['fullName'],
      );
      
      if (mounted) {
        setState(() => _isLoading = false);
        snack.showSnackBar(const SnackBar(content: Text('Profile updated successfully')));
        // Return map to trigger profile screen refresh
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop({'updated': 'true'});
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        final errorMsg = e.toString().replaceFirst('Exception: ', '');
        snack.showSnackBar(SnackBar(content: Text('Failed to update: $errorMsg')));
      }
    }  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.close, color: theme.iconTheme.color),
                    onPressed: () {
                      if (_isLoading) return; // Prevent pop while saving
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) Navigator.of(context).pop();
                      });
                    },
                  ),
                  Expanded(
                    child: Center(
                      child: Text('Edit Profile', style: TextStyle(color: primary, fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  TextButton(
                    onPressed: _isLoading ? null : _saveProfile,
                    child: Text('Save', style: TextStyle(color: primary, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile Photo
                    Center(
                      child: GestureDetector(
                        onTap: _isUploadingImage ? null : _pickAndUploadImage,
                        child: Stack(
                          children: [
                            _isUploadingImage
                                ? CircleAvatar(
                                    radius: 54,
                                    backgroundColor: AppColors.border,
                                    child: const CircularProgressIndicator(),
                                  )
                                : _selectedImage != null
                                    ? CircleAvatar(
                                        radius: 54,
                                        backgroundImage: FileImage(_selectedImage!),
                                      )
                                    : _profilePicUrl != null && _profilePicUrl!.isNotEmpty
                                        ? CircleAvatar(
                                            radius: 54,
                                            backgroundImage: NetworkImage(_profilePicUrl!),
                                          )
                                        : CircleAvatar(
                                            radius: 54,
                                            backgroundColor: primary,
                                            child: Text(
                                              _getInitials(_fullNameCtrl.text),
                                              style: theme.textTheme.headlineSmall?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: theme.cardColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                                ),
                                child: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: primary,
                                  child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Full Name
                    Text('Full Name', style: TextStyle(color: AppColors.mutedSolid, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    CustomTextField(
                      controller: _fullNameCtrl,
                      hintText: 'Enter your full name',
                    ),
                    const SizedBox(height: 20),
                    
                    // Username
                    Text('Username', style: TextStyle(color: AppColors.mutedSolid, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    CustomTextField(
                      controller: _usernameCtrl,
                      hintText: 'Enter your username',
                    ),
                    const SizedBox(height: 20),
                    
                    // Bio
                    Text('Bio', style: TextStyle(color: AppColors.mutedSolid, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _bioCtrl,
                      maxLines: 3,
                      maxLength: 150,
                      decoration: InputDecoration(
                        hintText: 'Write something about yourself...',
                        hintStyle: TextStyle(color: AppColors.mutedSolid),
                        filled: true,
                        fillColor: theme.cardColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/user_info_provider.dart';
import '../../onboarding/data/onboarding_repository.dart';
import '../data/profile_repository.dart';

/// First-time profile setup screen shown after login when the user
/// has no profile picture yet.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _displayNameController = TextEditingController();
  final _imagePicker = ImagePicker();

  File? _selectedImage;
  String? _currentAvatarUrl;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final userInfo = await ref.read(userInfoProvider.future);
      if (userInfo != null) {
        _displayNameController.text = userInfo.displayName;
        _currentAvatarUrl = userInfo.picture;
      }
    } catch (e) {
      AppLogger.warning('Failed to load profile for setup', error: e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (pickedFile == null) return;

      final original = File(pickedFile.path);
      final cropped = await _cropImage(original);

      if (cropped == null) return;

      if (!mounted) return;

      setState(() {
        _selectedImage = cropped;
      });
    } catch (e) {
      AppLogger.warning('Failed to pick image', error: e);
    }
  }

  Future<File?> _cropImage(File imageFile) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: imageFile.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop photo',
          toolbarColor: AppTheme.primaryGreen,
          toolbarWidgetColor: Colors.white,
          hideBottomControls: true,
          lockAspectRatio: true,
          initAspectRatio: CropAspectRatioPreset.square,
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
          ],
        ),
        IOSUiSettings(
          title: 'Crop photo',
          aspectRatioLockEnabled: true,
          aspectRatioPickerButtonHidden: true,
          resetAspectRatioEnabled: false,
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
          ],
        ),
        WebUiSettings(context: context),
      ],
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
    );

    if (cropped == null) return null;

    return File(cropped.path);
  }

  void _showImageSourceDialog() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAndContinue() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final profileRepo = ref.read(profileRepositoryProvider);

      // Upload photo if selected
      if (_selectedImage != null) {
        final result = await profileRepo.updateProfilePhoto(_selectedImage!);
        if (!result.success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to upload photo. Please try again.'),
              ),
            );
          }
          return;
        }
      }

      // Mark setup as complete
      final onboarding = ref.read(onboardingRepositoryProvider);
      await onboarding.markProfileSetupComplete();

      if (mounted) context.go('/');
    } catch (e, stackTrace) {
      AppLogger.error(
        'Profile setup save failed',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _skip() async {
    final onboarding = ref.read(onboardingRepositoryProvider);
    await onboarding.markProfileSetupComplete();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const Spacer(flex: 2),

                    // Title
                    Text(
                      'Set up your profile',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add a profile photo so your contacts can recognize you',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),

                    const Spacer(),

                    // Avatar
                    GestureDetector(
                      onTap: _showImageSourceDialog,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 72,
                            backgroundColor: AppTheme.primaryGreen.withValues(
                              alpha: 0.15,
                            ),
                            backgroundImage: _selectedImage != null
                                ? FileImage(_selectedImage!)
                                : (_currentAvatarUrl != null
                                      ? NetworkImage(_currentAvatarUrl!)
                                      : null),
                            child:
                                (_selectedImage == null &&
                                    _currentAvatarUrl == null)
                                ? Icon(
                                    Icons.person,
                                    size: 64,
                                    color: AppTheme.primaryGreen.withValues(
                                      alpha: 0.5,
                                    ),
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryGreen,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _displayNameController.text,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const Spacer(flex: 2),

                    // Continue button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isSaving ? null : _saveAndContinue,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryGreen,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Continue',
                                style: TextStyle(fontSize: 16),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Skip button
                    // TextButton(
                    //   onPressed: _isSaving ? null : _skip,
                    //   child: Text(
                    //     'Skip for now',
                    //     style: TextStyle(
                    //       color: theme.colorScheme.onSurfaceVariant,
                    //     ),
                    //   ),
                    // ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }
}

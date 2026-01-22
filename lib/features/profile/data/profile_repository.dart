import 'dart:io';

import 'package:antinvestor_api_common/antinvestor_api_common.dart' as common;
import 'package:antinvestor_api_profile/antinvestor_api_profile.dart' as pb;
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/networking/client.dart';
import '../../auth/data/user_info_provider.dart';
import '../../messages/data/file_upload_service.dart';

/// Contact type enum for phone/email management
enum ContactType { email, phone }

/// Result of a profile update operation
class ProfileUpdateResult {
  const ProfileUpdateResult._({required this.success, this.errorMessage});

  factory ProfileUpdateResult.success() =>
      const ProfileUpdateResult._(success: true);

  factory ProfileUpdateResult.failure(String message) =>
      ProfileUpdateResult._(success: false, errorMessage: message);

  final bool success;
  final String? errorMessage;
}

/// Contact info for display in UI
class ContactInfo {
  const ContactInfo({
    required this.id,
    required this.type,
    required this.value,
    this.isVerified = false,
    this.isPrimary = false,
  });

  final String id;
  final ContactType type;
  final String value;
  final bool isVerified;
  final bool isPrimary;
}

/// Repository for managing user profile data
class ProfileRepository {
  ProfileRepository(this._ref);

  final Ref _ref;

  /// Get the current user's profile from local database
  Future<Profile?> getCurrentProfile() async {
    final db = AppDatabase.instance;
    final userInfo = await _ref.read(userInfoProvider.future);
    if (userInfo?.id == null) return null;

    final query = db.select(db.profiles)
      ..where((t) => t.id.equals(userInfo!.id!));

    return query.getSingleOrNull();
  }

  /// Update the user's display name
  Future<ProfileUpdateResult> updateDisplayName(String name) async {
    try {
      final profileClient = await _ref.read(profileClientProvider.future);
      final userInfo = await _ref.read(userInfoProvider.future);

      if (userInfo?.id == null) {
        return ProfileUpdateResult.failure('User not authenticated');
      }

      final properties = common.Struct()
        ..fields['name'] = (common.Value()..stringValue = name);

      final request = pb.UpdateRequest(
        id: userInfo!.id,
        properties: properties,
      );

      await profileClient.stub.update(request);

      // Update local database
      await _updateLocalProfile(name: name);

      AppLogger.info('Profile name updated', data: {'name': name});
      return ProfileUpdateResult.success();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to update display name',
        error: e,
        stackTrace: stackTrace,
      );
      return ProfileUpdateResult.failure(e.toString());
    }
  }

  /// Update the user's bio/about text
  Future<ProfileUpdateResult> updateBio(String bio) async {
    try {
      final profileClient = await _ref.read(profileClientProvider.future);
      final userInfo = await _ref.read(userInfoProvider.future);

      if (userInfo?.id == null) {
        return ProfileUpdateResult.failure('User not authenticated');
      }

      final properties = common.Struct()
        ..fields['bio'] = (common.Value()..stringValue = bio);

      final request = pb.UpdateRequest(
        id: userInfo!.id,
        properties: properties,
      );

      await profileClient.stub.update(request);

      // Update local database metadata
      await _updateLocalProfile(bio: bio);

      AppLogger.info('Profile bio updated');
      return ProfileUpdateResult.success();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to update bio', error: e, stackTrace: stackTrace);
      return ProfileUpdateResult.failure(e.toString());
    }
  }

  /// Update the user's profile photo
  /// Returns the URL of the uploaded avatar
  Future<ProfileUpdateResult> updateProfilePhoto(File imageFile) async {
    try {
      final profileClient = await _ref.read(profileClientProvider.future);
      final uploadService = _ref.read(fileUploadServiceProvider);
      final userInfo = await _ref.read(userInfoProvider.future);

      if (userInfo?.id == null) {
        return ProfileUpdateResult.failure('User not authenticated');
      }

      // Upload the image first
      final uploadResult = await uploadService.uploadImage(imageFile);
      if (!uploadResult.isSuccess) {
        return ProfileUpdateResult.failure(
          uploadResult.errorMessage ?? 'Failed to upload image',
        );
      }

      final avatarUrl = uploadResult.fileUrl;

      // Update profile with new avatar URL
      final properties = common.Struct()
        ..fields['avatar_url'] = (common.Value()..stringValue = avatarUrl!);

      final request = pb.UpdateRequest(
        id: userInfo!.id,
        properties: properties,
      );

      await profileClient.stub.update(request);

      // Update local database
      await _updateLocalProfile(avatarUrl: avatarUrl);

      AppLogger.info('Profile photo updated', data: {'url': avatarUrl});
      return ProfileUpdateResult.success();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to update profile photo',
        error: e,
        stackTrace: stackTrace,
      );
      return ProfileUpdateResult.failure(e.toString());
    }
  }

  /// Get all contacts (emails and phones) for the current user
  Future<List<ContactInfo>> getContacts() async {
    final db = AppDatabase.instance;
    final userInfo = await _ref.read(userInfoProvider.future);

    if (userInfo?.id == null) return [];

    // Get roster entries for current user
    final query = db.select(db.roster)
      ..where((t) => t.profileId.equals(userInfo!.id!));

    final entries = await query.get();

    return entries.map((entry) {
      return ContactInfo(
        id: entry.id,
        type: entry.contactType == 0 ? ContactType.email : ContactType.phone,
        value: entry.contactDetail,
        isVerified: entry.isVerified,
      );
    }).toList();
  }

  /// Add a new email contact
  Future<ProfileUpdateResult> addEmail(String email) async {
    try {
      final profileClient = await _ref.read(profileClientProvider.future);

      final rawContact = pb.RawContact(contact: email);

      final request = pb.AddRosterRequest(data: [rawContact]);

      await profileClient.stub.addRoster(request);

      AppLogger.info('Email added to profile', data: {'email': email});
      return ProfileUpdateResult.success();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to add email', error: e, stackTrace: stackTrace);
      return ProfileUpdateResult.failure(e.toString());
    }
  }

  /// Add a new phone contact
  Future<ProfileUpdateResult> addPhone(String phone) async {
    try {
      final profileClient = await _ref.read(profileClientProvider.future);

      final rawContact = pb.RawContact(contact: phone);

      final request = pb.AddRosterRequest(data: [rawContact]);

      await profileClient.stub.addRoster(request);

      AppLogger.info('Phone added to profile', data: {'phone': phone});
      return ProfileUpdateResult.success();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to add phone', error: e, stackTrace: stackTrace);
      return ProfileUpdateResult.failure(e.toString());
    }
  }

  /// Remove a contact by ID
  Future<ProfileUpdateResult> removeContact(String contactId) async {
    try {
      final profileClient = await _ref.read(profileClientProvider.future);

      final request = pb.RemoveRosterRequest(id: contactId);

      await profileClient.stub.removeRoster(request);

      // Remove from local database
      final db = AppDatabase.instance;
      await (db.delete(db.roster)..where((t) => t.id.equals(contactId))).go();

      AppLogger.info('Contact removed', data: {'contactId': contactId});
      return ProfileUpdateResult.success();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to remove contact',
        error: e,
        stackTrace: stackTrace,
      );
      return ProfileUpdateResult.failure(e.toString());
    }
  }

  /// Start verification for a contact (sends verification code)
  Future<ProfileUpdateResult> startContactVerification(String contactId) async {
    try {
      final profileClient = await _ref.read(profileClientProvider.future);

      final request = pb.CreateContactVerificationRequest(contactId: contactId);

      await profileClient.stub.createContactVerification(request);

      AppLogger.info('Verification started', data: {'contactId': contactId});
      return ProfileUpdateResult.success();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to start verification',
        error: e,
        stackTrace: stackTrace,
      );
      return ProfileUpdateResult.failure(e.toString());
    }
  }

  /// Verify a contact with the provided code
  Future<ProfileUpdateResult> verifyContact(
    String contactId,
    String code,
  ) async {
    try {
      final profileClient = await _ref.read(profileClientProvider.future);

      final request = pb.CheckVerificationRequest(id: contactId, code: code);

      final response = await profileClient.stub.checkVerification(request);

      if (response.success) {
        // Update local database to mark as verified
        final db = AppDatabase.instance;
        await (db.update(db.roster)..where((t) => t.id.equals(contactId)))
            .write(const RosterCompanion(isVerified: drift.Value(true)));

        AppLogger.info('Contact verified', data: {'contactId': contactId});
        return ProfileUpdateResult.success();
      } else {
        return ProfileUpdateResult.failure('Verification failed');
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to verify contact',
        error: e,
        stackTrace: stackTrace,
      );
      return ProfileUpdateResult.failure(e.toString());
    }
  }

  /// Update local profile in database
  Future<void> _updateLocalProfile({
    String? name,
    String? avatarUrl,
    String? bio,
  }) async {
    final db = AppDatabase.instance;
    final userInfo = await _ref.read(userInfoProvider.future);

    if (userInfo?.id == null) return;

    final companion = ProfilesCompanion(
      id: drift.Value(userInfo!.id!),
      name: name != null ? drift.Value(name) : const drift.Value.absent(),
      avatarUrl: avatarUrl != null
          ? drift.Value(avatarUrl)
          : const drift.Value.absent(),
      updatedAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
    );

    await db.into(db.profiles).insertOnConflictUpdate(companion);
  }

  /// Sync profile from server to local database
  Future<void> syncProfile() async {
    try {
      final profileClient = await _ref.read(profileClientProvider.future);
      final userInfo = await _ref.read(userInfoProvider.future);

      if (userInfo?.id == null) return;

      final request = pb.GetByIdRequest(id: userInfo!.id);
      final response = await profileClient.stub.getById(request);

      if (response.hasData()) {
        final profile = response.data;
        final db = AppDatabase.instance;

        // Extract name from properties if available
        String? name;
        String? avatarUrl;
        if (profile.hasProperties()) {
          final props = profile.properties;
          if (props.fields.containsKey('name')) {
            name = props.fields['name']?.stringValue;
          }
          if (props.fields.containsKey('avatar_url')) {
            avatarUrl = props.fields['avatar_url']?.stringValue;
          }
        }

        await db
            .into(db.profiles)
            .insertOnConflictUpdate(
              ProfilesCompanion(
                id: drift.Value(profile.id),
                name: drift.Value(name),
                avatarUrl: drift.Value(avatarUrl),
                updatedAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
              ),
            );

        AppLogger.info('Profile synced from server');
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to sync profile',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}

/// Provider for ProfileRepository
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref);
});

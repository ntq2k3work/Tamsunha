import 'account_settings.dart';
import 'consent_versions.dart';

abstract interface class AuthRepository {
  bool get isConfigured;
  String? get initializationError;
  bool get hasSession;
  String? get currentEmail;
  Stream<bool> get signedInChanges;

  Future<void> sendEmailOtp(String email);
  Future<void> verifyEmailOtp({required String email, required String token});
  Future<AccountSettings> getAccountSettings();
  Future<void> completeOnboarding({
    required bool adultConfirmed,
    required bool termsAccepted,
    required bool privacyAccepted,
    required bool communityRulesAccepted,
    required bool onboardingAcknowledged,
    required ConsentVersions versions,
  });
  Future<void> updateSettings({
    bool? reducedMotion,
    bool? notificationsEnabled,
  });
  Future<void> requestAccountDeletion({required String clientRequestId});
  Future<void> signOut();
}

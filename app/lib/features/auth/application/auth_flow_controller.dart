import '../domain/auth_repository.dart';
import '../domain/consent_versions.dart';
import 'auth_gate_controller.dart';
import '../../../core/notifications/push_registration_service.dart';

final class AuthFlowController {
  const AuthFlowController(this._repository, this._gate, this._pushService);

  final AuthRepository _repository;
  final AuthGateController _gate;
  final PushRegistrationService? _pushService;

  Future<void> sendEmailOtp(String email) => _repository.sendEmailOtp(email);

  Future<void> verifyEmailOtp({required String email, required String token}) async {
    await _repository.verifyEmailOtp(email: email, token: token);
    await _gate.refresh();
  }

  Future<void> completeOnboarding({
    required bool adultConfirmed,
    required bool termsAccepted,
    required bool privacyAccepted,
    required bool communityRulesAccepted,
    required bool onboardingAcknowledged,
    ConsentVersions versions = ConsentVersions.current,
  }) async {
    await _repository.completeOnboarding(
      adultConfirmed: adultConfirmed,
      termsAccepted: termsAccepted,
      privacyAccepted: privacyAccepted,
      communityRulesAccepted: communityRulesAccepted,
      onboardingAcknowledged: onboardingAcknowledged,
      versions: versions,
    );
    await _gate.refresh();
  }

  Future<void> updateSettings({
    bool? reducedMotion,
    bool? notificationsEnabled,
  }) async {
    await _repository.updateSettings(
      reducedMotion: reducedMotion,
      notificationsEnabled: notificationsEnabled,
    );
    if (notificationsEnabled != null) {
      try {
        await _pushService?.sync(
          notificationsEnabled,
          requestPermission: notificationsEnabled,
        );
      } catch (_) {
        // Notification delivery is optional and cannot undo the saved preference.
      }
    }
  }

  Future<void> requestAccountDeletion({required String clientRequestId}) async {
    await _disablePushBestEffort();
    await _repository.requestAccountDeletion(clientRequestId: clientRequestId);
    await _gate.refresh();
  }

  Future<void> signOut() async {
    await _disablePushBestEffort();
    await _repository.signOut();
    await _gate.refresh();
  }

  Future<void> _disablePushBestEffort() async {
    try {
      await _pushService?.sync(false);
    } catch (_) {
      // Signing out or requesting deletion must work when push services are offline.
    }
  }
}

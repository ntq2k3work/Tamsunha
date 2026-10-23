import '../../../core/errors/backend_exception.dart';
import '../../../core/network/api_client.dart';
import '../domain/account_settings.dart';
import '../domain/auth_repository.dart';
import '../domain/consent_versions.dart';

final class ApiAuthRepository implements AuthRepository {
  const ApiAuthRepository(this._api, {this.initializationError});

  final ApiClient? _api;

  @override
  final String? initializationError;

  @override
  bool get isConfigured => _api != null;

  @override
  bool get hasSession => _api?.session.hasSession ?? false;

  @override
  String? get currentEmail => _api?.session.email;

  @override
  Stream<bool> get signedInChanges =>
      _api?.session.changes ?? const Stream<bool>.empty();

  ApiClient get _client {
    final api = _api;
    if (api == null) throw BackendException.notConfigured();
    return api;
  }

  @override
  Future<void> sendEmailOtp(String email) async {
    final normalized = email.trim().toLowerCase();
    if (!_looksLikeEmail(normalized)) {
      throw const BackendException(code: 'INVALID_INPUT',
          message: 'Hãy nhập một địa chỉ email hợp lệ.');
    }
    await _client.post('/api/v1/auth/request-code', authenticated: false,
        body: <String, Object?>{'email': normalized});
  }

  @override
  Future<void> verifyEmailOtp({required String email, required String token}) async {
    final normalized = email.trim().toLowerCase();
    final code = token.trim();
    if (!_looksLikeEmail(normalized) || !RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const BackendException(code: 'INVALID_INPUT',
          message: 'Hãy kiểm tra lại email và mã 6 chữ số.');
    }
    final data = await _client.post('/api/v1/auth/verify-code',
        authenticated: false, body: <String, Object?>{
          'email': normalized, 'code': code, 'device_name': 'tuong-nho-flutter',
        });
    final bearer = data['token'];
    final rawUser = data['user'];
    if (bearer is! String || bearer.isEmpty || rawUser is! Map) {
      throw BackendException.unavailable();
    }
    final user = Map<String, Object?>.from(rawUser);
    final id = user['id'];
    final userEmail = user['email'];
    if (id is! String || userEmail is! String) throw BackendException.unavailable();
    await _client.session.save(bearerToken: bearer, userEmail: userEmail, id: id);
  }

  @override
  Future<AccountSettings> getAccountSettings() async =>
      AccountSettings.fromJson(await _client.rpc('get_account_settings'));

  @override
  Future<void> completeOnboarding({
    required bool adultConfirmed,
    required bool termsAccepted,
    required bool privacyAccepted,
    required bool communityRulesAccepted,
    required bool onboardingAcknowledged,
    required ConsentVersions versions,
  }) async {
    await _client.rpc('complete_onboarding', params: <String, Object?>{
      'p_age_confirmed': adultConfirmed,
      'p_terms_accepted': termsAccepted,
      'p_privacy_accepted': privacyAccepted,
      'p_community_rules_accepted': communityRulesAccepted,
      'p_onboarding_acknowledged': onboardingAcknowledged,
      'p_terms_version': versions.terms,
      'p_privacy_version': versions.privacy,
      'p_community_rules_version': versions.communityRules,
      'p_onboarding_version': versions.onboarding,
    });
  }

  @override
  Future<void> updateSettings({bool? reducedMotion,
      bool? notificationsEnabled}) async {
    await _client.rpc('update_settings', params: <String, Object?>{
      'p_reduced_motion': reducedMotion,
      'p_notifications_enabled': notificationsEnabled,
    });
  }

  @override
  Future<void> requestAccountDeletion({required String clientRequestId}) async {
    final data = await _client.rpc('request_account_deletion',
        params: <String, Object?>{
          'p_confirm': true,
          'p_client_request_id': clientRequestId,
        });
    if (data['account_access_disabled'] != true) throw BackendException.unavailable();
    await _client.session.clear();
  }

  @override
  Future<void> signOut() async {
    await _client.post('/api/v1/auth/logout');
    await _client.session.clear();
  }

  bool _looksLikeEmail(String value) => value.length <= 254 &&
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/errors/backend_exception.dart';
import '../domain/account_settings.dart';
import '../domain/auth_repository.dart';

enum AuthGateStatus {
  loading,
  backendNotConfigured,
  backendUnavailable,
  signedOut,
  onboardingRequired,
  ready,
  suspended,
}

final class AuthGateController extends ChangeNotifier {
  AuthGateController(this._repository);

  final AuthRepository _repository;
  StreamSubscription<bool>? _authSubscription;
  AuthGateStatus _status = AuthGateStatus.loading;
  String? _errorMessage;
  AccountSettings? _accountSettings;
  bool _initialized = false;

  AuthGateStatus get status => _status;
  String? get errorMessage => _errorMessage;
  AccountSettings? get accountSettings => _accountSettings;
  bool get isModerator => _accountSettings?.isModerator ?? false;
  bool get isReady => _status == AuthGateStatus.ready;
  bool get isSignedIn => _repository.hasSession;
  String? get currentEmail => _repository.currentEmail;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!_repository.isConfigured) {
      _setStatus(AuthGateStatus.backendNotConfigured);
      return;
    }
    if (_repository.initializationError != null) {
      _setStatus(
        AuthGateStatus.backendUnavailable,
        'Chưa thể khởi tạo dịch vụ. Hãy kiểm tra cấu hình rồi khởi động lại ứng dụng.',
      );
      return;
    }
    _authSubscription = _repository.signedInChanges.listen((signedIn) {
      if (!signedIn) {
        _accountSettings = null;
        _setStatus(AuthGateStatus.signedOut);
      } else {
        unawaited(refresh());
      }
    }, onError: (Object _, StackTrace __) {
      _setStatus(
        AuthGateStatus.backendUnavailable,
        'Không thể kiểm tra phiên đăng nhập. Hãy thử kết nối lại.',
      );
    });
    await refresh();
  }

  Future<void> refresh() async {
    if (!_repository.isConfigured) {
      _setStatus(AuthGateStatus.backendNotConfigured);
      return;
    }
    if (_repository.initializationError != null) {
      _setStatus(
        AuthGateStatus.backendUnavailable,
        'Chưa thể khởi tạo dịch vụ. Hãy kiểm tra cấu hình rồi khởi động lại ứng dụng.',
      );
      return;
    }
    if (!_repository.hasSession) {
      _setStatus(AuthGateStatus.signedOut);
      return;
    }
    _setStatus(AuthGateStatus.loading);
    try {
      final settings = await _repository.getAccountSettings();
      _accountSettings = settings;
      notifyListeners();
      if (settings.accountStatus != 'active') {
        _setStatus(AuthGateStatus.suspended);
      } else if (settings.eligible) {
        _setStatus(AuthGateStatus.ready);
      } else {
        _setStatus(AuthGateStatus.onboardingRequired);
      }
    } on BackendException catch (error) {
      _setStatus(error.code == 'UNAUTHENTICATED'
          ? AuthGateStatus.signedOut
          : AuthGateStatus.backendUnavailable, error.message);
    } catch (_) {
      _setStatus(AuthGateStatus.backendUnavailable);
    }
  }

  void _setStatus(AuthGateStatus value, [String? errorMessage]) {
    if (value == AuthGateStatus.signedOut ||
        value == AuthGateStatus.backendNotConfigured) {
      _accountSettings = null;
    }
    if (_status == value && _errorMessage == errorMessage) return;
    _status = value;
    _errorMessage = errorMessage;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }
}

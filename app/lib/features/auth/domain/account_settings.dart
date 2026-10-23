import '../../../core/domain/model_parsing.dart';

final class AccountSettings {
  const AccountSettings({
    required this.eligible,
    required this.accountStatus,
    required this.adultConfirmed,
    required this.isModerator,
    required this.reducedMotion,
    required this.notificationsEnabled,
    this.termsVersion,
    this.privacyVersion,
    this.communityRulesVersion,
    this.onboardingVersion,
  });

  final bool eligible;
  final String accountStatus;
  final bool adultConfirmed;
  final bool isModerator;
  final bool reducedMotion;
  final bool notificationsEnabled;
  final String? termsVersion;
  final String? privacyVersion;
  final String? communityRulesVersion;
  final String? onboardingVersion;

  factory AccountSettings.fromJson(Map<String, Object?> json) => AccountSettings(
        eligible: ModelParsing.requiredBool(json, 'eligible'),
        accountStatus: ModelParsing.requiredString(json, 'account_status'),
        adultConfirmed: ModelParsing.requiredBool(json, 'adult_confirmed'),
        isModerator: ModelParsing.requiredBool(json, 'is_moderator'),
        reducedMotion: ModelParsing.requiredBool(json, 'reduced_motion'),
        notificationsEnabled:
            ModelParsing.requiredBool(json, 'notifications_enabled'),
        termsVersion: ModelParsing.optionalString(json, 'terms_version'),
        privacyVersion: ModelParsing.optionalString(json, 'privacy_version'),
        communityRulesVersion:
            ModelParsing.optionalString(json, 'community_rules_version'),
        onboardingVersion:
            ModelParsing.optionalString(json, 'onboarding_version'),
      );
}

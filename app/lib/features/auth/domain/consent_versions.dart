final class ConsentVersions {
  const ConsentVersions({
    required this.terms,
    required this.privacy,
    required this.communityRules,
    required this.onboarding,
  });

  static const current = ConsentVersions(
    terms: 'terms-v1',
    privacy: 'privacy-v1',
    communityRules: 'community-v1',
    onboarding: 'onboarding-v1',
  );

  final String terms;
  final String privacy;
  final String communityRules;
  final String onboarding;
}

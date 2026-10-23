enum AppRoute {
  bootstrap('/bootstrap'),
  welcome('/welcome'),
  onboarding('/onboarding'),
  accountStatus('/account-status'),
  offlineDemo('/offline-demo'),
  wall('/wall'),
  inbox('/inbox'),
  myNotes('/my-notes'),
  settings('/settings'),
  conversation('/conversation/:conversationId'),
  moderator('/moderator');

  const AppRoute(this.path);

  final String path;
}

import 'package:firebase_analytics/firebase_analytics.dart';

enum ProductEvent {
  appOpened('app_opened'),
  wallRegionVisited('wall_region_visited'),
  noteOpened('note_opened'),
  noteCreated('note_created'),
  notePlaced('note_placed'),
  encouragementSent('encouragement_sent'),
  conversationStarted('conversation_started'),
  messageSent('message_sent'),
  reportSubmitted('report_submitted');

  const ProductEvent(this.wireName);

  final String wireName;
}

final class ProductAnalytics {
  const ProductAnalytics(this._analytics);

  final FirebaseAnalytics? _analytics;

  Future<void> record(ProductEvent event) async {
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      await analytics.logEvent(name: event.wireName);
    } catch (_) {
      // Analytics must never affect a user action and receives no event properties.
    }
  }
}

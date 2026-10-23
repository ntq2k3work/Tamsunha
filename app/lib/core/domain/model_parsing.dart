/// Strict parsing helpers for API DTOs.
///
/// Unknown JSON fields are intentionally ignored by each model's `toJson`
/// whitelist. This prevents server-only identity fields from leaking back out
/// through public view models.
abstract final class ModelParsing {
  static String requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key must be a non-empty string.');
    }
    return value;
  }

  static String? optionalString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('$key must be a string or null.');
    }
    return value;
  }

  static int requiredInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw FormatException('$key must be an integer.');
    }
    return value;
  }

  static int requiredInt32(Map<String, Object?> json, String key) {
    final value = requiredInt(json, key);
    if (value < -2147483648 || value > 2147483647) {
      throw FormatException('$key must fit a signed 32-bit integer.');
    }
    return value;
  }

  static bool requiredBool(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! bool) {
      throw FormatException('$key must be a boolean.');
    }
    return value;
  }

  static DateTime requiredTimestamp(Map<String, Object?> json, String key) {
    final value = requiredString(json, key);
    final timestamp = DateTime.tryParse(value);
    if (timestamp == null) {
      throw FormatException('$key must be an ISO-8601 timestamp.');
    }
    return timestamp.toUtc();
  }

  static DateTime? optionalTimestamp(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('$key must be an ISO-8601 timestamp or null.');
    }
    final timestamp = DateTime.tryParse(value);
    if (timestamp == null) {
      throw FormatException('$key must be an ISO-8601 timestamp.');
    }
    return timestamp.toUtc();
  }
}

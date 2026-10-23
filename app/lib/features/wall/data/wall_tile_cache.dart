import 'dart:collection';

/// A small least-recently-used cache keyed by tile coordinate.
final class WallTileCache<K, V> {
  WallTileCache({this.capacity = 30}) {
    if (capacity < 1) throw ArgumentError.value(capacity, 'capacity');
  }

  final int capacity;
  final LinkedHashMap<K, V> _values = LinkedHashMap<K, V>();

  int get length => _values.length;
  Iterable<K> get keys => _values.keys;
  Iterable<V> get values => _values.values;

  V? get(K key) {
    final value = _values.remove(key);
    if (value != null) _values[key] = value;
    return value;
  }

  void put(K key, V value) {
    _values.remove(key);
    _values[key] = value;
    while (_values.length > capacity) {
      _values.remove(_values.keys.first);
    }
  }

  void remove(K key) => _values.remove(key);

  void clear() => _values.clear();
}

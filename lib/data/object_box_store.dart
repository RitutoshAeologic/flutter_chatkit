import 'package:objectbox/objectbox.dart';
import '../objectbox.g.dart';

/// Thin wrapper around the ObjectBox Store.
/// Opened once in main(), injected into all domain services.
class ObjectBoxStore {
  final Store _store;

  ObjectBoxStore(this._store);

  /// Returns the Box for entity type [T].
  Box<T> box<T>() => _store.box<T>();

  /// Closes the underlying store. Call only on app shutdown.
  void close() => _store.close();
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'provider_model.dart';

/// Registry of authorised content providers.
///
/// Responsibilities:
///  * Load the allow-list from Firestore (`providers` collection) once approved.
///  * Expose only providers whose `enabled` flag is true.
///  * Order providers by priority for the playback engine.
///  * Support resetting & retrying when auth state changes.
class ProviderRegistry extends ChangeNotifier {
  ProviderRegistry({FirebaseFirestore? firestore})
    : _firestoreInstance = firestore;

  final FirebaseFirestore? _firestoreInstance;
  FirebaseFirestore get _firestore => _firestoreInstance ?? FirebaseFirestore.instance;

  final Map<String, ProviderModel> _providers = {};
  StreamSubscription? _sub;
  bool _loaded = false;
  bool _loading = false;
  String? _error;

  /// All providers currently known (enabled or disabled).
  Map<String, ProviderModel> get all => Map.unmodifiable(_providers);

  /// Only providers that are enabled and eligible for playback.
  List<ProviderModel> get enabled =>
      _providers.values.where((p) => p.enabled).toList()
        ..sort((a, b) => a.priority.compareTo(b.priority));

  /// Whether the allow-list has been fetched from Firestore.
  bool get loaded => _loaded;

  /// Last stream error, if any.
  String? get error => _error;

  /// Load the provider allow-list and subscribe to live changes.
  void load() {
    if (_sub != null || _loading) return;
    _loading = true;
    _error = null;
    _sub = _firestore.collection('providers').snapshots().listen(
      (snap) {
        _loaded = true;
        _loading = false;
        _error = null;
        for (final doc in snap.docs) {
          _providers[doc.id] = ProviderModel.fromFirestore(doc.id, doc.data());
        }
        _providers.removeWhere(
          (key, _) => !snap.docs.any((d) => d.id == key),
        );
        notifyListeners();
      },
      onError: (e) {
        debugPrint('ProviderRegistry stream error: $e');
        _loaded = false;
        _loading = false;
        _error = e.toString();
        _sub?.cancel();
        _sub = null;
        notifyListeners();
      },
    );
  }

  /// Cancel active subscription and clear cached providers (e.g., on sign-out).
  void reset() {
    _sub?.cancel();
    _sub = null;
    _loaded = false;
    _loading = false;
    _error = null;
    _providers.clear();
    notifyListeners();
  }

  /// Look up a provider by id.
  ProviderModel? byId(String id) => _providers[id];

  /// Find a provider that supports the given content type and (optionally)
  /// a specific resource.
  ProviderModel? find({
    required ContentType type,
    String? id,
    String? season,
    String? episode,
  }) {
    for (final provider in enabled) {
      if (!provider.supports(type)) continue;
      if (id != null && provider.id != id) continue;
      return provider;
    }
    return null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

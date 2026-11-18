import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'provider_model.dart';
import 'provider_health.dart';

/// Registry of authorised content providers.
///
/// Responsibilities:
///  * Load the allow-list from Firestore (`providers` collection).
///  * Expose only providers whose `enabled` flag is true.
///  * Order providers by priority for the playback engine.
///  * Forward enable/disable toggles from the admin dashboard.
///
/// Security: a client can never create or promote a provider — the allow-list
/// is server-side and enforced by Firestore rules.
class ProviderRegistry extends ChangeNotifier {
  ProviderRegistry({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  final Map<String, ProviderModel> _providers = {};
  StreamSubscription? _sub;
  bool _loaded = false;

  /// All providers currently known (enabled or disabled).
  Map<String, ProviderModel> get all => Map.unmodifiable(_providers);

  /// Only providers that are enabled and eligible for playback.
  List<ProviderModel> get enabled =>
      _providers.values.where((p) => p.enabled).toList()
        ..sort((a, b) => a.priority.compareTo(b.priority));

  /// Whether the allow-list has been fetched from Firestore.
  bool get loaded => _loaded;

  /// Load the provider allow-list and subscribe to live changes.
  void load() {
    if (_loaded) return;
    _loaded = true;
    _sub = _firestore.collection('providers').snapshots().listen(
      (snap) {
        for (final doc in snap.docs) {
          _providers[doc.id] = ProviderModel.fromFirestore(doc.id, doc.data());
        }
        // Remove providers that were deleted server-side.
        _providers.removeWhere(
          (key, _) => !snap.docs.any((d) => d.id == key),
        );
        notifyListeners();
      },
      onError: (e) => debugPrint('ProviderRegistry stream error: $e'),
    );
  }

  /// Look up a provider by id.
  ProviderModel? byId(String id) => _providers[id];

  /// Find a provider that supports the given content type and (optionally)
  /// a specific resource. Falls back to any enabled provider.
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
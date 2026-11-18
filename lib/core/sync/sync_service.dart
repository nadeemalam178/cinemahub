import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import '../network/connectivity_provider.dart';

/// Coordinates offline-first sync of user data (watch progress, watchlist,
/// history, theme, profile) with Firestore.
///
/// Writes are debounced to avoid hammering Firestore on every video frame, and
/// queued locally when offline so they flush when connectivity returns.
class SyncService extends ChangeNotifier {
  SyncService({
    required AuthService auth,
    required ConnectivityProvider connectivity,
    FirebaseFirestore? firestore,
  }) : _auth = auth,
       _connectivity = connectivity,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final AuthService _auth;
  final ConnectivityProvider _connectivity;
  final FirebaseFirestore _firestore;

  final Map<String, Timer> _debounce = {};
  final List<Future<void> Function()> _pendingWrites = [];

  bool _syncing = false;
  bool get syncing => _syncing;
  DateTime? _lastSync;
  DateTime? get lastSync => _lastSync;

  /// Debounced write of a playback progress record.
  ///
  /// [contentId] is the stable provider-independent content id.
  void scheduleProgress({
    required String contentId,
    required double positionSeconds,
    required double durationSeconds,
    String? profileId,
    String? episodeId,
  }) {
    final uid = _auth.user?.uid;
    if (uid == null) return;

    final key = '$contentId::$profileId::$episodeId';
    _debounce[key]?.cancel();
    _debounce[key] = Timer(const Duration(seconds: 5), () {
      _debounce.remove(key);
      _enqueue(() => _writeProgress(
        uid: uid,
        contentId: contentId,
        profileId: profileId,
        episodeId: episodeId,
        positionSeconds: positionSeconds,
        durationSeconds: durationSeconds,
      ));
    });
  }

  Future<void> _writeProgress({
    required String uid,
    required String contentId,
    required double positionSeconds,
    required double durationSeconds,
    String? profileId,
    String? episodeId,
  }) async {
    final ref = _firestore
        .collection('users')
        .doc(uid)
        .collection('watchHistory')
        .doc(contentId);
    await ref.set({
      'contentId': contentId,
      'profileId': profileId,
      'episodeId': episodeId,
      'positionSeconds': positionSeconds,
      'durationSeconds': durationSeconds,
      'updatedAt': FieldValue.serverTimestamp(),
      'completed': durationSeconds > 0 && positionSeconds / durationSeconds >= 0.92,
    }, SetOptions(merge: true));
  }

  void _enqueue(Future<void> Function() write) {
    if (!_connectivity.online) {
      _pendingWrites.add(write);
      return;
    }
    _pendingWrites.add(write);
    _flush();
  }

  Future<void> _flush() async {
    if (_syncing) return;
    _syncing = true;
    notifyListeners();
    try {
      while (_pendingWrites.isNotEmpty) {
        final write = _pendingWrites.removeAt(0);
        try {
          await write();
        } catch (e) {
          debugPrint('SyncService write failed: $e');
        }
      }
      _lastSync = DateTime.now();
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Called when connectivity returns to flush queued writes.
  void onConnectivityRestored() {
    if (_connectivity.online) _flush();
  }

  @override
  void dispose() {
    for (final t in _debounce.values) {
      t.cancel();
    }
    super.dispose();
  }
}
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import '../network/connectivity_provider.dart';

/// Coordinates offline-first sync of user data (watch progress, watchlist,
/// history) with Firestore.
///
/// Writes are debounced to avoid hammering Firestore on every video frame, and
/// queued locally when offline so they flush automatically when connectivity returns.
class SyncService extends ChangeNotifier {
  SyncService({
    required this._auth,
    required this._connectivity,
    FirebaseFirestore? firestore,
  }) : _firestoreInstance = firestore {
    _wasOnline = _connectivity.online;
    _connectivity.addListener(_onConnectivityChanged);
  }

  final AuthService _auth;
  final ConnectivityProvider _connectivity;
  final FirebaseFirestore? _firestoreInstance;
  FirebaseFirestore get _firestore => _firestoreInstance ?? FirebaseFirestore.instance;

  final Map<String, Timer> _debounce = {};
  final List<Future<void> Function()> _pendingWrites = [];

  bool _wasOnline = true;
  bool _syncing = false;
  bool get syncing => _syncing;
  DateTime? _lastSync;
  DateTime? get lastSync => _lastSync;

  void _onConnectivityChanged() {
    final nowOnline = _connectivity.online;
    if (nowOnline && !_wasOnline) {
      onConnectivityRestored();
    }
    _wasOnline = nowOnline;
  }

  /// Debounced write of a playback progress record.
  void scheduleProgress({
    required String contentId,
    required double positionSeconds,
    required double durationSeconds,
    String? profileId,
    String? episodeId,
    String? title,
    String? type,
    String? posterUrl,
    String? releaseDate,
    double? rating,
  }) {
    final uid = _auth.user?.uid;
    if (uid == null || contentId.isEmpty) return;

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
        title: title,
        type: type,
        posterUrl: posterUrl,
        releaseDate: releaseDate,
        rating: rating,
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
    String? title,
    String? type,
    String? posterUrl,
    String? releaseDate,
    double? rating,
  }) async {
    final ref = _firestore
        .collection('users')
        .doc(uid)
        .collection('watchHistory')
        .doc(contentId);
    final payload = <String, dynamic>{
      'id': contentId,
      'contentId': contentId,
      'profileId': profileId,
      'episodeId': episodeId,
      'positionSeconds': positionSeconds,
      'durationSeconds': durationSeconds,
      'updatedAt': FieldValue.serverTimestamp(),
      'completed': durationSeconds > 0 && positionSeconds / durationSeconds >= 0.92,
    };
    if (title != null && title.isNotEmpty) payload['title'] = title;
    if (type != null && type.isNotEmpty) payload['type'] = type;
    if (posterUrl != null && posterUrl.isNotEmpty) payload['posterUrl'] = posterUrl;
    if (releaseDate != null && releaseDate.isNotEmpty) payload['releaseDate'] = releaseDate;
    if (rating != null) payload['rating'] = rating;

    await ref.set(payload, SetOptions(merge: true));
  }

  void _enqueue(Future<void> Function() write) {
    _pendingWrites.add(write);
    if (_connectivity.online) {
      unawaited(_flush());
    }
  }

  Future<void> _enqueueAndFlush(Future<void> Function() write) async {
    _pendingWrites.add(write);
    if (_connectivity.online) {
      await _flush();
    }
  }

  Future<void> _flush() async {
    if (_syncing || !_connectivity.online) return;
    _syncing = true;
    notifyListeners();
    try {
      while (_pendingWrites.isNotEmpty && _connectivity.online) {
        final write = _pendingWrites.first;
        try {
          await write();
          _pendingWrites.removeAt(0);
          _lastSync = DateTime.now();
        } catch (e) {
          debugPrint('SyncService write failed (kept in queue): $e');
          break;
        }
      }
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Called when connectivity returns to flush queued writes.
  Future<void> onConnectivityRestored() async {
    if (_connectivity.online && _pendingWrites.isNotEmpty) {
      await _flush();
    }
  }

  /// Adds an item to the user's watchlist (sanitized to avoid oversized nested blobs).
  Future<void> addToWatchlist(Map<String, dynamic> item) async {
    final uid = _auth.user?.uid;
    if (uid == null) return;
    final contentId = (item['id'] ?? '').toString();
    if (contentId.isEmpty) return;

    final payload = Map<String, dynamic>.from(item)
      ..remove('tmdbData')
      ..remove('stremioMeta');
    payload['id'] = contentId;
    payload['contentId'] = contentId;
    payload['addedAt'] = FieldValue.serverTimestamp();

    await _enqueueAndFlush(() async {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('watchlist')
          .doc(contentId)
          .set(payload, SetOptions(merge: true));
    });
  }

  /// Removes an item from the user's watchlist.
  Future<void> removeFromWatchlist(String contentId) async {
    final uid = _auth.user?.uid;
    if (uid == null || contentId.isEmpty) return;

    await _enqueueAndFlush(() async {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('watchlist')
          .doc(contentId)
          .delete();
    });
  }

  /// Removes an item from the user's watch history.
  Future<void> removeFromWatchHistory(String contentId) async {
    final uid = _auth.user?.uid;
    if (uid == null || contentId.isEmpty) return;

    await _enqueueAndFlush(() async {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('watchHistory')
          .doc(contentId)
          .delete();
    });
  }

  /// Checks if an item is in the user's watchlist.
  Future<bool> isInWatchlist(String contentId) async {
    final uid = _auth.user?.uid;
    if (uid == null || contentId.isEmpty) return false;
    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('watchlist')
          .doc(contentId)
          .get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  /// Gets the user's watchlist (for Library / My List screen).
  Future<List<Map<String, dynamic>>> getWatchlist() async {
    final uid = _auth.user?.uid;
    if (uid == null) return [];

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('watchlist')
          .orderBy('addedAt', descending: true)
          .get();
      return snapshot.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        data['id'] ??= d.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Failed to load watchlist: $e');
      return [];
    }
  }

  /// Gets the user's watch history.
  Future<List<Map<String, dynamic>>> getWatchHistory() async {
    final uid = _auth.user?.uid;
    if (uid == null) return [];

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('watchHistory')
          .orderBy('updatedAt', descending: true)
          .get();

      return snapshot.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        data['id'] ??= data['contentId'] ?? d.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Failed to load watch history: $e');
      return [];
    }
  }

  @override
  void dispose() {
    _connectivity.removeListener(_onConnectivityChanged);
    for (final t in _debounce.values) {
      t.cancel();
    }
    super.dispose();
  }
}

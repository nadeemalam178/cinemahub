import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';

/// Owner/admin management service.
///
/// Security: All writes are gated by Firestore security rules and synchronized
/// via `admin/userStatus/users/{uid}` -> Cloud Function `onUserStatusUpdate`.
class AdminService extends ChangeNotifier {
  AdminService({
    required AuthService auth,
    FirebaseFirestore? firestore,
    Stream<List<Map<String, dynamic>>>? userStream,
    Stream<List<Map<String, dynamic>>>? providerStream,
  })  : _auth = auth,
        _firestoreInstance = firestore,
        _userStream = userStream,
        _providerStream = providerStream;

  final AuthService _auth;
  final FirebaseFirestore? _firestoreInstance;
  FirebaseFirestore get _firestore => _firestoreInstance ?? FirebaseFirestore.instance;

  bool _isAdmin = false;
  bool get isAdmin => _isAdmin;

  Stream<List<Map<String, dynamic>>>? _userStream;
  Stream<List<Map<String, dynamic>>> get userStream => _userStream ??= _firestore
      .collection('users')
      .snapshots()
      .map((snap) => snap.docs.map((doc) {
            final data = Map<String, dynamic>.from(doc.data());
            data['uid'] ??= doc.id;
            return data;
          }).toList());

  Stream<List<Map<String, dynamic>>>? _providerStream;
  Stream<List<Map<String, dynamic>>> get providerStream =>
      _providerStream ??= _firestore
          .collection('providers')
          .snapshots()
          .map((snap) => snap.docs.map((doc) {
                final data = Map<String, dynamic>.from(doc.data());
                data['id'] ??= doc.id;
                return data;
              }).toList());

  Future<void> checkAdminStatus() async {
    final user = _auth.user;
    if (user == null) {
      reset();
      return;
    }
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final role = doc.data()?['role'] as String?;
      _isAdmin = role == 'admin' || role == 'owner';
      notifyListeners();
    } catch (_) {
      _isAdmin = _auth.isAdmin;
      notifyListeners();
    }
  }

  void reset() {
    _isAdmin = false;
    notifyListeners();
  }

  Future<String> _resolveExistingRole(String userId, {String? overrideRole}) async {
    if (overrideRole != null &&
        (overrideRole == 'user' || overrideRole == 'admin' || overrideRole == 'owner')) {
      return overrideRole;
    }
    final userSnap = await _firestore.collection('users').doc(userId).get();
    final existing = userSnap.data()?['role'] as String?;
    if (existing == 'admin' || existing == 'owner' || existing == 'user') {
      return existing!;
    }
    return 'user';
  }

  Future<void> approveUser(String userId, {String? role}) async {
    if (!_isAdmin && !_auth.isAdmin) {
      throw AdminPermissionException('Not admin');
    }
    final resolvedRole = await _resolveExistingRole(userId, overrideRole: role);

    await _firestore.collection('users').doc(userId).set({
      'status': 'approved',
      'role': resolvedRole,
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedBy': _auth.user?.uid,
    }, SetOptions(merge: true));

    await Future.wait([
      _firestore
          .collection('admin')
          .doc('userStatus')
          .collection('users')
          .doc(userId)
          .set({
        'status': 'approved',
        'role': resolvedRole,
        'updatedBy': _auth.user?.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((e) {
        debugPrint('Admin status collection sync note: $e');
      }),
      _firestore.collection('accessRequests').doc(userId).set({
        'status': 'approved',
        'updatedBy': _auth.user?.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((e) {
        debugPrint('Access request sync note: $e');
      }),
    ]);
  }

  Future<void> suspendUser(String userId) async {
    if (!_isAdmin && !_auth.isAdmin) {
      throw AdminPermissionException('Not admin');
    }
    final resolvedRole = await _resolveExistingRole(userId);
    if (resolvedRole == 'owner' && _auth.role != 'owner') {
      throw AdminPermissionException('Only an owner can suspend an owner');
    }

    await _firestore.collection('users').doc(userId).set({
      'status': 'suspended',
      'suspendedAt': FieldValue.serverTimestamp(),
      'suspendedBy': _auth.user?.uid,
    }, SetOptions(merge: true));

    await Future.wait([
      _firestore
          .collection('admin')
          .doc('userStatus')
          .collection('users')
          .doc(userId)
          .set({
        'status': 'suspended',
        'role': resolvedRole,
        'updatedBy': _auth.user?.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((e) {
        debugPrint('Admin status collection sync note: $e');
      }),
      _firestore.collection('accessRequests').doc(userId).set({
        'status': 'suspended',
        'updatedBy': _auth.user?.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((e) {
        debugPrint('Access request sync note: $e');
      }),
    ]);
  }

  Future<void> setUserRole(String userId, String role) async {
    if (!_isAdmin && !_auth.isAdmin) {
      throw AdminPermissionException('Not admin');
    }
    if (role == 'owner' && _auth.role != 'owner') {
      throw AdminPermissionException('Only an owner can assign owner role');
    }
    if (role != 'user' && role != 'admin' && role != 'owner') {
      throw ArgumentError('Unsupported role: $role');
    }

    final userSnap = await _firestore.collection('users').doc(userId).get();
    final currentStatus = (userSnap.data()?['status'] as String?) ?? 'approved';

    await _firestore.collection('users').doc(userId).set({
      'role': role,
      'updatedBy': _auth.user?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _firestore
        .collection('admin')
        .doc('userStatus')
        .collection('users')
        .doc(userId)
        .set({
      'status': currentStatus,
      'role': role,
      'updatedBy': _auth.user?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> enableProvider(String providerId) async {
    if (!_isAdmin && !_auth.isAdmin) {
      throw AdminPermissionException('Not admin');
    }
    await _firestore.collection('providers').doc(providerId).update({
      'enabled': true,
      'enabledAt': FieldValue.serverTimestamp(),
      'enabledBy': _auth.user?.uid,
    });
  }

  Future<void> disableProvider(String providerId) async {
    if (!_isAdmin && !_auth.isAdmin) {
      throw AdminPermissionException('Not admin');
    }
    await _firestore.collection('providers').doc(providerId).update({
      'enabled': false,
      'disabledAt': FieldValue.serverTimestamp(),
      'disabledBy': _auth.user?.uid,
    });
  }
}

/// Raised when a non-admin tries to perform admin actions.
class AdminPermissionException implements Exception {
  AdminPermissionException(this.message);
  final String message;
  @override
  String toString() => message;
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';

/// Owner-only admin dashboard service.
///
/// Responsibilities:
///  * View all registered users.
///  * Approve or suspend pending users.
///  * Manage provider registry.
///  * View provider health status.
///  * Manage catalogue entries.
///
/// Security: This service is gated by Firestore rules. Client code can't
/// promote itself to admin — that's enforced by rules.
class AdminService extends ChangeNotifier {
  AdminService({
    required AuthService auth,
    FirebaseFirestore? firestore,
  }) : _auth = auth,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final AuthService _auth;
  final FirebaseFirestore _firestore;

  bool _isAdmin = false;
  bool get isAdmin => _isAdmin;

  Stream<List<Map<String, dynamic>>>? _userStream;
  Stream<List<Map<String, dynamic>>> get userStream => _userStream ??= _firestore
      .collection('users')
      .snapshots()
      .map((snap) => snap.docs.map((doc) => doc.data()).toList());

  Stream<List<Map<String, dynamic>>>? _providerStream;
  Stream<List<Map<String, dynamic>>> get providerStream => _providerStream ??= _firestore
      .collection('providers')
      .snapshots()
      .map((snap) => snap.docs.map((doc) => doc.data()).toList());

  Future<void> checkAdminStatus() async {
    final user = _auth.user;
    if (user == null) return;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final role = doc.data()?['role'] as String?;
      _isAdmin = role == 'admin' || role == 'owner';
      notifyListeners();
    } catch (_) {
      _isAdmin = false;
      notifyListeners();
    }
  }

  Future<void> approveUser(String userId) async {
    if (!_isAdmin) throw AdminPermissionException('Not admin');
    await _firestore.collection('users').doc(userId).update({
      'status': 'approved',
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedBy': _auth.user?.uid,
    });
  }

  Future<void> suspendUser(String userId) async {
    if (!_isAdmin) throw AdminPermissionException('Not admin');
    await _firestore.collection('users').doc(userId).update({
      'status': 'suspended',
      'suspendedAt': FieldValue.serverTimestamp(),
      'suspendedBy': _auth.user?.uid,
    });
  }

  Future<void> enableProvider(String providerId) async {
    if (!_isAdmin) throw AdminPermissionException('Not admin');
    await _firestore.collection('providers').doc(providerId).update({
      'enabled': true,
      'enabledAt': FieldValue.serverTimestamp(),
      'enabledBy': _auth.user?.uid,
    });
  }

  Future<void> disableProvider(String providerId) async {
    if (!_isAdmin) throw AdminPermissionException('Not admin');
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
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_options.dart';

/// Current authentication + authorisation state for the app shell.
enum AuthState { loading, signedOut, pendingApproval, approved, suspended }

/// Central authentication and access-control service.
///
/// Responsibilities:
///  * Google Sign-In and session restoration.
///  * Account status (pending / approved / suspended) from Firestore.
///  * Sign-out and account switching.
///  * Never lets a client promote itself or approve its own account — those
///    decisions live in Firestore security rules and owner-only logic.
class AuthService extends ChangeNotifier {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;

  AuthState _state = AuthState.loading;
  AuthState get state => _state;

  User? _user;
  User? get user => _user;

  bool _firebaseReady = false;
  bool get firebaseReady => _firebaseReady;

  String? _configError;
  String? get configError => _configError;

  /// Set by the owner allowlist / admin detection logic.
  bool _isAdmin = false;
  bool get isAdmin => _isAdmin;

  StreamSubscription<User?>? _authSub;
  Stream<AuthState> get stateStream => Stream.value(_state);

  /// Called from main() after optional Firebase wiring.
  void initialize({required bool firebaseConfigured}) {
    _firebaseReady = firebaseConfigured;
    if (!firebaseConfigured) {
      _state = AuthState.signedOut;
      _configError = DefaultFirebaseOptions.configurationStatus;
      notifyListeners();
      return;
    }
    _authSub = _auth.authStateChanges().listen(_onAuthChanged);
  }

  void _onAuthChanged(User? user) async {
    _user = user;
    if (user == null) {
      _state = AuthState.signedOut;
      _isAdmin = false;
      notifyListeners();
      return;
    }
    // Validate account status from Firestore.
    await _refreshAccountStatus();
  }

  Future<void> _refreshAccountStatus() async {
    final user = _user;
    if (user == null) return;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        _state = AuthState.pendingApproval;
        notifyListeners();
        return;
      }
      final status = (doc.data()?['status'] as String?) ?? 'pending';
      _isAdmin = (doc.data()?['role'] as String?) == 'owner' ||
          (doc.data()?['role'] as String?) == 'admin';
      switch (status) {
        case 'approved':
          _state = AuthState.approved;
        case 'suspended':
          _state = AuthState.suspended;
        default:
          _state = AuthState.pendingApproval;
      }
      notifyListeners();
    } catch (_) {
      // Offline / network error — keep last known state.
      notifyListeners();
    }
  }

  Future<void> signInWithGoogle() async {
    if (!_firebaseReady) {
      throw AuthConfigException(
        _configError ?? 'Firebase configuration is missing.',
      );
    }
    try {
      // google_sign_in v7.x: authenticate() returns GoogleSignInAccount directly
      final GoogleSignInAccount account = await _googleSignIn.authenticate();
      // In v7.x, account.authentication is a GoogleSignInAuthentication object
      // It provides idToken and serverAuthCode (not accessToken directly)
      final authInfo = account.authentication;
      final idToken = authInfo.idToken;
      if (idToken == null) {
        throw AuthConfigException('Google sign-in failed: No ID token received');
      }
      // Note: accessToken is not available in v7.x - Firebase only needs idToken
      final credential = GoogleAuthProvider.credential(
        idToken: idToken,
      );
      await _auth.signInWithCredential(credential);
      // _onAuthChanged will drive state.
    } on FirebaseAuthException catch (e) {
      throw AuthConfigException(
        'Google sign-in failed: ${e.message ?? e.code}',
      );
    } on GoogleSignInException catch (e) {
      throw AuthConfigException(
        'Google sign-in cancelled or failed: ${e.description ?? e.code}',
      );
    } catch (e) {
      throw AuthConfigException('Sign-in failed: $e');
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    _user = null;
    _isAdmin = false;
    _state = AuthState.signedOut;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

/// Raised when Firebase/Google configuration is absent or invalid.
class AuthConfigException implements Exception {
  AuthConfigException(this.message);
  final String message;
  @override
  String toString() => message;
}
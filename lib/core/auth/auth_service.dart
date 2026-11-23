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
///  * Account status (pending / approved / suspended) from Firestore with live sync.
///  * Sign-out and account switching.
///  * Never lets a client promote itself or approve its own account — those
///    decisions live in Firestore security rules and owner-only logic.
class AuthService extends ChangeNotifier {
  // Production factory that requires Firebase initialization
  factory AuthService.production({GoogleSignIn? googleSignIn}) {
    return AuthService(
      auth: FirebaseAuth.instance,
      firestore: FirebaseFirestore.instance,
      googleSignIn: googleSignIn ?? GoogleSignIn.instance,
    );
  }

  // Test factory that skips Firebase initialization
  factory AuthService.test() {
    return AuthService(
      auth: null,
      firestore: null,
      googleSignIn: GoogleSignIn.instance,
    );
  }

  AuthService({
    this._auth,
    this._firestore,
    GoogleSignIn? googleSignIn,
  })  : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth? _auth;
  final FirebaseFirestore? _firestore;
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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  Stream<AuthState> get stateStream => Stream.value(_state);

  static const String _defaultWebClientId =
      '222608500817-2n8h32n8j5l6c1ivgrj1a9lcd378htsj.apps.googleusercontent.com';

  Future<void>? _initFuture;

  /// Ensures [GoogleSignIn.initialize] is executed strictly once and safely reused.
  Future<void> _ensureInitialized() {
    const serverClientId = String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
      defaultValue: _defaultWebClientId,
    );
    _initFuture ??= _googleSignIn.initialize(
      serverClientId: serverClientId,
    );
    return _initFuture!;
  }

  /// Called from main() after optional Firebase wiring.
  void initialize({required bool firebaseConfigured}) {
    _firebaseReady = firebaseConfigured;

    // Initialize GoogleSignIn asynchronously in background without blocking app startup
    unawaited(_ensureInitialized().catchError((e) {
      debugPrint('GoogleSignIn ensureInitialized error: $e');
    }));

    if (!firebaseConfigured || _auth == null) {
      _state = AuthState.signedOut;
      _configError = DefaultFirebaseOptions.configurationStatus;
      notifyListeners();
      return;
    }
    _authSub = _auth.authStateChanges().listen(_onAuthChanged);
  }

  /// Called when splash animation finishes. If auth status is still loading, transition to signedOut.
  void onSplashFinished() {
    if (_state == AuthState.loading) {
      _state = _user != null ? AuthState.pendingApproval : AuthState.signedOut;
      notifyListeners();
    }
  }

  void _onAuthChanged(User? user) async {
    _user = user;
    await _userDocSub?.cancel();
    _userDocSub = null;

    if (user == null) {
      _state = AuthState.signedOut;
      _isAdmin = false;
      notifyListeners();
      return;
    }

    // Set up real-time listener on user's status document in Firestore
    if (_firestore != null) {
      _userDocSub = _firestore
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen(
        (doc) async {
          if (!doc.exists) {
            // First time sign in: create initial user document in Firestore
            try {
              await _firestore.collection('users').doc(user.uid).set({
                'uid': user.uid,
                'email': user.email,
                'displayName': user.displayName,
                'photoURL': user.photoURL,
                'status': 'pending',
                'role': 'member',
                'createdAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            } catch (e) {
              debugPrint('Error creating user doc in Firestore: $e');
            }
            _state = AuthState.pendingApproval;
            _isAdmin = false;
            notifyListeners();
            return;
          }
          final data = doc.data();
          final status = (data?['status'] as String?) ?? 'pending';
          final role = data?['role'] as String?;
          _isAdmin = role == 'owner' || role == 'admin';
          switch (status) {
            case 'approved':
              _state = AuthState.approved;
            case 'suspended':
              _state = AuthState.suspended;
            default:
              _state = AuthState.pendingApproval;
          }
          notifyListeners();
        },
        onError: (e) {
          debugPrint('AuthService user doc stream error: $e');
          _refreshAccountStatus();
        },
      );
    } else {
      await _refreshAccountStatus();
    }
  }

  Future<void> _refreshAccountStatus() async {
    final user = _user;
    if (user == null) return;
    if (_firestore == null) {
      _state = AuthState.signedOut;
      notifyListeners();
      return;
    }
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
    if (!_firebaseReady || _auth == null) {
      throw AuthConfigException(
        _configError ?? 'Firebase configuration is missing.',
      );
    }
    try {
      await _ensureInitialized();

      final GoogleSignInAccount? account = await _googleSignIn.authenticate();
      if (account == null) {
        // User dismissed the account picker dialog
        return;
      }

      final GoogleSignInAuthentication authInfo = await account.authentication;
      final idToken = authInfo.idToken;

      debugPrint('Google Sign-In account: ${account.email}, idToken: ${idToken != null}');

      if (idToken == null) {
        throw AuthConfigException(
          'Google sign-in failed: No ID token received from Google. Make sure the Web Client ID is configured.',
        );
      }

      final credential = GoogleAuthProvider.credential(
        idToken: idToken,
      );
      await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuthException: ${e.code} ${e.message}');
      throw AuthConfigException(
        'Firebase auth error: ${e.message ?? e.code}',
      );
    } on GoogleSignInException catch (e) {
      debugPrint('GoogleSignInException: code=${e.code} description=${e.description}');
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw AuthConfigException(
          'Google sign-in was canceled or blocked. Ensure a Google account is logged into the emulator and your debug keystore SHA-1 is registered in Firebase Console.',
        );
      }
      throw AuthConfigException(
        'Google sign-in failed: ${e.description ?? e.code}',
      );
    } catch (e) {
      debugPrint('General sign-in exception: $e');
      throw AuthConfigException('Sign-in failed: $e');
    }
  }

  Future<void> signOut() async {
    await _userDocSub?.cancel();
    _userDocSub = null;
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    if (_auth != null) {
      await _auth.signOut();
    }
    _user = null;
    _isAdmin = false;
    _state = AuthState.signedOut;
    notifyListeners();
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
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

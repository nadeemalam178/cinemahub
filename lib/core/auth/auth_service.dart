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
///  * Custom claim token refresh when role changes.
///  * Sign-out and account switching.
///  * Never lets a client promote itself or approve its own account — those
///    decisions live in Firestore security rules and Cloud Functions.
class AuthService extends ChangeNotifier {
  factory AuthService.production({GoogleSignIn? googleSignIn}) {
    return AuthService(
      auth: FirebaseAuth.instance,
      firestore: FirebaseFirestore.instance,
      googleSignIn: googleSignIn ?? GoogleSignIn.instance,
    );
  }

  factory AuthService.test() {
    return AuthService(
      auth: null,
      firestore: null,
      googleSignIn: null,
    );
  }

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth,
        // ignore: prefer_initializing_formals
        _firestore = firestore,
        _googleSignIn = googleSignIn ?? (auth == null ? null : GoogleSignIn.instance);

  final FirebaseAuth? _auth;
  final FirebaseFirestore? _firestore;
  final GoogleSignIn? _googleSignIn;

  final StreamController<AuthState> _stateController =
      StreamController<AuthState>.broadcast();

  AuthState _state = AuthState.loading;
  AuthState get state => _state;

  User? _user;
  User? get user => _user;

  bool _firebaseReady = false;
  bool get firebaseReady => _firebaseReady;

  String? _configError;
  String? get configError => _configError;

  String? _role;
  String? get role => _role;

  /// Whether the current user has admin or owner privileges.
  bool _isAdmin = false;
  bool get isAdmin => _isAdmin;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  String? _sessionTouchedUid;

  Stream<AuthState> get stateStream => _stateController.stream;

  static const String _defaultWebClientId =
      '222608500817-2n8h32n8j5l6c1ivgrj1a9lcd378htsj.apps.googleusercontent.com';

  Future<void>? _initFuture;

  Future<void> _ensureInitialized() async {
    if (_googleSignIn == null) return;
    const serverClientId = String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
      defaultValue: _defaultWebClientId,
    );
    _initFuture ??= _googleSignIn.initialize(
      serverClientId: serverClientId,
    );
    await _initFuture!;
  }

  void _setState(AuthState next, {bool forceNotify = false}) {
    final changed = _state != next;
    _state = next;
    if (changed && !_stateController.isClosed) {
      _stateController.add(next);
    }
    if (changed || forceNotify) {
      notifyListeners();
    }
  }

  void _applyUserDoc(Map<String, dynamic>? data) {
    final status = (data?['status'] as String?) ?? 'pending';
    final nextRole = data?['role'] as String?;
    final roleChanged = nextRole != _role;
    final prevAdmin = _isAdmin;

    _role = nextRole;
    _isAdmin = nextRole == 'owner' || nextRole == 'admin';

    if (roleChanged && _user != null) {
      unawaited(_user!.getIdToken(true).catchError((_) => null));
    }

    final nextState = switch (status) {
      'approved' => AuthState.approved,
      'suspended' => AuthState.suspended,
      _ => AuthState.pendingApproval,
    };

    _setState(nextState, forceNotify: roleChanged || prevAdmin != _isAdmin);
  }

  /// Called from main() after optional Firebase wiring.
  void initialize({required bool firebaseConfigured}) {
    _firebaseReady = firebaseConfigured;

    unawaited(_ensureInitialized().catchError((e) {
      debugPrint('GoogleSignIn ensureInitialized error: $e');
    }));

    if (!firebaseConfigured || _auth == null) {
      _configError = DefaultFirebaseOptions.configurationStatus;
      _setState(AuthState.signedOut, forceNotify: true);
      return;
    }
    _authSub = _auth.authStateChanges().listen(_onAuthChanged);
  }

  /// Called when splash animation finishes.
  void onSplashFinished() {
    if (_state != AuthState.loading) return;
    if (_user == null) {
      _setState(AuthState.signedOut);
    } else {
      unawaited(_refreshAccountStatus(fallbackToPending: true));
    }
  }

  Future<void> _onAuthChanged(User? user) async {
    _user = user;
    await _userDocSub?.cancel();
    _userDocSub = null;

    if (user == null) {
      _role = null;
      _isAdmin = false;
      _sessionTouchedUid = null;
      _setState(AuthState.signedOut, forceNotify: true);
      return;
    }

    if (_firestore != null) {
      _userDocSub = _firestore
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen(
        (doc) async {
          if (!doc.exists) {
            // Create profile fields only; status/role are assigned server-side by onUserCreate.
            try {
              await _firestore.collection('users').doc(user.uid).set({
                'uid': user.uid,
                'email': user.email ?? '',
                'displayName': user.displayName ?? '',
                'photoURL': user.photoURL ?? '',
                'createdAt': FieldValue.serverTimestamp(),
                'lastActive': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            } catch (e) {
              debugPrint('Error creating user doc in Firestore: $e');
            }
            _role = null;
            _isAdmin = false;
            _setState(AuthState.pendingApproval, forceNotify: true);
            return;
          }

          if (_sessionTouchedUid != user.uid) {
            _sessionTouchedUid = user.uid;
            unawaited(
              _firestore
                  .collection('users')
                  .doc(user.uid)
                  .update({'lastActive': FieldValue.serverTimestamp()})
                  .catchError((_) {}),
            );
          }

          _applyUserDoc(doc.data());
        },
        onError: (e) {
          debugPrint('AuthService user doc stream error: $e');
          unawaited(_refreshAccountStatus());
        },
      );
    } else {
      await _refreshAccountStatus();
    }
  }

  Future<void> _refreshAccountStatus({bool fallbackToPending = false}) async {
    final user = _user;
    if (user == null) {
      _setState(AuthState.signedOut);
      return;
    }
    if (_firestore == null) {
      _setState(AuthState.signedOut);
      return;
    }
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        if (fallbackToPending) {
          _setState(AuthState.pendingApproval);
        }
        return;
      }
      _applyUserDoc(doc.data());
    } catch (_) {
      if (fallbackToPending && _state == AuthState.loading) {
        _setState(AuthState.pendingApproval);
      } else {
        notifyListeners();
      }
    }
  }

  Future<void> signInWithGoogle() async {
    if (!_firebaseReady || _auth == null) {
      throw AuthConfigException(
        _configError ?? 'Firebase configuration is missing.',
      );
    }
    try {
      final googleSignIn = _googleSignIn;
      if (googleSignIn == null) {
        throw AuthConfigException('Google Sign-In is not initialized.');
      }
      await _ensureInitialized();

      final account = await googleSignIn.authenticate();
      final idToken = account.authentication.idToken;

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
      await _googleSignIn?.signOut();
    } catch (_) {}
    if (_auth != null) {
      await _auth.signOut();
    }
    _user = null;
    _role = null;
    _isAdmin = false;
    _sessionTouchedUid = null;
    _setState(AuthState.signedOut, forceNotify: true);
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
    _authSub?.cancel();
    _stateController.close();
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

// Purpose: Manages authentication state and exposes auth actions to the widget tree.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/activity_log_model.dart';
import '../models/app_user_model.dart';
import '../models/member_permission_model.dart';
import '../services/auth_service.dart';

enum GoogleSignInOutcome { success, newUser, needsLinking, cancelled }

enum AuthStatus {
  /// Initial state — waiting for Firebase to report auth state.
  unknown,

  /// No signed-in user.
  unauthenticated,

  /// User is authenticated but has not completed company setup yet.
  noCompany,

  /// Fully authenticated with a company affiliation.
  authenticated,
}

class AuthController extends ChangeNotifier {
  AuthController(this._authService);

  final AuthService _authService;

  static const String _guestKey = 'auth_local_guest';

  OAuthCredential? _pendingGoogleCredential;
  String? _pendingGoogleEmail;

  AuthStatus _status = AuthStatus.unknown;
  AppUser? _user;
  String? _errorMessage;
  StreamSubscription<User?>? _authSub;

  AuthStatus get status => _status;
  AppUser? get user => _user;
  String? get errorMessage => _errorMessage;
  String? get pendingGoogleEmail => _pendingGoogleEmail;

  /// Returns the current Firebase ID token, or null if not signed in.
  Future<String?> getIdToken() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return Future.value(null);
    return currentUser.getIdToken();
  }

  /// Start listening to Firebase auth state changes. Call once from main.
  void init() {
    _initAsync();
  }

  Future<void> _initAsync() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_guestKey) == true) {
      _status = AuthStatus.authenticated;
      _user = _buildGuestUser();
      notifyListeners();
      return; // Guest mode — no Firebase listener needed
    }
    _authSub = FirebaseAuth.instance
        .authStateChanges()
        .listen(_handleAuthChange);
  }

  // ── Sign-in / sign-out ─────────────────────────────────────────────────────

  Future<void> signIn(String email, String password) async {
    _clearError();
    try {
      await _authService.signIn(email, password);
      // Auth state change fires automatically — _handleAuthChange takes over.
    } on FirebaseAuthException catch (e) {
      _setError(_mapFirebaseError(e));
      rethrow;
    }
  }

  /// Enters a fully local guest session — no Firebase required.
  Future<void> continueAsGuest() async {
    _clearError();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_guestKey, true);
    _status = AuthStatus.authenticated;
    _user = _buildGuestUser();
    notifyListeners();
  }

  Future<GoogleSignInOutcome> signInWithGoogle() async {
    _clearError();
    try {
      final googleAccount = await GoogleSignIn.instance.authenticate();
      final idToken = googleAccount.authentication.idToken;
      final credential = GoogleAuthProvider.credential(idToken: idToken);

      try {
        final userCredential =
            await FirebaseAuth.instance.signInWithCredential(credential);
        final isNewUser =
            userCredential.additionalUserInfo?.isNewUser ?? false;
        return isNewUser
            ? GoogleSignInOutcome.newUser
            : GoogleSignInOutcome.success;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'account-exists-with-different-credential') {
          _pendingGoogleCredential = credential;
          _pendingGoogleEmail = e.email;
          return GoogleSignInOutcome.needsLinking;
        }
        rethrow;
      }
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return GoogleSignInOutcome.cancelled;
      }
      _setError(e.description ?? 'Google Sign-In failed.');
      return GoogleSignInOutcome.cancelled;
    } on FirebaseAuthException catch (e) {
      _setError(_mapFirebaseError(e));
      rethrow;
    }
  }

  /// Signs in with email/password and links the pending Google credential.
  Future<void> linkWithPassword(String password) async {
    _clearError();
    final email = _pendingGoogleEmail;
    final googleCred = _pendingGoogleCredential;
    if (email == null || googleCred == null) {
      throw StateError('No pending Google credential to link.');
    }
    try {
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      await userCredential.user?.linkWithCredential(googleCred);
      _pendingGoogleCredential = null;
      _pendingGoogleEmail = null;
    } on FirebaseAuthException catch (e) {
      _setError(_mapFirebaseError(e));
      rethrow;
    }
  }

  /// Adds an email/password credential to the currently signed-in Google user.
  Future<void> addPasswordToAccount(String password) async {
    _clearError();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) throw StateError('Not signed in.');
    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      _setError(_mapFirebaseError(e));
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    _clearError();
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      _setError(_mapFirebaseError(e));
      rethrow;
    }
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_guestKey);
    if (_user?.isGuest == true) {
      _status = AuthStatus.unauthenticated;
      _user = null;
      notifyListeners();
      // Re-attach Firebase listener so normal sign-in works after guest exit.
      _authSub?.cancel();
      _authSub = FirebaseAuth.instance
          .authStateChanges()
          .listen(_handleAuthChange);
      return;
    }
    // Sign out of Firebase first — this drives the router redirect via the
    // authStateChanges listener, so navigation happens even if Google
    // sign-out hangs or throws (e.g. when GoogleSignIn was never initialised
    // because the user signed in with email/password).
    await _authService.signOut();
    try {
      await GoogleSignIn.instance
          .signOut()
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // User may not have signed in with Google, plugin not initialised,
      // or call timed out — ignore; Firebase sign-out already succeeded.
    }
  }

  // ── Registration (new company owner) ──────────────────────────────────────

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    required String companyName,
  }) async {
    _clearError();
    try {
      final credential = await _authService.createAccount(email, password);
      await credential.user?.updateDisplayName(displayName);

      final idToken = await credential.user?.getIdToken();
      if (idToken == null) throw StateError('Failed to retrieve authentication token.');

      await _authService.setupCompany(companyName, idToken);

      // Firebase custom claims can take a few seconds to propagate to the client.
      // Retry the force-refresh up to 5 times (max ~8s) until companyId appears.
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        for (int attempt = 0; attempt < 5; attempt++) {
          await Future.delayed(const Duration(milliseconds: 1500));
          final tokenResult = await firebaseUser.getIdTokenResult(true);
          final companyId = tokenResult.claims?['companyId'] as String?;
          if (companyId != null && companyId.isNotEmpty) {
            await _loadFromToken(firebaseUser, forceRefresh: false);
            break;
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      _setError(_mapFirebaseError(e));
      rethrow;
    } on StateError catch (e) {
      _setError(e.message);
      rethrow;
    }
  }

  // ── Company setup (recovery for noCompany state) ───────────────────────────

  Future<void> setupCompany(String companyName) async {
    _clearError();
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) throw StateError('Not authenticated.');

    try {
      final idToken = await firebaseUser.getIdToken();
      if (idToken == null) throw StateError('Failed to retrieve authentication token.');
      await _authService.setupCompany(companyName, idToken);
      // Retry the force-refresh until the companyId claim appears (max ~8s).
      for (int attempt = 0; attempt < 5; attempt++) {
        await Future.delayed(const Duration(milliseconds: 1500));
        final tokenResult = await firebaseUser.getIdTokenResult(true);
        final companyId = tokenResult.claims?['companyId'] as String?;
        if (companyId != null && companyId.isNotEmpty) {
          await _loadFromToken(firebaseUser, forceRefresh: false);
          break;
        }
      }
    } on StateError {
      rethrow;
    } catch (e) {
      throw StateError('Could not reach server: $e');
    }
  }

  // ── Team management ────────────────────────────────────────────────────────

  Future<TeamMember> createTeamMember({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final token = await getIdToken();
    if (token == null) throw StateError('Not authenticated.');
    return _authService.createTeamMember(
      email: email,
      password: password,
      displayName: displayName,
      idToken: token,
    );
  }

  Future<List<TeamMember>> listTeamMembers() async {
    final token = await getIdToken();
    if (token == null) return const [];
    return _authService.listTeamMembers(token);
  }

  Future<void> removeTeamMember(String uid) async {
    final token = await getIdToken();
    if (token == null) throw StateError('Not authenticated.');
    await _authService.removeTeamMember(uid, token);
  }

  // ── Team-settings: permissions ─────────────────────────────────────────────

  /// List all permissions visible to the current user.
  /// Owner: all company permissions. Member: own only.
  Future<List<MemberPermission>> listPermissions() async {
    final token = await getIdToken();
    if (token == null) return const [];
    return _authService.listPermissions(token);
  }

  /// Owner: fetch all project permissions for a specific team member.
  Future<List<MemberPermission>> getMemberPermissions(String memberUid) async {
    final token = await getIdToken();
    if (token == null) return const [];
    return _authService.getMemberPermissions(memberUid, token);
  }

  /// Owner: update a member's permissions for one specific project.
  Future<MemberPermission> setMemberProjectPermissions({
    required String memberUid,
    required String projectId,
    required MemberPermission permission,
  }) async {
    final token = await getIdToken();
    if (token == null) throw StateError('Not authenticated.');
    final saved = await _authService.setMemberProjectPermissions(
      memberUid: memberUid,
      projectId: projectId,
      permission: permission,
      idToken: token,
    );
    // Invalidate any cached entry for this user/project so member clients
    // pick up the new permissions on the next access.
    _projectPermissionsCache.remove(projectId);
    return saved;
  }

  // ── Current-user project permissions cache ─────────────────────────────────
  //
  // Used by feature screens to gate UI based on the signed-in member's
  // per-project permissions. Owners and guests always get a fully-permissive
  // record (UI gating is a no-op for them; the backend is the actual gate).

  final Map<String, MemberPermission> _projectPermissionsCache = {};

  /// Returns the permissions for the **current** user on [projectId].
  /// Cached for the lifetime of the controller (cleared on sign-out).
  /// Owners / guests get a fully-allow record without a backend call.
  Future<MemberPermission> permissionsForProject(String projectId) async {
    final currentUser = _user;
    if (currentUser == null || currentUser.isOwner || currentUser.isGuest) {
      return MemberPermission(
        uid: currentUser?.uid ?? '',
        projectId: projectId,
        companyId: currentUser?.companyId ?? '',
        canView: true,
        canRecord: true,
        canTranscribe: true,
        canEditDocument: true,
        canExport: true,
        canDeleteTranscript: true,
        canCreateProject: true,
        canEditProject: true,
        canDeleteProject: true,
        canManageTemplates: true,
        canUploadFiles: true,
        canViewSow: true,
        canCreateSow: true,
        canDeleteSow: true,
        canViewPdf: true,
        canCreatePdf: true,
        canDeletePdf: true,
      );
    }
    final cached = _projectPermissionsCache[projectId];
    if (cached != null) return cached;
    final token = await getIdToken();
    if (token == null) {
      return MemberPermission.defaultFor(
        uid: currentUser.uid,
        projectId: projectId,
        companyId: currentUser.companyId,
      );
    }
    try {
      final all = await _authService.listPermissions(token);
      final match = all.firstWhere(
        (p) => p.projectId == projectId && p.uid == currentUser.uid,
        orElse: () => MemberPermission.defaultFor(
          uid: currentUser.uid,
          projectId: projectId,
          companyId: currentUser.companyId,
        ),
      );
      _projectPermissionsCache[projectId] = match;
      return match;
    } catch (_) {
      return MemberPermission.defaultFor(
        uid: currentUser.uid,
        projectId: projectId,
        companyId: currentUser.companyId,
      );
    }
  }

  /// Drop the cached permissions (e.g. on sign-out or when an owner edits a
  /// member's permissions from another client and we want to force a refresh).
  void clearProjectPermissionsCache() {
    _projectPermissionsCache.clear();
  }

  // ── Activity logs ──────────────────────────────────────────────────────────

  /// Fetch activity logs. Owner gets all; member gets own only.
  Future<List<ActivityLogEntry>> getActivityLogs({
    int limit = 50,
    String? before,
    String? projectId,
  }) async {
    final token = await getIdToken();
    if (token == null) return const [];
    return _authService.getActivityLogs(
      token,
      limit: limit,
      before: before,
      projectId: projectId,
    );
  }

  /// Write an activity log entry. Silently ignores failures (guest / no token).
  Future<void> logActivity({
    required String action,
    String? projectId,
    String? projectName,
    String? details,
  }) async {
    if (_user?.isGuest == true) return;
    final token = await getIdToken();
    if (token == null) return;
    try {
      await _authService.logActivity(
        token,
        action: action,
        projectId: projectId,
        projectName: projectName,
        details: details,
      );
    } catch (_) {
      // Non-fatal — log failures must never disrupt the user flow.
    }
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<void> _handleAuthChange(User? firebaseUser) async {
    if (firebaseUser == null) {
      _status = AuthStatus.unauthenticated;
      _user = null;
      _projectPermissionsCache.clear();
      notifyListeners();
      return;
    }
    await _loadFromToken(firebaseUser);
  }

  Future<void> _loadFromToken(User firebaseUser, {bool forceRefresh = false}) async {
    final tokenResult = await firebaseUser.getIdTokenResult(forceRefresh);
    final companyId = tokenResult.claims?['companyId'] as String?;
    final role = tokenResult.claims?['role'] as String? ?? 'member';

    if (companyId == null || companyId.isEmpty) {
      _status = AuthStatus.noCompany;
      _user = null;
    } else {
      _status = AuthStatus.authenticated;
      _user = AppUser(
        uid: firebaseUser.uid,
        email: firebaseUser.email ?? '',
        displayName: firebaseUser.displayName ?? '',
        companyId: companyId,
        role: role,
      );
    }
    notifyListeners();
  }

  AppUser _buildGuestUser() => AppUser(
        uid: 'guest-local',
        email: '',
        displayName: 'Guest',
        companyId: 'guest',
        role: 'guest',
        isGuest: true,
      );

  void _clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  String _mapFirebaseError(FirebaseAuthException e) {
    return switch (e.code) {
      'user-not-found' || 'wrong-password' || 'invalid-credential' =>
        'Invalid email or password.',
      'email-already-in-use' => 'An account with this email already exists.',
      'account-exists-with-different-credential' =>
        'An account already exists with this email.',
      'credential-already-in-use' =>
        'This Google account is already linked to another account.',
      'weak-password' => 'Password must be at least 6 characters.',
      'invalid-email' => 'Please enter a valid email address.',
      'too-many-requests' => 'Too many attempts. Please try again later.',
      'network-request-failed' => 'Network error. Check your connection.',
      'requires-recent-login' => 'Please sign in again to complete this action.',
      _ => e.message ?? 'Authentication failed.',
    };
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

// Purpose: Wraps Firebase Auth calls and backend auth API endpoints.
import 'dart:convert';

import 'package:buildercam/core/config/api_config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/activity_log_model.dart';
import '../models/app_user_model.dart';
import '../models/member_permission_model.dart';

class AuthService {
  AuthService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri get _baseUri => Uri.parse(ApiConfig.sowProxyBaseUrl);

  // ── Firebase Auth ──────────────────────────────────────────────────────────

  Future<UserCredential> signIn(String email, String password) {
    return FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> createAccount(String email, String password) {
    return FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() => FirebaseAuth.instance.signOut();

  // ── Backend auth API ───────────────────────────────────────────────────────

  Future<void> setupCompany(String companyName, String idToken) async {
    final response = await _client.post(
      _baseUri.resolve('/api/auth/setup-company'),
      headers: _headers(idToken),
      body: jsonEncode({'companyName': companyName}),
    );
    _assertSuccess(response, 'setupCompany');
  }

  /// Fetch the full user profile (including [hasSeenWelcome]) from the backend.
  Future<Map<String, dynamic>?> fetchMe(String idToken) async {
    final response = await _client.get(
      _baseUri.resolve('/api/auth/me'),
      headers: _headers(idToken),
    );
    if (response.statusCode >= 400) return null;
    final payload = _decode(response);
    return payload['user'] as Map<String, dynamic>?;
  }

  /// Marks the welcome screen as seen in Firestore (cross-device persisted).
  Future<void> markWelcomeSeen(String idToken) async {
    try {
      await _client.post(
        _baseUri.resolve('/api/auth/mark-welcome-seen'),
        headers: _headers(idToken),
      );
    } catch (_) {
      // Non-fatal — worst case user sees welcome again on next cold start.
    }
  }

  Future<TeamMember> createTeamMember({
    required String email,
    required String password,
    required String displayName,
    required String idToken,
  }) async {
    final response = await _client.post(
      _baseUri.resolve('/api/auth/team-members'),
      headers: _headers(idToken),
      body: jsonEncode({
        'email': email,
        'password': password,
        'displayName': displayName,
      }),
    );
    _assertSuccess(response, 'createTeamMember');
    final payload = _decode(response);
    return TeamMember.fromJson(payload['member'] as Map<String, dynamic>? ?? {});
  }

  Future<List<TeamMember>> listTeamMembers(String idToken) async {
    final response = await _client.get(
      _baseUri.resolve('/api/auth/team-members'),
      headers: _headers(idToken),
    );
    _assertSuccess(response, 'listTeamMembers');
    final payload = _decode(response);
    final raw = payload['members'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map(TeamMember.fromJson).toList();
  }

  Future<void> removeTeamMember(String uid, String idToken) async {
    final response = await _client.delete(
      _baseUri.resolve('/api/auth/team-members/$uid'),
      headers: _headers(idToken),
    );
    if (response.statusCode != 404) {
      _assertSuccess(response, 'removeTeamMember');
    }
  }

  // ── Team-settings: permissions ─────────────────────────────────────────────

  /// Returns all permission records visible to the caller.
  /// Owner: all company permissions. Member: own permissions only.
  Future<List<MemberPermission>> listPermissions(String idToken) async {
    final response = await _client.get(
      _baseUri.resolve('/api/team-settings/permissions'),
      headers: _headers(idToken),
    );
    _assertSuccess(response, 'listPermissions');
    final payload = _decode(response);
    final raw = payload['permissions'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MemberPermission.fromJson)
        .toList();
  }

  /// Owner: get all project permissions for a specific member.
  Future<List<MemberPermission>> getMemberPermissions(
    String memberUid,
    String idToken,
  ) async {
    final response = await _client.get(
      _baseUri.resolve('/api/team-settings/permissions/$memberUid'),
      headers: _headers(idToken),
    );
    _assertSuccess(response, 'getMemberPermissions');
    final payload = _decode(response);
    final raw = payload['permissions'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MemberPermission.fromJson)
        .toList();
  }

  /// Owner: set a member's permissions for a specific project.
  Future<MemberPermission> setMemberProjectPermissions({
    required String memberUid,
    required String projectId,
    required MemberPermission permission,
    required String idToken,
  }) async {
    final response = await _client.put(
      _baseUri.resolve('/api/team-settings/permissions/$memberUid/$projectId'),
      headers: _headers(idToken),
      body: jsonEncode(permission.toJson()),
    );
    _assertSuccess(response, 'setMemberProjectPermissions');
    final payload = _decode(response);
    return MemberPermission.fromJson(
      payload['permission'] as Map<String, dynamic>? ?? {},
    );
  }

  // ── Company settings ───────────────────────────────────────────────────────

  Future<void> deleteAccount(String idToken) async {
    final response = await _client.delete(
      _baseUri.resolve('/api/auth/account'),
      headers: _headers(idToken),
    );
    _assertSuccess(response, 'deleteAccount');
  }

  Future<CompanySettings> fetchCompanySettings(String idToken) async {
    final response = await _client.get(
      _baseUri.resolve('/api/auth/company-settings'),
      headers: _headers(idToken),
    );
    _assertSuccess(response, 'fetchCompanySettings');
    final payload = _decode(response);
    return CompanySettings.fromJson(
      payload['settings'] as Map<String, dynamic>? ?? {},
    );
  }

  Future<CompanySettings> updateCompanySettings({
    required List<String> categories,
    required String notes,
    required String idToken,
  }) async {
    final response = await _client.put(
      _baseUri.resolve('/api/auth/company-settings'),
      headers: _headers(idToken),
      body: jsonEncode({'categories': categories, 'notes': notes}),
    );
    _assertSuccess(response, 'updateCompanySettings');
    final payload = _decode(response);
    return CompanySettings.fromJson(
      payload['settings'] as Map<String, dynamic>? ?? {},
    );
  }

  // ── Activity logs ──────────────────────────────────────────────────────────

  /// Fetch activity logs. Owner sees all; member sees own only.
  /// [before]: ISO timestamp for cursor-based pagination.
  /// [projectId]: optional filter to show only logs for a specific project.
  Future<List<ActivityLogEntry>> getActivityLogs(
    String idToken, {
    int limit = 50,
    String? before,
    String? projectId,
  }) async {
    final uri = _baseUri.resolve('/api/activity-logs').replace(
      queryParameters: {
        'limit': limit.toString(),
        if (before != null) 'before': before,
        if (projectId != null) 'projectId': projectId,
      },
    );
    final response = await _client.get(uri, headers: _headers(idToken));
    _assertSuccess(response, 'getActivityLogs');
    final payload = _decode(response);
    final raw = payload['logs'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ActivityLogEntry.fromJson)
        .toList();
  }

  /// Write a new activity log entry for the current user.
  Future<void> logActivity(
    String idToken, {
    required String action,
    String? projectId,
    String? projectName,
    String? details,
  }) async {
    final response = await _client.post(
      _baseUri.resolve('/api/activity-logs'),
      headers: _headers(idToken),
      body: jsonEncode({
        'action': action,
        if (projectId != null) 'projectId': projectId,
        if (projectName != null) 'projectName': projectName,
        if (details != null) 'details': details,
      }),
    );
    _assertSuccess(response, 'logActivity');
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Map<String, String> _headers(String idToken) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $idToken',
  };

  void _assertSuccess(http.Response response, String action) {
    if (response.statusCode >= 400) {
      final decoded = _decode(response);
      final message =
          decoded['message'] as String? ??
          'Request failed with status ${response.statusCode}.';
      if (kDebugMode) {
        debugPrint('[AuthService] $action failed (${response.statusCode}): $message');
      }
      throw StateError(message);
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return {};
  }
}

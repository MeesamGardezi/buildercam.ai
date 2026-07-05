// Purpose: Data models for the authenticated user and team members.

/// Represents the currently authenticated user with their company affiliation.
class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.companyId,
    required this.role,
    this.isVip = false,
    this.isGuest = false,
    this.hasSeenWelcome = true,
  });

  final String uid;
  final String email;
  final String displayName;
  final String companyId;

  /// 'owner', 'member', or 'guest'
  final String role;

  /// VIP flag is independent of role — owners can also be VIP.
  final bool isVip;

  final bool isGuest;

  /// False only for brand-new accounts that haven't dismissed the welcome screen yet.
  /// Stored in Firestore so it persists across devices.
  final bool hasSeenWelcome;

  bool get isOwner => role == 'owner';

  /// Two-letter initials derived from display name or email.
  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      return email.isNotEmpty ? email[0].toUpperCase() : '?';
    }
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

/// Represents a team member record returned from the backend API.
class TeamMember {
  const TeamMember({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.companyId,
    required this.role,
    this.isVip = false,
    this.createdAt,
  });

  factory TeamMember.fromJson(Map<String, dynamic> json) {
    return TeamMember(
      uid: json['uid'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      companyId: json['companyId'] as String? ?? '',
      role: json['role'] as String? ?? 'member',
      isVip: json['isVip'] as bool? ?? false,
      createdAt: json['createdAt'] as String?,
    );
  }

  final String uid;
  final String email;
  final String displayName;
  final String companyId;
  final String role;
  final bool isVip;
  final String? createdAt;

  bool get isOwner => role == 'owner';
}

/// Company-wide AI generation settings managed by the owner.
class CompanySettings {
  const CompanySettings({
    this.categories = const [],
    this.notes = '',
    this.logoUrl = '',
    this.companyName = '',
    this.address = '',
    this.phone = '',
    this.email = '',
  });

  factory CompanySettings.fromJson(Map<String, dynamic> json) {
    final rawCats = json['categories'];
    return CompanySettings(
      categories: rawCats is List
          ? rawCats.whereType<String>().toList(growable: false)
          : const [],
      notes: json['notes'] as String? ?? '',
      logoUrl: json['logoUrl'] as String? ?? '',
      companyName: json['companyName'] as String? ?? '',
      address: json['address'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
    );
  }

  final List<String> categories;
  final String notes;
  final String logoUrl;
  final String companyName;
  final String address;
  final String phone;
  final String email;
}

/// Mirrors the backend's TwoFactorStatusResponse.
class TwoFactorStatus {
  final bool enabled;
  final String? method; // "PHONE" | "EMAIL" | null when not enabled
  final bool emailVerified;
  final String? maskedEmail;
  final bool phoneVerified;
  final String? maskedPhone;

  const TwoFactorStatus({
    required this.enabled,
    this.method,
    required this.emailVerified,
    this.maskedEmail,
    required this.phoneVerified,
    this.maskedPhone,
  });

  factory TwoFactorStatus.fromJson(Map<String, dynamic> json) {
    return TwoFactorStatus(
      enabled: json['enabled'] as bool? ?? false,
      method: json['method'] as String?,
      emailVerified: json['emailVerified'] as bool? ?? false,
      maskedEmail: json['maskedEmail'] as String?,
      phoneVerified: json['phoneVerified'] as bool? ?? false,
      maskedPhone: json['maskedPhone'] as String?,
    );
  }
}

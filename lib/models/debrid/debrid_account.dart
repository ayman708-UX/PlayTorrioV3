enum DebridProvider {
  realDebrid('Real-Debrid', 'https://api.real-debrid.com/rest/1.0'),
  torbox('Torbox', 'https://api.torbox.app/v1/api'),
  allDebrid('AllDebrid', 'https://api.alldebrid.com/v4'),
  premiumize('Premiumize', 'https://www.premiumize.me/api');

  final String displayName;
  final String apiUrl;
  const DebridProvider(this.displayName, this.apiUrl);
}

class DebridAccount {
  final DebridProvider provider;
  final String apiKey;
  final String? username;
  final String? email;
  final DateTime? expirationDate;
  final bool isPremium;

  const DebridAccount({
    required this.provider,
    required this.apiKey,
    this.username,
    this.email,
    this.expirationDate,
    this.isPremium = false,
  });

  Map<String, dynamic> toJson() => {
        'provider': provider.name,
        'apiKey': apiKey,
        if (username != null) 'username': username,
        if (email != null) 'email': email,
        if (expirationDate != null)
          'expirationDate': expirationDate!.toIso8601String(),
        'isPremium': isPremium,
      };

  factory DebridAccount.fromJson(Map<String, dynamic> json) {
    return DebridAccount(
      provider: DebridProvider.values.firstWhere(
        (p) => p.name == json['provider'],
        orElse: () => DebridProvider.realDebrid,
      ),
      apiKey: json['apiKey'] as String? ?? '',
      username: json['username'] as String?,
      email: json['email'] as String?,
      expirationDate: json['expirationDate'] != null
          ? DateTime.tryParse(json['expirationDate'] as String)
          : null,
      isPremium: json['isPremium'] as bool? ?? false,
    );
  }
}

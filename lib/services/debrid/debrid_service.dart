import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/debrid/debrid_account.dart';

class DebridService {
  DebridService._();
  static final DebridService instance = DebridService._();

  static const _storageKey = 'debrid_accounts_v1';
  final ValueNotifier<List<DebridAccount>> accounts = ValueNotifier<List<DebridAccount>>([]);
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey);
    if (stored != null) {
      try {
        final list = (jsonDecode(stored) as List)
            .map((e) => DebridAccount.fromJson(e as Map<String, dynamic>))
            .toList();
        accounts.value = list;
      } catch (_) {
        accounts.value = [];
      }
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(accounts.value.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, data);
  }

  bool isConfigured(DebridProvider provider) {
    return accounts.value.any((a) => a.provider == provider && a.apiKey.isNotEmpty);
  }

  DebridAccount? getAccount(DebridProvider provider) {
    try {
      return accounts.value.firstWhere((a) => a.provider == provider);
    } catch (_) {
      return null;
    }
  }

  Future<bool> authenticateRealDebrid(String apiToken) async {
    isLoading.value = true;
    try {
      final response = await http.get(
        Uri.parse('https://api.real-debrid.com/rest/1.0/user'),
        headers: {'Authorization': 'Bearer $apiToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final username = data['username']?.toString();
        final email = data['email']?.toString();
        final expiration = data['expiration'] != null
            ? DateTime.tryParse(data['expiration'].toString())
            : null;
        final type = data['type']?.toString();
        final isPremium = type == 'premium';

        final account = DebridAccount(
          provider: DebridProvider.realDebrid,
          apiKey: apiToken,
          username: username,
          email: email,
          expirationDate: expiration,
          isPremium: isPremium,
        );

        final updated = accounts.value.where((a) => a.provider != DebridProvider.realDebrid).toList();
        updated.add(account);
        accounts.value = updated;
        await _persist();
        isLoading.value = false;
        return true;
      }
    } catch (e) {
      debugPrint('Real-Debrid auth error: $e');
    }
    isLoading.value = false;
    return false;
  }

  Future<bool> authenticateTorbox(String apiToken) async {
    isLoading.value = true;
    try {
      final response = await http.get(
        Uri.parse('https://api.torbox.app/v1/api/user/me'),
        headers: {'Authorization': 'Bearer $apiToken'},
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>?;
        final email = data?['email']?.toString();
        final plan = data?['plan'] as int? ?? 0;

        final account = DebridAccount(
          provider: DebridProvider.torbox,
          apiKey: apiToken,
          username: email?.split('@').first,
          email: email,
          isPremium: plan > 0,
        );

        final updated = accounts.value.where((a) => a.provider != DebridProvider.torbox).toList();
        updated.add(account);
        accounts.value = updated;
        await _persist();
        isLoading.value = false;
        return true;
      }
    } catch (e) {
      debugPrint('Torbox auth error: $e');
    }
    isLoading.value = false;
    return false;
  }

  Future<void> removeAccount(DebridProvider provider) async {
    accounts.value = accounts.value.where((a) => a.provider != provider).toList();
    await _persist();
  }
}

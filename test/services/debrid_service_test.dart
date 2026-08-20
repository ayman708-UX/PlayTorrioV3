import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/models/debrid/debrid_account.dart';
import 'package:playtorrio/services/debrid/debrid_service.dart';

void main() {
  group('DebridService', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      DebridService.instance.accounts.value = [];
      await DebridService.instance.initialize();
    });

    test('starts with empty accounts', () {
      expect(DebridService.instance.accounts.value, isEmpty);
      expect(DebridService.instance.isConfigured(DebridProvider.realDebrid), isFalse);
    });

    test('removeAccount removes configured provider', () async {
      DebridService.instance.accounts.value = [
        const DebridAccount(
          provider: DebridProvider.realDebrid,
          apiKey: 'test-token',
          username: 'tester',
        ),
      ];

      expect(DebridService.instance.isConfigured(DebridProvider.realDebrid), isTrue);
      await DebridService.instance.removeAccount(DebridProvider.realDebrid);
      expect(DebridService.instance.isConfigured(DebridProvider.realDebrid), isFalse);
    });
  });
}

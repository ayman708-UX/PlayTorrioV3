import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/iptv/iptv_epg_settings.dart';

void main() {
  group('IptvEpgSettings', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await IptvEpgSettings.initialize();
    });

    test('home TV guide is hidden by default', () {
      expect(IptvEpgSettings.showHomeTvGuide.value, false);
    });

    test('persists show home TV guide toggle', () async {
      await IptvEpgSettings.setShowHomeTvGuide(true);
      expect(IptvEpgSettings.showHomeTvGuide.value, true);

      await IptvEpgSettings.initialize();
      expect(IptvEpgSettings.showHomeTvGuide.value, true);
    });
  });
}

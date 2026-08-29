import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../models/subtitle/subtitle_model.dart';
import '../subtitle_provider.dart';
import '../subtitlecat_service.dart';

class SubtitleCatProvider extends SubtitleProvider {
  @override
  String get name => 'SubtitleCat';

  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  @override
  Future<List<SubtitleVariant>> search(
    String movieName, {
    String? imdbId,
    int? season,
    int? episode,
    int? year,
  }) async {
    final List<SubtitleVariant> results = [];

    try {
      final entries = await SubtitleCatService.instance.searchAndExtract(
        title: movieName,
        year: year,
        season: season,
        episode: episode,
      );

      for (final entry in entries) {
        final isTr = entry.isTranslated;
        final base = entry.baseName.isNotEmpty ? entry.baseName : movieName;
        final tag = isTr ? '${entry.label} (Auto Translated)' : entry.label;
        final title = '$base - $tag';

        results.add(
          SubtitleVariant(
            providerName: name,
            language: entry.label,
            title: title,
            downloadUrl: entry.url,
            format: 'srt',
            extraData: {
              'isTranslate': isTr,
              'origUrl': entry.origUrl,
              'targetLang': entry.code,
              'langCode': entry.code,
            },
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[SubtitleCatProvider] search error: $e');
    }

    return results;
  }

  @override
  Future<String?> download(SubtitleVariant variant) async {
    try {
      final dir = await getTemporaryDirectory();
      final isTr = variant.extraData['isTranslate'] == true;

      if (isTr) {
        final origUrl = (variant.extraData['origUrl'] as String?) ?? variant.downloadUrl;
        final targetLang = (variant.extraData['targetLang'] as String?) ?? 'en';

        final srtText = await SubtitleCatService.instance.translateSrt(
          origUrl: origUrl,
          targetLang: targetLang,
        );

        final outPath = '${dir.path}/subtitlecat_tr_${DateTime.now().millisecondsSinceEpoch}.srt';
        final file = File(outPath);
        await file.writeAsString(srtText, encoding: utf8, flush: true);
        return outPath;
      } else {
        final req = await _httpClient.getUrl(Uri.parse(variant.downloadUrl));
        req.headers.set(
          'User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
        );
        req.headers.set('Accept', '*/*');
        final res = await req.close();
        if (res.statusCode != 200) return null;

        final bytes = await res.fold<List<int>>([], (p, e) => p..addAll(e));
        final outPath = '${dir.path}/subtitlecat_${DateTime.now().millisecondsSinceEpoch}.srt';
        final file = File(outPath);
        await file.writeAsBytes(bytes, flush: true);
        return outPath;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[SubtitleCatProvider] download error: $e');
      return null;
    }
  }
}

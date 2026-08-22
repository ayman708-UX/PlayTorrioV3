import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

class SubtitleExtractor {
  /// Downloads a file (ZIP, SRT, or VTT) and extracts the subtitle if necessary.
  /// Returns the absolute path to the local .srt or .vtt file.
  static Future<String?> downloadAndExtract(
    String url, {
    Map<String, String>? headers,
    required String providerName,
  }) async {
    try {
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode != 200) return null;

      final bytes = response.bodyBytes;
      
      // Determine if it's a zip file based on magic bytes (PK\\x03\\x04)
      final isZip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04;

      final tempDir = await getTemporaryDirectory();
      final targetDir = Directory('${tempDir.path}/subtitles/$providerName');
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final fileName = '${DateTime.now().millisecondsSinceEpoch}';

      if (isZip) {
        final archive = ZipDecoder().decodeBytes(bytes);
        // Find the first .srt or .vtt file in the archive
        for (final file in archive) {
          if (file.isFile) {
            final name = file.name.toLowerCase();
            if (name.endsWith('.srt') || name.endsWith('.vtt')) {
              final content = file.content as List<int>;
              final ext = name.endsWith('.srt') ? '.srt' : '.vtt';
              final savePath = '${targetDir.path}/$fileName$ext';
              final localFile = File(savePath);
              await localFile.writeAsBytes(content);
              return savePath;
            }
          }
        }
      } else {
        // Assume direct SRT/VTT if not zip
        final ext = url.toLowerCase().endsWith('.vtt') ? '.vtt' : '.srt';
        final savePath = '${targetDir.path}/$fileName$ext';
        final localFile = File(savePath);
        await localFile.writeAsBytes(bytes);
        return savePath;
      }
    } catch (e) {
      print('Subtitle extraction error ($providerName): $e');
    }
    return null;
  }
}

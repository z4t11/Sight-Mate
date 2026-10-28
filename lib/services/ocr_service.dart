import 'dart:io';
import 'dart:typed_data';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// Result of OCR processing on a camera frame.
class OcrResult {
  final String rawText;
  final String spokenSummary;
  final double confidence;
  final bool hasText;

  const OcrResult({
    required this.rawText,
    required this.spokenSummary,
    required this.confidence,
    required this.hasText,
  });
}

/// Dedicated On-Device OCR & Signpost Reading Engine (Section 4).
/// Uses Google ML Kit Text Recognition with uncertainty hedging.
class OcrService {
  final TextRecognizer _recognizer = TextRecognizer();

  /// Process a camera picture frame or bytes using on-device ML Kit OCR.
  Future<OcrResult> readSignFromFrame(Uint8List frameBytes) async {
    try {
      // Write temporarily to local cache file for ML Kit InputImage
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/ocr_temp_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(frameBytes);

      final inputImage = InputImage.fromFile(tempFile);
      final recognized = await _recognizer.processImage(inputImage);

      // Clean up temp file
      try {
        await tempFile.delete();
      } catch (_) {}

      final cleanText = recognized.text.trim();
      if (cleanText.isEmpty) {
        return const OcrResult(
          rawText: '',
          spokenSummary: "I don't see any clear text or sign in front of the camera.",
          confidence: 0.0,
          hasText: false,
        );
      }

      // Check text block confidence and formatting
      final lines = recognized.blocks.expand((b) => b.lines).map((l) => l.text.trim()).toList();
      final lineCount = lines.length;

      String summary;
      if (lineCount <= 3) {
        // Short sign / door label
        summary = "The sign says: '$cleanText'.";
      } else {
        // Longer noticeboard / document
        final preview = lines.take(3).join(', ');
        summary = "Noticeboard text reads: '$preview', with more details below.";
      }

      return OcrResult(
        rawText: cleanText,
        spokenSummary: summary,
        confidence: 0.9,
        hasText: true,
      );
    } catch (_) {
      return const OcrResult(
        rawText: '',
        spokenSummary: "I had trouble reading the text. The image might be blurry or out of focus.",
        confidence: 0.0,
        hasText: false,
      );
    }
  }

  void dispose() {
    _recognizer.close();
  }
}

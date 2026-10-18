import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/scanner/scanner_page.dart';

void main() {
  group('normalizeWayMarkQrCode', () {
    test('trims surrounding whitespace and preserves the code', () {
      expect(normalizeWayMarkQrCode('  WM-A01  '), 'WM-A01');
    });

    test('rejects an empty value', () {
      expect(normalizeWayMarkQrCode('  '), isNull);
    });

    test('rejects codes longer than the API model limit', () {
      expect(normalizeWayMarkQrCode('W' * 101), isNull);
    });

    test('rejects control characters', () {
      expect(normalizeWayMarkQrCode('WM-A\n01'), isNull);
    });

    test('accepts the API model maximum length', () {
      final code = 'W' * 100;
      expect(normalizeWayMarkQrCode(code), code);
    });
  });
}

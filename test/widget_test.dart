import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_music/core/utils/formatters.dart';

void main() {
  group('Fmt.duration', () {
    test('formats minutes:seconds', () {
      expect(Fmt.duration(const Duration(seconds: 215)), '3:35');
    });
    test('formats hours:minutes:seconds', () {
      expect(Fmt.duration(const Duration(seconds: 3725)), '1:02:05');
    });
  });

  group('Fmt.compact', () {
    test('millions', () => expect(Fmt.compact(12300000), '12.3M'));
    test('thousands', () => expect(Fmt.compact(4200), '4.2K'));
  });
}

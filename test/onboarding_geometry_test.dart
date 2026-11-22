import 'package:flutter_test/flutter_test.dart';

/// The first-run overlay positions cards with a window-relative upper bound.
/// `num.clamp` throws when the lower bound exceeds the upper bound, which used
/// to crash the tour on a short window. This reproduces the arithmetic.
double clampTop(double value, double extent, double minimum, double reserve) {
  final upper = extent - reserve;
  final lower = upper < minimum ? upper : minimum;
  return value.clamp(lower, upper);
}

void main() {
  test('short windows produce a valid range instead of throwing', () {
    for (final height in <double>[120, 200, 250, 300, 360, 380, 480, 720, 1440]) {
      for (final reserve in <double>[220, 300]) {
        for (final minimum in <double>[76, 80]) {
          expect(
            () => clampTop(height - 270, height, minimum, reserve),
            returnsNormally,
            reason: 'height=$height reserve=$reserve minimum=$minimum',
          );
        }
      }
    }
  });

  test('the result never exceeds the window', () {
    for (final height in <double>[120, 250, 380, 720, 1440]) {
      final top = clampTop(height - 270, height, 80, 220);
      expect(top, lessThanOrEqualTo(height));
    }
  });

  test('a tall window keeps the intended 80px minimum', () {
    expect(clampTop(-1000, 1000, 80, 220), 80);
  });

  test('the horizontal fallback never inverts either', () {
    double clampLeft(double width, double maxWidth) {
      final upper = width - maxWidth - 20;
      final lower = upper < 20.0 ? upper : 20.0;
      return (width - maxWidth - 32).clamp(lower, upper);
    }

    for (final width in <double>[200, 320, 480, 800, 1600]) {
      expect(() => clampLeft(width, 440), returnsNormally, reason: 'width=$width');
      expect(() => clampLeft(width, width - 32), returnsNormally);
    }
  });
}

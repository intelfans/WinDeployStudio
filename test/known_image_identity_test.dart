import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/mirror/models/mirror_models.dart';

void main() {
  const sha = '6ba9d0c4907d6d34ef3a3ae3736fdb5ca8470c027f04e0fb3ab578ea03666aac';
  const md5 = 'd41d8cd98f00b204e9800998ecf8427e';

  KnownImage image() => KnownImage.fromJson(<String, dynamic>{
    'id': 'test-image',
    'name': 'Test Image',
    'sha256': sha,
    'md5': md5,
  });

  test('a matching SHA-256 identifies the image', () {
    expect(image().matches(sha256: sha, md5: md5), isTrue);
    expect(image().matchesSha256(sha.toUpperCase()), isTrue);
  });

  test('a matching MD5 alone no longer identifies the image', () {
    // Same MD5, different bytes: this is the collision scenario.
    const forgedSha =
        '0000000000000000000000000000000000000000000000000000000000000000';
    expect(image().matches(sha256: forgedSha, md5: md5), isFalse,
        reason: 'MD5 must not decide identity on its own');
  });

  test('an empty or malformed digest is refused', () {
    expect(image().matchesSha256(''), isFalse);
    expect(image().matchesSha256('deadbeef'), isFalse);
    expect(image().matchesSha256(sha.substring(0, 63)), isFalse);
  });

  test('a catalog entry with no SHA-256 never matches', () {
    final noSha = KnownImage.fromJson(<String, dynamic>{
      'id': 'md5-only',
      'name': 'MD5 Only',
      'sha256': '',
      'md5': md5,
    });
    expect(noSha.matches(sha256: sha, md5: md5), isFalse);
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/wim_info_service.dart';

void main() {
  test('parses Tiny10-style ESD metadata from the native helper', () {
    const xml = '''
<IMAGE INDEX="1">
  <TOTALBYTES>13348635472</TOTALBYTES>
  <WINDOWS>
    <ARCH>9</ARCH>
    <EDITIONID>EnterpriseS</EDITIONID>
    <INSTALLATIONTYPE>Client</INSTALLATIONTYPE>
    <LANGUAGES>
      <LANGUAGE>en-US</LANGUAGE>
    </LANGUAGES>
    <VERSION>
      <MAJOR>10</MAJOR>
      <MINOR>0</MINOR>
      <BUILD>19044</BUILD>
      <SPBUILD>3324</SPBUILD>
    </VERSION>
  </WINDOWS>
  <NAME>Windows 10 Enterprise LTSC 2021</NAME>
  <DESCRIPTION>Windows 10 Enterprise LTSC 2021</DESCRIPTION>
</IMAGE>
''';

    final images = WimInfoService.parseHelperOutput(
      'IMAGE|1|${base64Encode(utf8.encode(xml))}',
    );

    expect(images, hasLength(1));
    expect(images.single.index, 1);
    expect(images.single.name, 'Windows 10 Enterprise LTSC 2021');
    expect(images.single.architecture, 'x64');
    expect(images.single.edition, 'EnterpriseS');
    expect(images.single.installationType, 'Client');
    expect(images.single.language, 'en-US');
    expect(images.single.version, '10.0.19044.3324');
    expect(
      images.single.toMap()['description'],
      'Windows 10 Enterprise LTSC 2021',
    );
  });
}

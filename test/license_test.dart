import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('GPLv3 and the original sky-data license are bundled', () async {
    final license = await rootBundle.loadString('LICENSE');
    expect(license, contains('GNU GENERAL PUBLIC LICENSE'));
    expect(license, contains('Version 3, 29 June 2007'));
    final sky = await rootBundle.loadString('assets/sky/LICENSE.txt');
    expect(sky, contains('Copyright (c) 2015, Olaf Frohn'));
    expect(sky, contains('Redistribution and use in source and binary forms'));
  });
}

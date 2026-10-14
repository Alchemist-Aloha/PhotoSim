import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'D3-Celestial sky data',
    ], await rootBundle.loadString('assets/sky/LICENSE.txt'));
  });
  runApp(const PhotoSimApp());
}

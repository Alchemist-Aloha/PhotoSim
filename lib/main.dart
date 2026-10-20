import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'data/app_session.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['PhotoSim'],
      'Copyright (C) 2026 PhotoSim contributors\nLicensed under GPL-3.0-only.\n\n${await rootBundle.loadString('LICENSE')}',
    );
    yield LicenseEntryWithLineBreaks([
      'D3-Celestial sky data',
    ], await rootBundle.loadString('assets/sky/LICENSE.txt'));
    yield LicenseEntryWithLineBreaks([
      'NASA SVS / LRO Moon surface',
    ], await rootBundle.loadString('assets/moon/LICENSE.txt'));
    yield LicenseEntryWithLineBreaks([
      'Source Sans 3',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  SessionStore? store;
  AppSession? session;
  String? warning;
  try {
    store = SessionStore(
      File(
        '${(await getApplicationSupportDirectory()).path}/photosim/session-v1.json',
      ),
    );
    final restored = await store.restore();
    session = restored.session;
    warning = restored.warning;
  } on Object {
    store = null;
    warning = 'Session storage is unavailable. Your previous session is left unchanged, but this session cannot be recovered automatically. Check folder permissions and restart.';
  }
  runApp(
    PhotoSimApp(
      sessionStore: store,
      initialSession: session,
      sessionWarning: warning,
    ),
  );
}

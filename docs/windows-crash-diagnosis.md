# Windows 3D-entry crash, October 22, 2026

## Confirmed failure

Windows Error Reporting recorded PhotoSim 1.1.0.2 crashing in
`flutter_windows.dll` with exception `0xc0000005`, at module offset `0x3c1ca`.
The 12:38 crash occurred 24 seconds after process startup.

The crash minidump was decoded using the matching Flutter 3.47.7 release PDB.
The faulting instruction reads address `0x48` through a null pointer:

```text
flutter_windows!ui::AXNode::id
flutter_windows!flutter::AccessibilityBridge::CreateRemoveReparentedNodesUpdate+0xba
flutter_windows!flutter::AccessibilityBridge::CommitUpdates+0x40
flutter_windows!flutter::FlutterWindowsEngine::Run semantics callback
```

The engine assumes that an existing accessibility node has a parent. A rejected
tree update leaves a parentless node, and a later update dereferences it. The
ordinary release reproduction repeatedly logged:

```text
Failed to update ui::AXTree, error: N will not be in the tree and is not the new root
```

This locates the recorded crash in the native accessibility bridge. There is no
GPU upload or terrain-decoding frame on the faulting stack. Terrain and imagery
loading overlap the UI updates, so partial scene loading is the visible symptom.

Local evidence is retained under the ignored `build/diagnostics/` folder:
`original-crash.dmp`, `original-stack.log`, `repro-stderr.log` and the original
session snapshot. Crash dumps are intentionally excluded from source control.

## Build repair

Flutter's merged [PR #193372](https://github.com/flutter/flutter/pull/193372)
prevents orphaned `OverlayPortal` semantics nodes from being sent to the engine
and keeps traversal parents and child lists synchronized. Material sliders use
these overlays. The associated [Windows issue #190357](https://github.com/flutter/flutter/issues/190357)
describes the invalid accessibility tree; [issue #175041](https://github.com/flutter/flutter/issues/175041)
tracks the same native crash function.

Windows release builds backport the upstream framework change through
`tool/flutter_windows.py`. The SDK's original bytes are restored after the
command, including build failures. Accessibility and Impeller/GPU rendering stay
enabled. The backport is vendored with its upstream BSD license and attribution
in `tool/patches/`. It can be removed once the pinned Flutter stable SDK includes
the upstream fix.

## Regression coverage

`integration_test/windows_scene_regression_test.dart` runs the full app using
the affected Yosemite camera location and real terrain/imagery. It explicitly
activates the native accessibility bridge in the debug runner; Dart widget-test
semantics alone does not create that bridge. The test loads all nine terrain
and imagery tiles, animates inspector slider sections, changes inspector
visibility, revisits 3D from the map, enters/exits fullscreen and checks that
rendered frames continue advancing. It writes a screenshot and loading progress
under `build/validation/windows/real-scene/`.

The original crash is intermittent: a passing unpatched run is possible. Native
integration coverage and a release-startup comparison therefore supplement,
rather than replace, the recorded crash stack. Full screen-reader interaction
and other graphics drivers remain outside this local validation.

## Local repair results

The patched full-app native regression passed with all nine terrain and imagery
tiles loaded and rendered frames advancing after the workspace/fullscreen
transitions. The resulting screenshot is
`build/validation/windows/real-scene/loaded.png`.

The PhotoSim 1.1.1.3 release survived a 90-second launch using the original saved
3D session. Its native stderr contained zero accessibility-tree or fatal errors,
where the original release repeatedly rejected AXTree updates. Native stderr and
the survival check are retained in `build/diagnostics/fixed-release-stderr.log`
and `fixed-release-smoke.log`.

The rebuilt EXE installer passed silent install, SHA-256 verification of all 56
application-bundle files, and uninstall. Flutter static analysis reported no
issues, all 247 Dart tests passed with the patched framework, and all 15 Python
packaging/backport tests passed. The original SDK source and the user's saved
session match their pre-test SHA-256 hashes. The vendored patch also applies
cleanly to the CI-pinned Flutter 3.47.6
source; a hosted GitHub Actions build has not been triggered in this session.

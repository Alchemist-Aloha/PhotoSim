# Flutter Windows accessibility backport

`flutter-193372-semantics.patch` contains the runtime-only diff from Flutter PR
[#193372](https://github.com/flutter/flutter/pull/193372), merged on October 19,
2026 as `b304cf1`. The original Flutter code and patch are BSD-3-Clause licensed;
the upstream license is retained in `LICENSE.flutter`.

Flutter 3.47.6 and 3.47.7 can send orphaned `OverlayPortal` semantics nodes from
Material sliders. A rejected accessibility update can later cause a native
null-parent dereference in `AccessibilityBridge::CreateRemoveReparentedNodesUpdate`.
PhotoSim's Windows crash dump resolves to this exact function at DLL offset
`0x3c1ca`, with a null `AXNode` parent and an attempted read at address `0x48`.

`tool/flutter_windows.py` applies the upstream framework patch only while a
Flutter command runs, then restores the original SDK bytes in `finally`. It
skips SDKs that already contain the fix and refuses to patch an incompatible
source tree. Run commands serially against a shared SDK while the backport is
active. No accessibility APIs or GPU features are disabled.

The Windows release builder uses the same context for its build, so local and
GitHub Actions packages contain the fix. Remove this workaround after adopting
a pinned Flutter stable SDK that includes the upstream change.

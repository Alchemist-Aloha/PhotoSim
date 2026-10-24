import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'workspace_feedback.dart';

/// The PNG shown here is the same byte buffer passed to the native saver.
class ExportPanel extends StatelessWidget {
  const ExportPanel({
    super.key,
    required this.bytes,
    required this.prompt,
    required this.busy,
    required this.ready,
    required this.stale,
    required this.onRender,
    required this.onSave,
    this.error,
    this.width,
    this.height,
  });

  final Uint8List? bytes;
  final TextEditingController prompt;
  final bool busy, ready, stale;
  final VoidCallback onRender, onSave;
  final String? error;
  final int? width, height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bytes == null)
          SizedBox(
            height: 220,
            child: Center(
              child: Text(
                busy ? 'Rendering high-quality preview…' : 'Render a preview to prepare your PNG and enhancement prompt.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 480),
            child: Image.memory(
              bytes!,
              key: const ValueKey('export-image'),
              fit: BoxFit.contain,
              semanticLabel: 'High-quality PNG export preview',
              gaplessPlayback: true,
            ),
          ),
          const SizedBox(height: 12),
          Text('$width × $height px · PNG · Source credits included'),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            onPressed: bytes == null || busy || stale ? null : onSave,
            icon: const Icon(Icons.save_alt),
            label: const Text('Save PNG'),
          ),
        ),
      ],
    );
    final editor = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('AI enhancement prompt', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Attach the saved PNG and paste this prompt into your image model. '
          'Nothing is uploaded automatically. Prompt edits are temporary; copy them before leaving.',
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('enhancement-prompt'),
          controller: prompt,
          enabled: bytes != null && !busy,
          minLines: 10,
          maxLines: 18,
          decoration: const InputDecoration(
            labelText: 'Prompt and capture metadata',
            alignLabelWithHint: true,
            hintText: 'Location, time, optics, lighting and source metadata appear after rendering.',
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Includes precise GPS coordinates and shooting time. Review before sharing. '
          'AI-added details are not reliable scouting evidence.',
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: bytes == null || busy
                ? null
                : () async {
                    try {
                      await Clipboard.setData(ClipboardData(text: prompt.text));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..removeWorkspaceFeedback()
                        ..showWorkspaceFeedback(
                          const SnackBar(content: Text('Prompt copied.')),
                        );
                    } catch (failure) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..removeWorkspaceFeedback()
                        ..showWorkspaceFeedback(
                          SnackBar(
                            content: Text(
                              'Could not copy prompt: $failure. Select and copy the text manually.',
                            ),
                          ),
                        );
                    }
                  },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy prompt'),
          ),
        ),
      ],
    );
    return Material(
      color: theme.colorScheme.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Export photograph', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              'Re-rendered at twice the screen pixel density, up to 6144 px / 20 MP. '
              'No composition guides or controls. Existing files are never overwritten.',
            ),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: !ready || busy ? null : onRender,
                icon: const Icon(Icons.high_quality_outlined),
                label: Text(
                  bytes == null
                      ? 'Render high-quality preview'
                      : 'Re-render preview & reset prompt',
                ),
              ),
            ),
            if (busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(semanticsLabel: 'Preparing export'),
            ],
            if (!ready && !busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Waiting for terrain and imagery. If loading fails, return to 3D Preview to retry.',
                ),
              ),
            if (stale)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'The scene has changed. Re-render to update the image and metadata.',
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, bounds) => bounds.maxWidth >= 900
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: preview),
                        const SizedBox(width: 32),
                        Expanded(flex: 2, child: editor),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [preview, const SizedBox(height: 32), editor],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

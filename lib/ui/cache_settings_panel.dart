import 'package:flutter/material.dart';

import '../data/raster_cache.dart';

class CacheSettingsPanel extends StatefulWidget {
  const CacheSettingsPanel({super.key, this.cache, this.error});
  final RasterCache? cache;
  final String? error;

  @override
  State<CacheSettingsPanel> createState() => _CacheSettingsPanelState();
}

class _CacheSettingsPanelState extends State<CacheSettingsPanel> {
  final form = GlobalKey<FormState>();
  late final limit = TextEditingController(
    text: '${widget.cache?.limitMiB ?? RasterCache.defaultLimitMiB}',
  );
  bool busy = false;
  String? result;

  @override
  void didUpdateWidget(covariant CacheSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cache != widget.cache) {
      limit.text = '${widget.cache?.limitMiB ?? RasterCache.defaultLimitMiB}';
    }
  }

  Future<void> apply() async {
    final cache = widget.cache;
    if (busy || cache == null || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      result = null;
    });
    try {
      await cache.setLimitMiB(int.parse(limit.text.trim()));
      if (mounted) setState(() => result = 'Cache limit saved.');
    } on Exception {
      if (mounted) {
        setState(
          () => result =
              cache.warning ??
              'Could not save cache settings. Check disk permissions.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Terrain + imagery cache: ${widget.cache?.limitMiB ?? RasterCache.defaultLimitMiB} MiB',
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const PageStorageKey('cache-limit'),
          controller: limit,
          enabled: widget.cache != null && !busy,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Total disk cache limit (MiB)',
          ),
          validator: (text) {
            final value = int.tryParse(text?.trim() ?? '');
            return value == null || value < 0 || value > RasterCache.maxLimitMiB
                ? 'Enter 0–${RasterCache.maxLimitMiB} whole MiB'
                : null;
          },
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: widget.cache == null || busy ? null : apply,
          child: Text(busy ? 'Applying…' : 'Apply cache limit'),
        ),
        const SizedBox(height: 8),
        const Text(
          'One shared disk limit. Oldest-used terrain and imagery are removed when full. Lowering it trims immediately; 0 disables disk caching. Loaded meshes and textures stay visible.',
        ),
        if (result != null) Text(result!, semanticsLabel: result),
        if (widget.cache?.warning != null) Text(widget.cache!.warning!),
        if (widget.cache == null)
          Text(widget.error ?? 'Loading cache settings…'),
      ],
    ),
  );
}

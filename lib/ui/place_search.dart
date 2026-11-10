import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/place_search.dart';

class PlaceSearch extends StatefulWidget {
  const PlaceSearch({super.key, required this.onSelected, this.httpClient});

  final ValueChanged<PlaceSearchResult> onSelected;
  final http.Client? httpClient;

  @override
  State<PlaceSearch> createState() => _PlaceSearchState();
}

class _PlaceSearchState extends State<PlaceSearch> {
  final query = TextEditingController();
  final menu = MenuController();
  LocalHistoryEntry? menuHistory;
  late final client = widget.httpClient ?? http.Client();
  late final repository = PlaceSearchRepository(client);
  List<PlaceSearchResult> results = [];
  String? error;
  bool loading = false;

  @override
  void dispose() {
    menuHistory?.remove();
    query.dispose();
    if (widget.httpClient == null) client.close();
    super.dispose();
  }

  Future<void> search() async {
    if (loading) return;
    menu.close();
    if (query.text.trim().isEmpty) {
      setState(() => error = 'Enter a town or place to search.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      loading = true;
      error = null;
      results = [];
    });
    try {
      final found = await repository.search(query.text);
      if (!mounted) return;
      setState(() {
        results = found;
        if (found.isEmpty) {
          error = 'No places found. Try a nearby town or add a country.';
        }
      });
      if (found.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && results.isNotEmpty) menu.open();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error =
              'Place search unavailable. Check your connection and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => MenuAnchor(
      controller: menu,
      onOpen: () {
        menuHistory = LocalHistoryEntry(onRemove: menu.close);
        ModalRoute.of(context)?.addLocalHistoryEntry(menuHistory!);
      },
      onClose: () {
        final history = menuHistory;
        menuHistory = null;
        history?.remove();
      },
      consumeOutsideTap: true,
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
        maximumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 280)),
      ),
      menuChildren: [
        for (final result in results)
          MenuItemButton(
            autofocus: result == results.first,
            onPressed: () {
              query.text = result.name;
              widget.onSelected(result);
            },
            child: SizedBox(
              width: (constraints.maxWidth - 32).clamp(0, double.infinity),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(result.name),
                    if (result.description.isNotEmpty)
                      Text(
                        result.description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: query,
                  readOnly: loading,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => search(),
                  onChanged: (_) {
                    menu.close();
                    setState(() {
                      results = [];
                      error = null;
                    });
                  },
                  decoration: const InputDecoration(
                    labelText: 'Town or place',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: loading ? null : search,
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Text('Search'),
              ),
            ],
          ),
          if (loading)
            const LinearProgressIndicator(semanticsLabel: 'Searching places'),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

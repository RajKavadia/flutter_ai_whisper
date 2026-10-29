import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

import 'panel_controller.dart';
import 'vm_client.dart';

/// DevTools panel for inspecting and mutating live app state.
class WhisperPanel extends StatefulWidget {
  const WhisperPanel({super.key});

  @override
  State<WhisperPanel> createState() => _WhisperPanelState();
}

class _WhisperPanelState extends State<WhisperPanel> {
  late final PanelController _controller;
  late final TextEditingController _searchController;
  late final TextEditingController _valueController;
  late final TextEditingController _runExpressionController;
  late final TextEditingController _runLibraryController;

  @override
  void initState() {
    super.initState();
    _controller = PanelController(DevToolsVmClient())
      ..addListener(_onControllerChanged);
    _searchController = TextEditingController();
    _valueController = TextEditingController();
    _runExpressionController = TextEditingController();
    _runLibraryController = TextEditingController();
    serviceManager.connectedState.addListener(_onConnectionChanged);
    _onConnectionChanged();
  }

  @override
  void dispose() {
    serviceManager.connectedState.removeListener(_onConnectionChanged);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _searchController.dispose();
    _valueController.dispose();
    _runExpressionController.dispose();
    _runLibraryController.dispose();
    super.dispose();
  }

  void _onConnectionChanged() {
    if (!_controller.isConnected) {
      _controller.reset();
      return;
    }
    if (_controller.mode == PanelMode.screen && _controller.census == null) {
      _controller.loadScreen();
    }
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.isConnected) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Open DevTools on a flutter run debug session.\n'
              'There is no VM Service connection.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          if (_controller.error != null)
            _banner(_controller.error!, isError: true),
          if (_controller.notice != null) _banner(_controller.notice!),
          if (_controller.logicNotice != null) _banner(_controller.logicNotice!),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: _controller.setSearch,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<PanelMode>(
              segments: const [
                ButtonSegment(value: PanelMode.screen, label: Text('Screen')),
                ButtonSegment(value: PanelMode.logic, label: Text('Logic')),
                ButtonSegment(value: PanelMode.run, label: Text('Run')),
              ],
              selected: {_controller.mode},
              onSelectionChanged: (selection) {
                _controller.setMode(selection.first);
              },
            ),
          ),
          Expanded(child: _body()),
          if (_controller.target != null) _fieldEditor(),
        ],
      ),
    );
  }

  Widget _header() {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Text(
              'flutter_ai_whisper',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _controller.appName ?? 'connected',
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_controller.busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _controller.busy ? null : _controller.refresh,
              child: const Text('Refresh'),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _controller.busy ? null : _reloadList,
              child: const Text('Reload list'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reloadList() async {
    switch (_controller.mode) {
      case PanelMode.screen:
        await _controller.loadScreen();
      case PanelMode.logic:
        await _controller.loadLogic();
      case PanelMode.run:
        break;
    }
  }

  Widget _banner(String text, {bool isError = false}) {
    return Material(
      color: isError
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }

  Widget _body() {
    switch (_controller.mode) {
      case PanelMode.screen:
        return _screenList();
      case PanelMode.logic:
        return _logicList();
      case PanelMode.run:
        return _runPane();
    }
  }

  Widget _screenList() {
    final rows = _controller.visibleScreenRows;
    if (_controller.census == null && !_controller.busy) {
      return const Center(
        child: Text('Tap Reload list to scan the current route.'),
      );
    }
    if (rows.isEmpty) {
      return Center(
        child: Text(
          _controller.census?.route.isNotEmpty == true
              ? 'No StatefulWidgets on route "${_controller.census!.route}".'
              : 'No matches.',
        ),
      );
    }
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final selected = _controller.selectedScreen?.finderKey == row.finderKey;
        return ListTile(
          selected: selected,
          title: Text(row.stateType),
          subtitle: Text('${row.widgetType} · ${row.preview}'),
          onTap: () => _controller.selectScreenRow(row),
        );
      },
    );
  }

  Widget _logicList() {
    if (_controller.logicRows.isEmpty && !_controller.busy) {
      return Center(
        child: Text(
          _controller.heapUnavailable
              ? 'Tap Reload list. Heap listing is unavailable on web.'
              : 'Tap Reload list to scan logic objects.',
        ),
      );
    }
    final rows = _controller.visibleLogicRows;
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final selected = _controller.selectedLogic?.name == row.name &&
            _controller.selectedLogic?.source == row.source;
        return ListTile(
          selected: selected,
          title: Text('${row.name} · ${row.type}'),
          subtitle: Text('${row.source} ${row.valuePreview ?? ''}'),
          onTap: () => _controller.selectLogicRow(row),
        );
      },
    );
  }

  Widget _runPane() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Runs one Dart expression in the app (debug only).',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _runExpressionController,
            decoration: const InputDecoration(
              labelText: 'Expression',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            onChanged: _controller.setRunExpression,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _runLibraryController,
            decoration: const InputDecoration(
              labelText: 'Library URI (optional)',
              border: OutlineInputBorder(),
            ),
            onChanged: _controller.setRunLibraryUri,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _controller.busy ? null : _controller.run,
            child: const Text('Run'),
          ),
          if (_controller.runResult != null) ...[
            const SizedBox(height: 12),
            Text('Result: ${_controller.runResult}'),
          ],
        ],
      ),
    );
  }

  Widget _fieldEditor() {
    final target = _controller.target!;
    final field = _controller.selectedField;
    return Material(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(target.title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: field?.name,
              decoration: const InputDecoration(
                labelText: 'Field',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _controller.fields
                  .map(
                    (f) => DropdownMenuItem(
                      value: f.name,
                      child: Text('${f.name} = ${f.value}'),
                    ),
                  )
                  .toList(),
              onChanged: (name) {
                if (name == null) return;
                for (final candidate in _controller.fields) {
                  if (candidate.name == name) {
                    _controller.selectField(candidate);
                    break;
                  }
                }
              },
            ),
            if (field?.readOnlyReason != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  field!.readOnlyReason!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _valueController,
              decoration: InputDecoration(
                labelText:
                    field?.editable == true ? 'New literal' : 'Read-only',
                hintText: '42, true, "text", null',
                border: const OutlineInputBorder(),
              ),
              enabled: field?.editable == true && !_controller.busy,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: field?.editable == true && !_controller.busy
                  ? () => _controller.assign(_valueController.text)
                  : null,
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
  }
}

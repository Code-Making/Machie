// =========================================
// UPDATED: lib/editor/plugins/refactor_editor/refactor_editor_widget.dart
// =========================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/dto/tab_hot_state_dto.dart';
import '../../../editor/editor_tab_models.dart';
import 'refactor_editor_hot_state.dart';
import 'refactor_editor_models.dart';
import 'refactor_state_notifier.dart';
import 'occurrence_list_item.dart';

class RefactorEditorWidget extends EditorWidget {
  @override
  final RefactorEditorTab tab;

  const RefactorEditorWidget({
    required GlobalKey<RefactorEditorWidgetState> key,
    required this.tab,
  }) : super(key: key, tab: tab);

  @override
  RefactorEditorWidgetState createState() => RefactorEditorWidgetState();
}

class RefactorEditorWidgetState extends EditorWidgetState<RefactorEditorWidget> {
  late final TextEditingController _findController;
  late final TextEditingController _replaceController;

  @override
  void init() {
    final notifier = ref.read(refactorStateProvider.notifier);
    notifier.setInitialState(widget.tab.initialState);

    _findController = TextEditingController(text: widget.tab.initialState.searchTerm);
    _replaceController = TextEditingController(text: widget.tab.initialState.replaceTerm);

    _findController.addListener(() => notifier.updateSearchTerm(_findController.text));
    _replaceController.addListener(() => notifier.updateReplaceTerm(_replaceController.text));
  }

  @override
  void dispose() {
    _findController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  @override
  void onFirstFrameReady() {
    if (!widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(refactorStateProvider);
    final notifier = ref.read(refactorStateProvider.notifier);
    final bool allSelected = state.occurrences.isNotEmpty && state.selectedOccurrences.length == state.occurrences.length;

    return Column(
      children: [
        _buildInputPanel(state, notifier),
        if (state.searchStatus == SearchStatus.searching)
          const LinearProgressIndicator(),
        Expanded(child: _buildResultsPanel(state, notifier, allSelected)),
        _buildActionPanel(state, notifier),
      ],
    );
  }

  Widget _buildInputPanel(RefactorSessionState state, RefactorStateNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _findController,
                  decoration: const InputDecoration(labelText: 'Find', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: state.searchStatus == SearchStatus.searching ? null : notifier.findOccurrences,
                child: const Text('Find All'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _replaceController,
            decoration: const InputDecoration(labelText: 'Replace', border: OutlineInputBorder()),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _OptionCheckbox(
                label: 'Use Regex',
                value: state.isRegex,
                onChanged: (val) => notifier.toggleIsRegex(val ?? false),
              ),
              _OptionCheckbox(
                label: 'Case Sensitive',
                value: state.isCaseSensitive,
                onChanged: (val) => notifier.toggleCaseSensitive(val ?? false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultsPanel(RefactorSessionState state, RefactorStateNotifier notifier, bool allSelected) {
    if (state.searchStatus == SearchStatus.idle) {
      return const Center(child: Text('Enter a search term and click "Find All"'));
    }
    if (state.searchStatus == SearchStatus.error) {
      return const Center(child: Text('An error occurred during search.', style: TextStyle(color: Colors.red)));
    }
    if (state.searchStatus == SearchStatus.complete && state.occurrences.isEmpty) {
      return Center(child: Text('No results found for "${state.searchTerm}"'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Text('${state.occurrences.length} results found.'),
              const Spacer(),
              const Text('Select All'),
              Checkbox(
                value: allSelected,
                tristate: !allSelected && state.selectedOccurrences.isNotEmpty,
                onChanged: (val) => notifier.toggleSelectAll(val ?? false),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: state.occurrences.length,
            itemBuilder: (context, index) {
              final occurrence = state.occurrences[index];
              final isSelected = state.selectedOccurrences.contains(occurrence);
              return OccurrenceListItem(
                occurrence: occurrence,
                isSelected: isSelected,
                onSelected: (_) => notifier.toggleOccurrenceSelection(occurrence),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActionPanel(RefactorSessionState state, RefactorStateNotifier notifier) {
    final canApply = state.selectedOccurrences.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).bottomAppBarTheme.color,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton(
            onPressed: canApply ? notifier.applyChanges : null,
            child: Text('Replace ${state.selectedOccurrences.length} selected'),
          ),
        ],
      ),
    );
  }

  @override
  Future<EditorContent> getContent() async {
    return EditorContentString('{}'); // State is managed by the hot cache, not file content.
  }

  @override
  Future<TabHotStateDto?> serializeHotState() async {
    final currentState = ref.read(refactorStateProvider);
    return RefactorEditorHotStateDto(
      searchTerm: currentState.searchTerm,
      replaceTerm: currentState.replaceTerm,
      isRegex: currentState.isRegex,
      isCaseSensitive: currentState.isCaseSensitive,
    );
  }

  // Other overrides remain empty for now
  @override
  void redo() {}
  @override
  void syncCommandContext() {}
  @override
  void undo() {}
  @override
  void onSaveSuccess(String newHash) {}
}

class _OptionCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool?> onChanged;

  const _OptionCheckbox({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(value: value, onChanged: onChanged),
        Text(label),
      ],
    );
  }
}
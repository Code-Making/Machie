import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/dto/tab_hot_state_dto.dart';
import '../../../editor/editor_tab_models.dart';
import 'refactor_editor_controller.dart';
import 'refactor_editor_hot_state.dart';
import 'refactor_editor_models.dart';
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

// It's now a ConsumerStatefulWidget's State
class RefactorEditorWidgetState extends EditorWidgetState<RefactorEditorWidget> {
  late final RefactorController _controller;
  late final TextEditingController _findController;
  late final TextEditingController _replaceController;

  @override
  void init() {
    // Create the controller, passing it the Riverpod ref and initial state
    _controller = RefactorController(ref, initialState: widget.tab.initialState);

    _findController = TextEditingController(text: _controller.searchTerm);
    _replaceController = TextEditingController(text: _controller.replaceTerm);

    // Listen to text field changes to update the controller's mutable state
    _findController.addListener(() => _controller.updateSearchTerm(_findController.text));
    _replaceController.addListener(() => _controller.updateReplaceTerm(_replaceController.text));
  }

  @override
  void dispose() {
    _findController.dispose();
    _replaceController.dispose();
    _controller.dispose(); // Dispose the controller
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
    // Use ListenableBuilder to rebuild when the controller notifies its listeners
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        final allSelected = _controller.occurrences.isNotEmpty && _controller.selectedOccurrences.length == _controller.occurrences.length;

        return Column(
          children: [
            _buildInputPanel(),
            if (_controller.searchStatus == SearchStatus.searching) const LinearProgressIndicator(),
            Expanded(child: _buildResultsPanel(allSelected)),
            _buildActionPanel(),
          ],
        );
      },
    );
  }

  // Builder methods now directly access the controller's state
  Widget _buildInputPanel() {
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
                  onSubmitted: (_) => _controller.findOccurrences(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _controller.searchStatus == SearchStatus.searching ? null : _controller.findOccurrences,
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
                value: _controller.isRegex,
                onChanged: (val) => _controller.toggleIsRegex(val ?? false),
              ),
              _OptionCheckbox(
                label: 'Case Sensitive',
                value: _controller.isCaseSensitive,
                onChanged: (val) => _controller.toggleCaseSensitive(val ?? false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultsPanel(bool allSelected) {
    if (_controller.searchStatus == SearchStatus.idle) {
      return const Center(child: Text('Enter a search term and click "Find All"'));
    }
    if (_controller.searchStatus == SearchStatus.error) {
      return const Center(child: Text('An error occurred during search.', style: TextStyle(color: Colors.red)));
    }
    if (_controller.searchStatus == SearchStatus.complete && _controller.occurrences.isEmpty) {
      return Center(child: Text('No results found for "${_controller.searchTerm}"'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Text('${_controller.occurrences.length} results found.'),
              const Spacer(),
              const Text('Select All'),
              Checkbox(
                value: allSelected,
                tristate: !allSelected && _controller.selectedOccurrences.isNotEmpty,
                onChanged: (val) => _controller.toggleSelectAll(val ?? false),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _controller.occurrences.length,
            itemBuilder: (context, index) {
              final occurrence = _controller.occurrences[index];
              final isSelected = _controller.selectedOccurrences.contains(occurrence);
              return OccurrenceListItem(
                occurrence: occurrence,
                isSelected: isSelected,
                onSelected: (_) => _controller.toggleOccurrenceSelection(occurrence),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActionPanel() {
    final canApply = _controller.selectedOccurrences.isNotEmpty;
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
            onPressed: canApply ? _controller.applyChanges : null,
            child: Text('Replace ${_controller.selectedOccurrences.length} selected'),
          ),
        ],
      ),
    );
  }
  
  // These methods now read from the controller to serialize state
  @override
  Future<EditorContent> getContent() async {
    return EditorContentString('{}');
  }

  @override
  Future<TabHotStateDto?> serializeHotState() async {
    return RefactorEditorHotStateDto(
      searchTerm: _controller.searchTerm,
      replaceTerm: _controller.replaceTerm,
      isRegex: _controller.isRegex,
      isCaseSensitive: _controller.isCaseSensitive,
    );
  }

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
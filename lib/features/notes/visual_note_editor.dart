import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../models/note_video_link.dart';
import 'video_note_frame_viewer_page.dart';

/// A visual document surface. Markdown is only the compatible storage/export
/// representation; video links and attachments are never edited as source text.
class VisualNoteEditor extends StatefulWidget {
  const VisualNoteEditor({
    super.key,
    required this.controller,
    this.editing = true,
    this.attachments = const {},
    this.onChanged,
    this.onLink,
    this.onTimestamp,
    this.onScreenshot,
    this.capturing = false,
  });

  final TextEditingController controller;
  final bool editing;
  final Map<String, String> attachments;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onLink;
  final VoidCallback? onTimestamp;
  final VoidCallback? onScreenshot;
  final bool capturing;

  /// The external selection tracks the active text block's caret in the stored
  /// document, so player actions insert between the correct pieces of text.
  static void insert(TextEditingController controller, String text) {
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : controller.text.length;
    final end = selection.isValid ? selection.end : start;
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  @override
  State<VisualNoteEditor> createState() => _VisualNoteEditorState();
}

class _NoteBlock {
  _NoteBlock.text(String text)
    : text = TextEditingController(text: text),
      focus = FocusNode(),
      source = '',
      label = '',
      target = null,
      image = false;

  _NoteBlock.media(this.source, this.label, this.target, this.image)
    : text = null,
      focus = null;

  final TextEditingController? text;
  final FocusNode? focus;
  final String source;
  final String label;
  final String? target;
  final bool image;
  String get serialized => text?.text ?? source;

  void dispose() {
    text?.dispose();
    focus?.dispose();
  }
}

class _VisualNoteEditorState extends State<VisualNoteEditor> {
  // Code spans/fences are consumed first, preserving literal examples. Other
  // Markdown remains untouched, including the old notes' escaped plain text.
  static final _tokens = RegExp(
    r'```[^]*?```|`[^`\n]*`|!\[([^\]\n]*)\]\(([^\s)]+)(?:\s+"[^"]*")?\)|\[([^\]\n]*)\]\((focubili://[^\s)]+)\)',
  );
  List<_NoteBlock> _blocks = [];
  final List<_NoteBlock> _retired = [];
  String _loadedText = '';
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
    widget.controller.addListener(_externalChanged);
  }

  @override
  void didUpdateWidget(VisualNoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_externalChanged);
      widget.controller.addListener(_externalChanged);
      _load();
    }
  }

  void _load() {
    _retired.addAll(_blocks);
    _blocks = [];
    _loadedText = widget.controller.text;
    var offset = 0;
    for (final match in _tokens.allMatches(_loadedText)) {
      final image = match.group(1) != null;
      final target = image ? match.group(2) : match.group(4);
      if (target == null || (!image && NoteVideoLink.parse(target) == null)) {
        continue;
      }
      _addText(_loadedText.substring(offset, match.start));
      _blocks.add(
        _NoteBlock.media(
          match.group(0)!,
          (image ? match.group(1) : match.group(3))!,
          target,
          image,
        ),
      );
      offset = match.end;
    }
    _addText(_loadedText.substring(offset));
    // Keep old controllers alive until their TextFields have unmounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final block in _retired) {
        block.dispose();
      }
      _retired.clear();
    });
  }

  void _addText(String text) {
    final block = _NoteBlock.text(text);
    block.text!.addListener(() => _textChanged(block));
    _blocks.add(block);
  }

  void _textChanged(_NoteBlock block) {
    if (_syncing || !_blocks.contains(block)) return;
    final value = block.text!.value;
    final body = _blocks.map((b) => b.serialized).join();
    final changed = body != _loadedText;
    var offset = 0;
    for (final b in _blocks) {
      if (identical(b, block)) break;
      offset += b.serialized.length;
    }
    _syncing = true;
    _loadedText = body;
    widget.controller.value = TextEditingValue(
      text: body,
      selection: value.selection.isValid
          ? TextSelection(
              baseOffset: offset + value.selection.baseOffset,
              extentOffset: offset + value.selection.extentOffset,
            )
          : TextSelection.collapsed(offset: offset + value.text.length),
    );
    _syncing = false;
    if (changed) widget.onChanged?.call(body);
  }

  void _externalChanged() {
    if (_syncing || widget.controller.text == _loadedText) return;
    setState(_load);
    final caret = widget.controller.selection.extentOffset;
    if (widget.editing && caret >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.editing) return;
        var offset = 0;
        for (final block in _blocks) {
          final end = offset + block.serialized.length;
          if (block.text != null && caret >= offset && caret <= end) {
            block.focus!.requestFocus();
            block.text!.selection = TextSelection.collapsed(
              offset: caret - offset,
            );
            break;
          }
          offset = end;
        }
      });
    }
  }

  void _remove(_NoteBlock block) {
    var start = 0;
    for (final b in _blocks) {
      if (identical(b, block)) break;
      start += b.serialized.length;
    }
    widget.controller.value = TextEditingValue(
      text: _loadedText.replaceRange(start, start + block.source.length, ''),
      selection: TextSelection.collapsed(offset: start),
    );
    widget.onChanged?.call(widget.controller.text);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_externalChanged);
    for (final block in [..._blocks, ..._retired]) {
      block.dispose();
    }
    _retired.clear();
    super.dispose();
  }

  Widget _image(_NoteBlock block) {
    final path = widget.attachments[block.target];
    if (path == null) return const Text('截图文件不可用');
    return Tooltip(
      message: '点击放大',
      child: InkWell(
        key: ValueKey('open-note-image-${block.target}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          FocusScope.of(context).unfocus();
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => VideoNoteFrameViewerPage(framePath: path),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, error, stack) => const Padding(
              padding: EdgeInsets.all(16),
              child: Text('截图文件不可用'),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var textIndex = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.editing)
          Wrap(
            children: [
              if (widget.onTimestamp != null)
                TextButton.icon(
                  onPressed: widget.onTimestamp,
                  icon: const Icon(Icons.schedule),
                  label: const Text('时间戳'),
                ),
              if (widget.onScreenshot != null)
                TextButton.icon(
                  onPressed: widget.capturing ? null : widget.onScreenshot,
                  icon: const Icon(Icons.screenshot_monitor),
                  label: Text(widget.capturing ? '截图中' : '截图'),
                ),
            ],
          ),
        for (final block in _blocks)
          if (block.text != null) ...[
            if (widget.editing)
              TextField(
                key: textIndex++ == 0
                    ? const Key('visual-note-body')
                    : ObjectKey(block),
                controller: block.text,
                focusNode: block.focus,
                enabled: true,
                minLines: _blocks.length == 1 ? 4 : 1,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: _blocks.length == 1 ? '记录学习内容…' : '继续写笔记…',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              )
            else if (block.text!.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: MarkdownBody(
                  data: block.text!.text,
                  selectable: true,
                  onTapLink: (text, href, title) {
                    if (href != null) widget.onLink?.call(href);
                  },
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (block.image)
                        const Expanded(child: Text('视频截图 · 点击放大'))
                      else
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ActionChip(
                              avatar: const Icon(
                                Icons.play_circle_outline,
                                size: 18,
                              ),
                              label: Text(block.label),
                              tooltip: '跳转到此视频时间',
                              onPressed: () =>
                                  widget.onLink?.call(block.target!),
                            ),
                          ),
                        ),
                      if (widget.editing)
                        IconButton(
                          tooltip: block.image ? '移除截图' : '移除时间戳',
                          onPressed: () => _remove(block),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                    ],
                  ),
                  if (block.image) _image(block),
                ],
              ),
            ),
      ],
    );
  }
}

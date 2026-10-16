import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Reusable Markdown document editor and preview, independent of the player.
class MarkdownNoteEditor extends StatelessWidget {
  const MarkdownNoteEditor({
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

  /// Insert at selection, retaining surrounding Markdown and restoring the caret.
  static void insert(TextEditingController controller, String text) {
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : controller.text.length;
    final end = selection.isValid ? selection.end : start;
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  /// Wrap selected text in formatting without losing its contents.
  void _format(String prefix, String suffix) {
    final s = controller.selection;
    final text = s.isValid ? controller.text.substring(s.start, s.end) : '';
    insert(controller, '$prefix$text$suffix');
    onChanged?.call(controller.text);
  }

  @override
  Widget build(BuildContext context) {
    if (!editing) {
      return MarkdownBody(
        data: controller.text,
        selectable: true,
        onTapLink: (text, href, title) {
          if (href != null) onLink?.call(href);
        },
        imageBuilder: (uri, title, alt) {
          final path = attachments[uri.toString()];
          if (path == null) return Text(alt ?? '图片不可用');
          return Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, error, stack) => const Text('图片文件不可用'),
          );
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          children: [
            TextButton(
              onPressed: () => _format('## ', ''),
              child: const Text('标题'),
            ),
            TextButton(
              onPressed: () => _format('**', '**'),
              child: const Text('加粗'),
            ),
            TextButton(
              onPressed: () => _format('- ', ''),
              child: const Text('列表'),
            ),
            TextButton(
              onPressed: () => _format('> ', ''),
              child: const Text('引用'),
            ),
            TextButton(
              onPressed: () => _format('```\n', '\n```'),
              child: const Text('代码'),
            ),
            TextButton(
              onPressed: () => _format('[', '](https://)'),
              child: const Text('链接'),
            ),
            if (onTimestamp != null)
              TextButton.icon(
                onPressed: onTimestamp,
                icon: const Icon(Icons.schedule),
                label: const Text('时间戳'),
              ),
            if (onScreenshot != null)
              TextButton.icon(
                onPressed: capturing ? null : onScreenshot,
                icon: const Icon(Icons.screenshot_monitor),
                label: Text(capturing ? '截图中' : '截图'),
              ),
          ],
        ),
        TextField(
          key: const Key('markdown-note-body'),
          enabled: true,
          controller: controller,
          minLines: 8,
          maxLines: null,
          onChanged: onChanged,
          decoration: const InputDecoration(
            hintText: '使用 Markdown 记录学习内容…',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

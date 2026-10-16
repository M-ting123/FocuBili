import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focubili/features/notes/markdown_note_editor.dart';

void main() {
  testWidgets('formatting retains selected text and surrounding paragraphs', (
    tester,
  ) async {
    final controller = TextEditingController(text: '前文\n重点\n后文');
    controller.selection = const TextSelection(baseOffset: 3, extentOffset: 5);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MarkdownNoteEditor(controller: controller)),
      ),
    );
    await tester.tap(find.text('加粗'));
    expect(controller.text, '前文\n**重点**\n后文');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('preview renders Markdown and dispatches timestamp links', (
    tester,
  ) async {
    final controller = TextEditingController(
      text:
          '# 学习重点\n\n[时间 01:02](focubili://video?bvid=BV1GJ411x7h7&cid=100&page=1&ms=62000)',
    );
    String? target;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownNoteEditor(
            controller: controller,
            editing: false,
            onLink: (href) => target = href,
          ),
        ),
      ),
    );
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('时间 01:02', findRichText: true));
    expect(target, contains('ms=62000'));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}

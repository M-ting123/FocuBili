import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focubili/models/note_video_link.dart';
import 'package:focubili/models/note_markdown.dart';
import 'package:focubili/models/video_note.dart';
import 'package:focubili/services/video_note_export_service.dart';

void main() {
  test(
    'Markdown image references preserve titles and reference-style attachments',
    () {
      expect(
        noteImageReferences(
          '![一](images/a.png "截图")\n\n![二][frame]\n\n[frame]: images/b.png\n\n`![代码](images/unused.png)`',
        ),
        {'images/a.png', 'images/b.png'},
      );
    },
  );
  test('timestamp preserves milliseconds and part identity', () {
    const link = NoteVideoLink(
      'BV1GJ411x7h7',
      202,
      2,
      Duration(milliseconds: 62345),
    );
    final parsed = NoteVideoLink.parse('${link.uri}')!;
    expect(parsed.cid, 202);
    expect(parsed.position.inMilliseconds, 62345);
    expect(parsed.webUri.queryParameters, {'p': '2', 't': '62'});
    expect(
      NoteVideoLink.parse('focubili://video?bvid=bad&cid=2&page=1&ms=-1'),
      isNull,
    );
  });
  test(
    'multiple images export with independent paths and portable video links',
    () async {
      final dir = await Directory.systemTemp.createTemp('note-export');
      try {
        final a = File('${dir.path}/a.png');
        final b = File('${dir.path}/b.png');
        await a.writeAsBytes([1]);
        await b.writeAsBytes([2]);
        const link = NoteVideoLink(
          'BV1GJ411x7h7',
          202,
          2,
          Duration(seconds: 62),
        );
        final note = VideoNote(
          id: 'note',
          bvid: link.bvid,
          videoTitle: '视频',
          ownerName: 'UP',
          partCid: 202,
          partPageNumber: 2,
          partTitle: '第二节',
          title: '学习笔记',
          body:
              '# 重点\n[01:02](${link.uri})\n![一](images/a.png)\n![二](images/b.png)',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          position: Duration.zero,
          attachments: {'images/a.png': a.path, 'images/b.png': b.path},
        );
        final package = await const VideoNoteExportService().buildPackage([
          note,
        ], VideoNoteExportFormat.markdown);
        expect(package.imageCount, 2);
        final archive = ZipDecoder().decodeBytes(package.bytes);
        final md = utf8.decode(
          archive.find('focubili_notes.md')!.content as List<int>,
        );
        expect(
          md,
          contains('https://www.bilibili.com/video/BV1GJ411x7h7?p=2&t=62'),
        );
        expect(md, contains('images/0-note.png'));
        expect(md, contains('images/1-note.png'));
        expect(archive.find('images/0-note.png')!.content, [1]);
        expect(archive.find('images/1-note.png')!.content, [2]);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}

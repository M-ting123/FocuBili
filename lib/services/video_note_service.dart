import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/video_note.dart';

typedef VideoNotePreferencesLoader = Future<SharedPreferences> Function();

/// 使用 SharedPreferences 保存文字数据，并管理笔记附带的本机视频画面文件。
class VideoNoteService {
  /// 创建时间点笔记服务；测试可注入内存偏好设置读取器。
  VideoNoteService({VideoNotePreferencesLoader? preferencesLoader})
    : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const String storageKey = 'video_timepoint_notes_v1';
  // Kept for source compatibility; documents are never truncated.
  static const int maximumEntries = 500;
  static const String legacyBackupKey = 'video_timepoint_notes_original_backup';
  static Future<void>? _queue;

  /// Serialize mutations across instances to prevent lost autosaves.
  Future<T> _mutate<T>(Future<T> Function() operation) async {
    final previous = _queue;
    final completion = Completer<void>.sync();
    _queue = completion.future;
    if (previous != null) await previous;
    try {
      return await operation();
    } finally {
      if (identical(_queue, completion.future)) _queue = null;
      completion.complete();
    }
  }

  /// Preserve the original JSON before any rewrite.
  Future<void> _backup(SharedPreferences prefs) async {
    final raw = prefs.getString(storageKey);
    if (raw != null && prefs.getString(legacyBackupKey) == null) {
      if (!await prefs.setString(legacyBackupKey, raw)) {
        throw StateError('原始笔记备份失败');
      }
    }
  }

  /// Restore the cached previous value as well as disk contents after rejected writes.
  Future<void> _writeNotes(
    SharedPreferences prefs,
    List<VideoNote> notes,
  ) async {
    final original = prefs.getString(storageKey);
    try {
      if (!await prefs.setString(
        storageKey,
        jsonEncode(notes.map((note) => note.toJson()).toList()),
      )) {
        throw StateError('笔记保存失败');
      }
    } catch (_) {
      try {
        if (original == null) {
          await prefs.remove(storageKey);
        } else {
          await prefs.setString(storageKey, original);
        }
      } catch (_) {
        /* Preserve the failure so the editor retains the draft. */
      }
      rethrow;
    }
  }

  /// Coordinate backup import with autosave operations across service instances.
  Future<T> withExclusiveWrite<T>(Future<T> Function() operation) =>
      _mutate(operation);

  /// Move documents before deleting their folder, in one persisted operation.
  Future<void> moveFolder(String source, String target) => _mutate(() async {
    final prefs = await _preferencesLoader();
    final notes = _decodeNotes(prefs.getString(storageKey));
    if (!notes.any((note) => note.folderId == source)) return;
    await _backup(prefs);
    final moved = notes
        .map(
          (note) => note.folderId == source
              ? note.copyWith(folderId: target, updatedAt: DateTime.now())
              : note,
        )
        .toList();
    await _writeNotes(prefs, moved);
    for (final note in notes.where((note) => note.folderId == source)) {
      _changes.add(note.bvid);
    }
  });

  static final StreamController<String> _changes =
      StreamController<String>.broadcast();

  /// 通知所有服务实例同一 BV 的笔记已成功写入，播放器无需另建数据源。
  static Stream<String> get changes => _changes.stream;

  final VideoNotePreferencesLoader _preferencesLoader;

  /// Read persisted data without hiding corruption from backup transactions.
  Future<List<VideoNote>> loadNotesStrict() async {
    final prefs = await _preferencesLoader();
    return _decodeNotes(prefs.getString(storageKey));
  }

  /// Refresh open workspaces after a transactional backup import.
  void notifyChanges(Iterable<VideoNote> notes) {
    for (final bvid in notes.map((note) => note.bvid).toSet()) {
      _changes.add(bvid);
    }
  }

  /// 读取全部合法笔记，并按最近更新时间从新到旧排列。
  Future<List<VideoNote>> loadNotes() async {
    try {
      final SharedPreferences preferences = await _preferencesLoader();
      final List<VideoNote> notes = _decodeNotes(
        preferences.getString(storageKey),
      );
      notes.sort(
        // 排序函数让最近编辑过的笔记优先出现在“我的笔记”页面。
        (VideoNote left, VideoNote right) =>
            right.updatedAt.compareTo(left.updatedAt),
      );
      return List<VideoNote>.unmodifiable(notes);
    } catch (_) {
      return const <VideoNote>[];
    }
  }

  /// 读取指定 BV 视频的笔记，并按视频时间点从早到晚排列。
  Future<List<VideoNote>> loadNotesForVideo(String bvid) async {
    final String normalizedBvid = bvid.trim();
    final List<VideoNote> notes = (await loadNotes())
        .where((VideoNote note) => note.bvid == normalizedBvid)
        .toList(growable: true);
    notes.sort(
      // 时间点排序函数让全屏左侧列表与视频播放时间线保持一致。
      (VideoNote left, VideoNote right) =>
          left.position.compareTo(right.position),
    );
    return List<VideoNote>.unmodifiable(notes);
  }

  /// 新增或覆盖同编号笔记，并在更换画面时删除不再引用的旧文件。
  Future<void> saveNote(VideoNote note) => _mutate(() async {
    final VideoNote? normalized = VideoNote.tryParse(note.toJson());
    if (normalized == null) {
      throw ArgumentError.value(note, 'note', '笔记缺少必要信息。');
    }
    final SharedPreferences preferences = await _preferencesLoader();
    final List<VideoNote> notes = _decodeNotes(
      preferences.getString(storageKey),
    );
    await _backup(preferences);
    final int existingIndex = notes.indexWhere(
      (VideoNote item) => item.id == normalized.id,
    );
    final obsoletePaths = <String>[];
    String? obsoleteFramePath;
    if (existingIndex >= 0) {
      final VideoNote previous = notes[existingIndex];
      obsoletePaths.addAll(previous.attachments.values);
      if (previous.framePath != normalized.framePath) {
        obsoleteFramePath = previous.framePath;
      }
      notes[existingIndex] = normalized;
    } else {
      notes.add(normalized);
    }
    notes.sort(
      // 保存前排序函数让截断上限时优先保留最近编辑过的笔记。
      (VideoNote left, VideoNote right) =>
          right.updatedAt.compareTo(left.updatedAt),
    );
    final List<VideoNote> limited = notes;
    await _writeNotes(preferences, limited);
    _changes.add(normalized.bvid);
    final retainedPaths = notes
        .expand(
          (n) => [
            ...n.attachments.values,
            if (n.framePath != null) n.framePath!,
          ],
        )
        .toSet();
    for (final path in [...obsoletePaths, ?obsoleteFramePath]) {
      if (!retainedPaths.contains(path)) await _deleteFrameIfPresent(path);
    }
  });

  /// 删除指定编号的笔记，并同步清理该笔记独占的视频画面文件。
  Future<void> deleteNote(String id) => _mutate(() async {
    final String normalizedId = id.trim();
    if (normalizedId.isEmpty) {
      return;
    }
    final SharedPreferences preferences = await _preferencesLoader();
    final List<VideoNote> notes = _decodeNotes(
      preferences.getString(storageKey),
    );
    final VideoNote? removed = notes.cast<VideoNote?>().firstWhere(
      (VideoNote? item) => item?.id == normalizedId,
      orElse: () => null,
    );
    await _backup(preferences);
    notes.removeWhere((VideoNote item) => item.id == normalizedId);
    await _writeNotes(preferences, notes);
    if (removed != null) _changes.add(removed.bvid);
    final retainedPaths = notes
        .expand(
          (n) => [
            ...n.attachments.values,
            if (n.framePath != null) n.framePath!,
          ],
        )
        .toSet();
    for (final path in [
      ...?removed?.attachments.values,
      if (removed?.framePath != null) removed!.framePath!,
    ]) {
      if (!retainedPaths.contains(path)) await _deleteFrameIfPresent(path);
    }
  });

  /// 将本机 JSON 解码为去重后的笔记列表，损坏数据会被安全忽略。
  List<VideoNote> _decodeNotes(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) {
      return <VideoNote>[];
    }
    try {
      final Object? decoded = jsonDecode(rawJson);
      if (decoded is! List<Object?>) throw const FormatException('笔记数据损坏');
      final Set<String> seenIds = <String>{};
      final List<VideoNote> notes = <VideoNote>[];
      for (final Object? item in decoded) {
        if (item is! Map) throw const FormatException('笔记数据损坏');
        final VideoNote? note = VideoNote.tryParse(
          Map<String, dynamic>.from(item),
        );
        if (note == null) throw const FormatException('笔记数据损坏');
        if (seenIds.add(note.id)) {
          notes.add(note);
        }
      }
      return notes;
    } catch (_) {
      throw const FormatException('笔记数据损坏，原始数据已保留');
    }
  }

  /// 删除存在的本机画面文件；文件已不存在或删除失败不会影响文字笔记。
  Future<void> _deleteFrameIfPresent(String? framePath) async {
    if (framePath == null || framePath.trim().isEmpty) {
      return;
    }
    try {
      final File file = File(framePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // 画面清理失败不应导致用户的文字笔记保存或删除失败。
    }
  }
}

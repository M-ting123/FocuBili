/// A validated internal video timestamp, shared by playback and export.
class NoteVideoLink {
  const NoteVideoLink(this.bvid, this.cid, this.page, this.position);
  final String bvid;
  final int cid;
  final int page;
  final Duration position;
  Uri get uri => Uri(
    scheme: 'focubili',
    host: 'video',
    queryParameters: {
      'bvid': bvid,
      'cid': '$cid',
      'page': '$page',
      'ms': '${position.inMilliseconds}',
    },
  );
  Uri get webUri => Uri.https('www.bilibili.com', '/video/$bvid', {
    'p': '$page',
    't': '${position.inSeconds}',
  });
  static NoteVideoLink? parse(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'focubili' || uri.host != 'video') {
      return null;
    }
    final bvid = uri.queryParameters['bvid'] ?? '';
    final cid = int.tryParse(uri.queryParameters['cid'] ?? '');
    final page = int.tryParse(uri.queryParameters['page'] ?? '');
    final ms = int.tryParse(uri.queryParameters['ms'] ?? '');
    if (!RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(bvid) ||
        cid == null ||
        cid <= 0 ||
        page == null ||
        page <= 0 ||
        ms == null ||
        ms < 0) {
      return null;
    }
    return NoteVideoLink(bvid, cid, page, Duration(milliseconds: ms));
  }
}

import 'package:markdown/markdown.dart' as md;

/// Parse Markdown images so optional titles and reference syntax retain assets.
Set<String> noteImageReferences(String body) {
  final paths = <String>{};
  void visit(md.Node node) {
    if (node is md.Element) {
      final path = node.attributes['src'];
      if (node.tag == 'img' && path != null) paths.add(path);
      for (final child in node.children ?? <md.Node>[]) {
        visit(child);
      }
    }
  }

  for (final node in md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
  ).parseLines(body.split('\n'))) {
    visit(node);
  }
  return paths;
}

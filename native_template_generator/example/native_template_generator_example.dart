import 'package:native_template_support/native_template_support.dart';

part 'native_template_generator_example.g.dart';

class TemplateRenderer = _TemplateRenderer with _$TemplateRenderer;

abstract class _TemplateRenderer {
  @Template("example/template.html")
  Future<String> renderTemplate(String title, List<String> items, String? nullableString);

  @Template("example/header.html")
  String renderHeader(String title);

  @Template("example/footer.html")
  String renderFooter(String title);

  @Template("example/async.html")
  Future<String> renderAsync();

  Future<String> _asyncCall() async {
    await Future.delayed(Duration(milliseconds: 1));
    return "test-async-value";
  }
}

Future<void> main() async {
  final renderer = TemplateRenderer();
  print(await renderer.renderTemplate("super title", ["item0", "item1"], ""));
}

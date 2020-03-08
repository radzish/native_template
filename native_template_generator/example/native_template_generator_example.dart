import 'package:native_template_support/native_template_support.dart';

part 'native_template_generator_example.g.dart';

class TemplateRenderer = _TemplateRenderer with _$TemplateRenderer;

abstract class _TemplateRenderer {
  @Template("example/template.html")
  String renderTemplate(String title, List<String> items);

  @Template("example/header.html")
  String renderHeader(String title);

  @Template("example/footer.html")
  String renderFooter(String title);
}

void main() {
  final renderer = TemplateRenderer();
  print(renderer.renderTemplate("super title", ["item0", "item1"]));
}
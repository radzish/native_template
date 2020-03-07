import 'package:native_template_support/native_template_support.dart';

part 'native_template_generator_example.g.dart';

class TemplateRenderer = _TemplateRenderer with _$TemplateRenderer;

abstract class _TemplateRenderer {
  @Template("example/template.html")
  String renderTemplate(String title, List<String> items);
}

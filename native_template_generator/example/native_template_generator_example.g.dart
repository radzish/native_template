// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'native_template_generator_example.dart';

// **************************************************************************
// NativeTemplateGenerator
// **************************************************************************

mixin _$TemplateRenderer on _TemplateRenderer {
  @override
  String renderTemplate(String title, List<String> items) {
    final result = StringBuffer();
    result.write("<html>\n<body>\n<p>");
    result.write(title);
    result.write("</p>\n</body>\n<ul>\n    ");
    for (String item in items) {
      result.write("\n    <li>");
      result.write(item);
      result.write("</li>\n    ");
    }
    result.write("\n</ul>\n</html>");
    return result.toString();
  }
}

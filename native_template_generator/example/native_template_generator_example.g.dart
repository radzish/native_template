// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'native_template_generator_example.dart';

// **************************************************************************
// NativeTemplateGenerator
// **************************************************************************

mixin _$TemplateRenderer on _TemplateRenderer {
  @override
  Future<String> renderTemplate(String title, List<String> items) async {
    final result = StringBuffer();
    result.write(
        "<html>\n<body>\n<p>${title}</p>\n</body>\n${renderHeader(title)}\n<ul>\n    ");
    for (String item in items) {
      result.write("\n    <li>${item}</li>\n    ");
    }
    result.write(
        "\n</ul>\n${renderFooter(title)}\n${await renderAsync()}\n</html>");
    return result.toString();
  }

  @override
  String renderHeader(String title) {
    final result = StringBuffer();
    result.write("<p>this is header with ${title}</p>");
    return result.toString();
  }

  @override
  String renderFooter(String title) {
    final result = StringBuffer();
    result.write("<p>this is footer with ${title}</p>");
    return result.toString();
  }

  @override
  Future<String> renderAsync() async {
    final result = StringBuffer();
    result.write("${await _asyncCall()}");
    return result.toString();
  }
}

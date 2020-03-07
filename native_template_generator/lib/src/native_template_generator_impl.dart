import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:built_collection/built_collection.dart';
import 'package:native_template_support/native_template_support.dart';
import 'package:source_gen/source_gen.dart';
import 'package:code_builder/code_builder.dart' as code;
import 'package:string_scanner/string_scanner.dart';

final _templateChecker = TypeChecker.fromRuntime(Template);
final _stringChecker = TypeChecker.fromRuntime(String);
final _privateClassNameRegexp = RegExp(r"_+([^_]+)");

class NativeTemplateGenerator extends Generator {
  @override
  FutureOr<String> generate(LibraryReader library, BuildStep buildStep) async {
    final rendererClasses = library.classes.where(_hasPageMethod);

    if (rendererClasses.isEmpty) {
      return null;
    }

    final nonPrivateRenderer = rendererClasses.firstWhere((renderer) => !renderer.isPrivate, orElse: () => null);
    if (nonPrivateRenderer != null) {
      throw "class having template methods must be private: $nonPrivateRenderer";
    }

    return rendererClasses.map(_generateRendererClass).join("\n");
  }

  String _generateRendererClass(ClassElement cls) {
    return _convertToMixin(code.Class(
      (b) => b
        ..name = _generateMixinName(cls.displayName)
        ..types = _buildClassParameters(cls)
        ..extend = code.refer(_buildClassExtends(cls))
        ..methods = _buildPageMethods(cls),
    ).accept(code.DartEmitter()).toString());
  }

  ListBuilder<code.Method> _buildPageMethods(ClassElement cls) {
    final pageMethods = cls.methods.where(_isPageMethod);

    final invalidMethod = pageMethods.firstWhere(
        (method) => !method.isAbstract || method.isAsynchronous || !_stringChecker.isExactlyType(method.returnType),
        orElse: () => null);

    if (invalidMethod != null) {
      throw "template render method must be synchronous, abstract and return String";
    }

    return ListBuilder(
      pageMethods.map(
        (method) => code.Method(
          (b) => b
            ..name = method.name
            ..requiredParameters = _buildMethodRequiredParams(method)
            ..optionalParameters = _buildMethodOptionalParams(method)
            ..returns = code.refer("String")
            ..annotations = ListBuilder([code.refer("override").expression])
            ..body = _buildMethodBody(method),
        ),
      ),
    );
  }

  String _convertToMixin(String classCode) {
    // replace class with mixin keyword
    var result = "mixin ${classCode.substring(5)}";

    // find last "extends" before first {
    final openingBracePosition = result.indexOf("{");
    final extendsPosition = result.substring(0, openingBracePosition).lastIndexOf("extends");

    // replace "extends" with "on"
    result = result.substring(0, extendsPosition) + " on " + result.substring(extendsPosition + "extends".length);

    return result;
  }

  String _generateMixinName(String name) {
    return "_\$${_privateClassNameRegexp.firstMatch(name).group(1)}";
  }

  ListBuilder<code.Reference> _buildClassParameters(ClassElement cls) {
    return ListBuilder(
      cls.typeParameters.map((param) => code.refer(param.toString())),
    );
  }

  String _buildClassExtends(ClassElement cls) {
    if (cls.typeParameters.isEmpty ||
        cls.typeParameters.length == 1 && cls.typeParameters.first.displayName == "dynamic") {
      return cls.displayName;
    }

    return "${cls.displayName}<${cls.typeParameters.map((param) => param.displayName).join(",")}>";
  }

  bool _hasPageMethod(ClassElement element) => element.methods.any(_isPageMethod);

  bool _isPageMethod(MethodElement method) => _templateChecker.hasAnnotationOfExact(method);

  ListBuilder<code.Parameter> _buildMethodRequiredParams(FunctionTypedElement constructor) {
    return ListBuilder(
      constructor.parameters.where((param) => param.isRequiredPositional).map(_buildMethodParam),
    );
  }

  ListBuilder<code.Parameter> _buildMethodOptionalParams(FunctionTypedElement constructor) {
    return ListBuilder(
      constructor.parameters.where((param) => param.isRequiredNamed || param.isOptional).map(_buildMethodParam),
    );
  }

  code.Parameter _buildMethodParam(ParameterElement param) {
    return code.Parameter((b) => b
      ..name = param.name
      ..type = code.refer(param.type.toString())
      ..named = param.isNamed);
  }

  code.Code _buildMethodBody(MethodElement method) {
    final templateAnnotation = _templateChecker.firstAnnotationOf(method);
    final templatePath = templateAnnotation.getField("path").toStringValue();

    final template = File.fromUri(Uri.parse(templatePath)).readAsStringSync();

    return code.Code(_compileTemplate(template));
  }

  String _compileTemplate(String template) {
    final result = StringBuffer("""
      final result = StringBuffer();
      """);

    final scanner = StringScanner(template);

    final textRegExp = RegExp(r"((?!<%).)+", dotAll: true);
    final expressionRegExp = RegExp(r"<%=(((?!%>).)+)%>", dotAll: true);
    final blockRegExp = RegExp(r"<%(((?!%>).)+)%>", dotAll: true);

    while (!scanner.isDone) {
      if (scanner.scan(textRegExp)) {
        final text = scanner.lastMatch.group(0);
        _writeText(result, text);
      } else if (scanner.scan(expressionRegExp)) {
        final expression = scanner.lastMatch.group(1);
        _writeExpression(result, expression);
      } else if (scanner.scan(blockRegExp)) {
        final code = scanner.lastMatch.group(1);
        _writeCode(result, code);
      } else {
        int errorLineNumber = _calculateErrorLineNumber(template, scanner);
        throw "native template compilation error at line ${errorLineNumber}";
      }
    }

    result.write("""
      return result.toString();
      """);

    return result.toString();
  }

  int _calculateErrorLineNumber(String template, StringScanner scanner) {
    final splitter = LineSplitter();
    List<String> lines = splitter.convert(template);
    int totalLength = 0;
    int currentLineNumber = 0;
    while (totalLength < scanner.position && currentLineNumber < lines.length) {
      totalLength += lines[currentLineNumber++].length + 1;
    }
    var errorLineNumber = currentLineNumber > 0 ? currentLineNumber : currentLineNumber + 1;
    return errorLineNumber;
  }

  void _writeText(StringBuffer result, String text) {
    result.write("result.write(\"${text.replaceAll("\n", "\\n").replaceAll("\"", "\\\"")}\");");
  }

  void _writeExpression(StringBuffer result, String expression) {
    result.write("result.write($expression);");
  }

  void _writeCode(StringBuffer result, String code) {
    result.write(code);
  }
}
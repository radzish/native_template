import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:built_collection/built_collection.dart';
import 'package:native_template_support/native_template_support.dart';
import 'package:source_gen/source_gen.dart';
import 'package:code_builder/code_builder.dart' as code;
import 'package:string_scanner/string_scanner.dart';

final _templateChecker = TypeChecker.fromRuntime(Template);
final _stringChecker = TypeChecker.fromRuntime(String);
final _futureChecker = TypeChecker.fromRuntime(Future);
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
          (b) =>
      b
        ..name = _generateMixinName(cls.displayName)
        ..types = _buildClassParameters(cls)
        ..extend = code.refer(_buildClassExtends(cls))
        ..methods = _buildPageMethods(cls),
    ).accept(code.DartEmitter()).toString());
  }

  ListBuilder<code.Method> _buildPageMethods(ClassElement cls) {
    final pageMethods = cls.methods.where(_isPageMethod);

    final invalidMethod = pageMethods
        .firstWhere((method) => !method.isAbstract || !_isSuitableReturnType(method.returnType), orElse: () => null);

    if (invalidMethod != null) {
      throw "template render method must be synchronous, abstract and return String";
    }

    return ListBuilder(
      pageMethods.map(
            (method) =>
            code.Method(
                  (b) =>
              b
                ..name = method.name
                ..requiredParameters = _buildMethodRequiredParams(method)
                ..optionalParameters = _buildMethodOptionalParams(method)
                ..returns = _isAsync(method) ? code.refer("Future<String>") : code.refer("String")
                ..annotations = ListBuilder([code
                    .refer("override")
                    .expression
                ])
                ..modifier = _isAsync(method) ? code.MethodModifier.async : null
                ..body = _buildMethodBody(method),
            ),
      ),
    );
  }

  bool _isAsync(MethodElement method) {
    // abstract methods do not have async modifier. so we need to check return type if it is Future
    return _futureChecker.isExactlyType(method.returnType);
  }

  bool _isSuitableReturnType(DartType type) {
    if (_stringChecker.isExactlyType(type)) {
      return true;
    }

    if (_futureChecker.isExactlyType(type)) {
      final futureGenerics = (type as InterfaceType).typeArguments;
      if (futureGenerics.isNotEmpty) {
        if (_stringChecker.isExactlyType(futureGenerics.first)) {
          return true;
        }
      }
    }

    return false;
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
    return code.Parameter((b) =>
    b
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
    final blockRegExp = RegExp(r"<%(((?!%>).)+)%>", dotAll: true);

    while (!scanner.isDone) {
      if (scanner.scan(textRegExp)) {
        final text = scanner.lastMatch.group(0);
        _writeText(result, text);
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
    final nativeExpressionRegExp = RegExp(r"\$\{(((?!\}).)+)\}", dotAll: true);
    final escaped = text.splitMapJoin(
      nativeExpressionRegExp,
      // native expression goes as is
      onMatch: (match) => match.group(0),
      // rest of the text should be escaped
      onNonMatch: (simpleText) => simpleText.replaceAll("\n", "\\n").replaceAll("\"", "\\\""),
    );
    result.write("result.write(\"${escaped}\");");
  }

  void _writeExpression(StringBuffer result, String expression) {
    result.write("result.write($expression);");
  }

  void _writeCode(StringBuffer result, String code) {
    result.write(code);
  }
}

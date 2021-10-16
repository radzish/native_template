library builder;

import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/native_template_generator_impl.dart';

Builder nativeTemplateGenerator(BuilderOptions _) =>
    SharedPartBuilder([NativeTemplateGenerator()], 'native_template_generator');

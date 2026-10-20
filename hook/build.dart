import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildMaterials(
      buildInput: input,
      buildOutput: output,
      materials: [
        'assets/atmosphere/sky.fmat',
        'assets/atmosphere/clouds.fmat',
      ],
    );
  });
}

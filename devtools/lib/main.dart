import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

import 'src/panel.dart';

void main() {
  runApp(const DevToolsExtension(child: WhisperPanel()));
}

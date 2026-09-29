import 'dart:io';

void main() {
  final dir = Directory('lib');
  int count = 0;
  
  final regex = RegExp(r"content:\s*Text\([^)]*\$e[^)]*\)");
  
  for (var file in dir.listSync(recursive: true)) {
    if (file is File && file.path.endsWith('.dart') && !file.path.contains('error_mapper.dart')) {
      var content = file.readAsStringSync();
      if (regex.hasMatch(content)) {
        content = content.replaceAll(regex, "content: Text(mapRawErrorToUserMessage(e))");
        
        if (!content.contains('import \'package:re_v/core/utils/error_mapper.dart\';')) {
          content = "import 'package:re_v/core/utils/error_mapper.dart';\n" + content;
        }
        
        file.writeAsStringSync(content);
        count++;
      }
    }
  }
  print('Replaced in $count files.');
}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app/bootstrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Color(0xFFF1F7F6),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const AppBootstrap());
}

import 'dart:async';
import 'package:fl_clash/xboard/features/splash/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'application.dart';

Future<void> run(Future<void> Function() initializeApp) async {
  runApp(const ProviderScope(child: SplashScreen()));
  await initializeApp();
  runApp(const ProviderScope(child: Application()));
}

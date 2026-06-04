import 'package:flutter/material.dart';
import 'package:hrms_plaridel/app/app.dart';
import 'package:hrms_plaridel/app/bootstrap.dart';

export 'package:hrms_plaridel/app/app.dart' show MyApp;
export 'package:hrms_plaridel/app/app_constants.dart' show kLoginAsKey;
export 'package:hrms_plaridel/app/route_observer.dart' show routeObserver;

Future<void> main() async {
  final bootstrap = await bootstrapApp();
  runApp(MyApp(auth: bootstrap.auth, themeNotifier: bootstrap.themeNotifier));
}

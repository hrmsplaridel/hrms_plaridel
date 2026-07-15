import 'package:flutter/material.dart';
import 'package:hrms_plaridel/app/app.dart';
import 'package:hrms_plaridel/app/bootstrap.dart';

export 'package:hrms_plaridel/app/app.dart' show MyApp;
export 'package:hrms_plaridel/app/app_constants.dart' show kLoginAsKey;
export 'package:hrms_plaridel/app/route_observer.dart' show routeObserver;

Future<void> main(List<String> arguments) async {
  final bootstrap = await bootstrapApp(
    startHidden: arguments.contains('--hidden'),
  );
  runApp(MyApp(auth: bootstrap.auth, themeNotifier: bootstrap.themeNotifier));
}

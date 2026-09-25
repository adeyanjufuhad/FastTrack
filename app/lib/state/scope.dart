import 'package:flutter/material.dart';

import 'app_state.dart';

/// Minimal inherited access to [AppState] — no state-management package.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Read without subscribing (for callbacks).
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

extension AppStateX on BuildContext {
  AppState get app => AppScope.of(this);
  AppState get appRead => AppScope.read(this);

  void toast(String message) => ScaffoldMessenger.maybeOf(this)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

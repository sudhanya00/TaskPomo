import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/paper.dart';
import '../state/app_controller.dart';
import '../theme.dart';
import '../state/timer_controller.dart';

/// Pushes a page that can still see the signed-in user's controllers (the
/// providers live under the home route, not above the navigator).
Future<T?> pushPage<T>(BuildContext context, Widget page) {
  return pushPageWith<T>(
    Navigator.of(context),
    context.read<AppController>(),
    context.read<TimerController>(),
    page,
  );
}

Future<T?> pushPageWith<T>(
  NavigatorState nav,
  AppController app,
  TimerController timer,
  Widget page,
) {
  return nav.push<T>(
    MaterialPageRoute(
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: app),
          ChangeNotifierProvider.value(value: timer),
        ],
        child: AgedPaper(child: page),
      ),
    ),
  );
}

/// Applies today's paper: it yellows as the day goes on with work left and
/// is fresh again once everything is done.
class AgedPaper extends StatelessWidget {
  const AgedPaper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final age = paperAge(
      tasks: app.tasks,
      todayLogs: app.todayLogs,
      today: app.today,
      now: DateTime.now(),
    );
    // Steps of 2% keep the theme from rebuilding on every tiny change.
    final stepped = (age * 50).round() / 50;
    return AnimatedTheme(
      data: AppTheme.light(age: stepped),
      duration: const Duration(milliseconds: 900),
      child: child,
    );
  }
}

import 'package:flutter/widgets.dart';

/// Lets any descendant switch the active bottom-nav tab (e.g. jump to 航行
/// right after a launch). Lives in its own file so pages can depend on it
/// without importing the shell.
class ShellScope extends InheritedWidget {
  const ShellScope({
    super.key,
    required this.goToTab,
    required super.child,
  });

  final void Function(int index) goToTab;

  static void go(BuildContext context, int index) {
    final scope = context.getInheritedWidgetOfExactType<ShellScope>();
    assert(scope != null, 'ShellScope not found');
    scope?.goToTab(index);
  }

  /// The nearest scope, or null. Used to re-provide the tab switcher into
  /// routes/sheets pushed above the shell (which don't inherit it).
  static ShellScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope oldWidget) => false;
}

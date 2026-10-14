import 'package:flutter/foundation.dart';

/// Which bottom-navigation destination is selected.
///
/// Kept outside the widget tree so screens (e.g. the gallery's "Convert" action) can move the
/// user to another tab without threading callbacks through every widget.
enum AppTab { home, gallery, convert, tools, settings }

class ShellController extends ChangeNotifier {
  AppTab _tab = AppTab.home;

  AppTab get tab => _tab;
  int get index => _tab.index;

  void select(AppTab tab) {
    if (tab == _tab) {
      return;
    }
    _tab = tab;
    notifyListeners();
  }

  void selectIndex(int index) {
    if (index < 0 || index >= AppTab.values.length) {
      return;
    }
    select(AppTab.values[index]);
  }
}

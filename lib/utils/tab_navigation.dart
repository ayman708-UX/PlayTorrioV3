import 'package:flutter/foundation.dart';

/// Global tab index for the root `IndexedStack` in `HomePage`
/// (Home = 0, MultiNutz = 1). Lets any widget deep inside a tab request a
/// switch to the MultiNutz hub without threading callbacks through the tree.
class TabNav {
  TabNav._();

  static const int home = 0;
  static const int multiWindow = 1;

  static final ValueNotifier<int> index = ValueNotifier<int>(home);

  static void switchTo(int tab) => index.value = tab;
}
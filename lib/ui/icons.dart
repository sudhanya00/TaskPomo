import 'package:flutter/widgets.dart';

// Phosphor icons (MIT), used straight from the bundled icon fonts.
const _regular = 'PhosphorRegular';
const _fill = 'PhosphorFill';

/// Line icons a task can wear. Keys are stored on the task, so never rename
/// one; add new keys instead.
const taskIcons = <String, IconData>{
  'book': IconData(0xe0e6, fontFamily: _regular),
  'pen': IconData(0xebc6, fontFamily: _regular),
  'brush': IconData(0xe6f0, fontFamily: _regular),
  'camera': IconData(0xe10e, fontFamily: _regular),
  'guitar': IconData(0xea8a, fontFamily: _regular),
  'music': IconData(0xe342, fontFamily: _regular),
  'piano': IconData(0xe9c8, fontFamily: _regular),
  'headphones': IconData(0xe2a6, fontFamily: _regular),
  'mic': IconData(0xe326, fontFamily: _regular),
  'code': IconData(0xe1bc, fontFamily: _regular),
  'keyboard': IconData(0xe2d8, fontFamily: _regular),
  'briefcase': IconData(0xe0ee, fontFamily: _regular),
  'study': IconData(0xe62c, fontFamily: _regular),
  'atom': IconData(0xe5e4, fontFamily: _regular),
  'calculator': IconData(0xe538, fontFamily: _regular),
  'brain': IconData(0xe74e, fontFamily: _regular),
  'translate': IconData(0xe4a2, fontFamily: _regular),
  'chats': IconData(0xe17c, fontFamily: _regular),
  'globe': IconData(0xe288, fontFamily: _regular),
  'run': IconData(0xe730, fontFamily: _regular),
  'barbell': IconData(0xe0b6, fontFamily: _regular),
  'lotus': IconData(0xe6cc, fontFamily: _regular),
  'heart': IconData(0xe2ac, fontFamily: _regular),
  'leaf': IconData(0xe2da, fontFamily: _regular),
  'chef': IconData(0xed8e, fontFamily: _regular),
  'puzzle': IconData(0xe596, fontFamily: _regular),
  'idea': IconData(0xe2dc, fontFamily: _regular),
  'notes': IconData(0xe63e, fontFamily: _regular),
  'circle': IconData(0xe18a, fontFamily: _regular),
};

IconData taskIcon(String key) =>
    taskIcons[key] ?? const IconData(0xe18a, fontFamily: _regular);

/// Interface icons.
class Ic {
  Ic._();

  static const today = IconData(0xe5b6, fontFamily: _regular);
  static const insights = IconData(0xe156, fontFamily: _regular);
  static const me = IconData(0xe4c2, fontFamily: _regular);
  static const back = IconData(0xe058, fontFamily: _regular);
  static const more = IconData(0xe1fe, fontFamily: _regular);
  static const play = IconData(0xe3d0, fontFamily: _fill);
  static const pause = IconData(0xe39e, fontFamily: _regular);
  static const check = IconData(0xe182, fontFamily: _regular);
  static const plus = IconData(0xe3d4, fontFamily: _regular);
  static const close = IconData(0xe4f6, fontFamily: _regular);
  static const chevron = IconData(0xe13a, fontFamily: _regular);
  static const freeze = IconData(0xe5aa, fontFamily: _regular);
  static const travel = IconData(0xe5d6, fontFamily: _regular);
  static const edit = IconData(0xe3b4, fontFamily: _regular);
  static const trash = IconData(0xe4a6, fontFamily: _regular);
  static const signOut = IconData(0xe42a, fontFamily: _regular);
  static const refresh = IconData(0xe036, fontFamily: _regular);
  static const share = IconData(0xeaf0, fontFamily: _regular);
  static const calendar = IconData(0xe10a, fontFamily: _regular);
  static const google = IconData(0xe292, fontFamily: _regular);
}

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'theme.dart';

/// Designer session icons: 18px, `stroke="currentColor"`, painted `on-accent`.
const double kRwSessionIconSize = 18;

const String kRwIconChat = 'assets/session/chat.svg';
const String kRwIconClipboard = 'assets/session/clipboard.svg';
const String kRwIconDisplay = 'assets/session/display.svg';
const String kRwIconEdit = 'assets/session/edit.svg';
const String kRwIconFiles = 'assets/session/files.svg';
const String kRwIconFullscreen = 'assets/session/fullscreen.svg';
const String kRwIconKeyboard = 'assets/session/keyboard.svg';
const String kRwIconMore = 'assets/session/more.svg';

/// Map a legacy toolbar asset onto the 8 provided session SVGs when possible.
String rwSessionAsset(String assetName) {
  final name = assetName.split('/').last;
  switch (name) {
    case 'chat.svg':
    case 'message_24dp_5F6368.svg':
      return kRwIconChat;
    case 'display.svg':
    case 'display_switcher.svg':
    case 'screen.svg':
      return kRwIconDisplay;
    case 'keyboard_mouse.svg':
    case 'keyboard.svg':
      return kRwIconKeyboard;
    case 'actions.svg':
    case 'more.svg':
    case 'actions_mobile.svg':
      return kRwIconMore;
    case 'clipboard.svg':
      return kRwIconClipboard;
    case 'file.svg':
    case 'files.svg':
    case 'folder.svg':
      return kRwIconFiles;
    case 'fullscreen.svg':
      return kRwIconFullscreen;
    case 'edit.svg':
      return kRwIconEdit;
    case 'pinned.svg':
    case 'unpinned.svg':
    case 'rec.svg':
    case 'voice_call.svg':
    case 'call_wait.svg':
      return kRwIconMore;
    default:
      return kRwIconMore;
  }
}

Widget rwSessionSvg(String assetName, {Color? color, double size = kRwSessionIconSize}) {
  return SvgPicture.asset(
    rwSessionAsset(assetName),
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color ?? RwColors.onAccent, BlendMode.srcIn),
  );
}

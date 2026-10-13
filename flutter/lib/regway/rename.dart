import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../common.dart';
import '../models/peer_model.dart';
import '../models/platform_model.dart';
import '../utils/http_service.dart' as http;
import 'session_icons.dart';
import 'theme.dart';

/// Inline rename: hover `edit.svg` (muted) → same-height field.
/// Enter save, Esc cancel, empty not saved; spinner while saving;
/// toast «Не удалось переименовать».
class RwRenameName extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Future<bool> Function(String next) onSave;
  const RwRenameName({
    super.key,
    required this.text,
    required this.onSave,
    this.style,
  });

  @override
  State<RwRenameName> createState() => _RwRenameNameState();
}

class _RwRenameNameState extends State<RwRenameName> {
  bool _hover = false;
  bool _editing = false;
  bool _saving = false;
  late final TextEditingController _ctl;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: widget.text);
  }

  @override
  void didUpdateWidget(covariant RwRenameName old) {
    super.didUpdateWidget(old);
    if (!_editing && old.text != widget.text) {
      _ctl.text = widget.text;
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final next = _ctl.text.trim();
    if (next.isEmpty || next == widget.text) {
      setState(() => _editing = false);
      _ctl.text = widget.text;
      return;
    }
    setState(() => _saving = true);
    final ok = await widget.onSave(next);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _editing = false;
    });
    if (!ok) {
      _ctl.text = widget.text;
      showToast(translate('Failed to rename'));
    }
  }

  void _cancel() {
    _ctl.text = widget.text;
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    final style = widget.style ?? p.textH3;
    if (_editing || _saving) {
      return SizedBox(
        height: 22,
        child: Row(
          children: [
            Expanded(
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (e) {
                  if (e is KeyDownEvent &&
                      e.logicalKey == LogicalKeyboardKey.escape) {
                    _cancel();
                  }
                },
                child: TextField(
                  controller: _ctl,
                  focusNode: _focus,
                  autofocus: true,
                  enabled: !_saving,
                  style: style,
                  cursorColor: p.accent,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: (_) => _save(),
                ),
              ),
            ),
            if (_saving)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: p.accent,
                ),
              ),
          ],
        ),
      );
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        children: [
          Flexible(
            child: Text(
              widget.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (_hover) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                setState(() => _editing = true);
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _focus.requestFocus());
              },
              child: SvgPicture.asset(
                kRwIconEdit,
                width: 14,
                height: 14,
                colorFilter: ColorFilter.mode(p.muted, BlendMode.srcIn),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<bool> rwRenamePeer(Peer peer, String alias) async {
  try {
    await bind.mainSetPeerAlias(id: peer.id, alias: alias);
  } catch (_) {}
  try {
    final api = '${await bind.mainGetApiServer()}/api/ab/peer';
    final headers = getHttpHeaders();
    headers['Content-Type'] = 'application/json';
    final resp = await http.post(
      Uri.parse(api),
      headers: headers,
      body:
          '{"id":"${peer.id}","alias":${_jsonStr(alias)},"hostname":${_jsonStr(alias)}}',
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) return false;
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> rwRenameOwn(String hostname) async {
  try {
    bind.mainSetCommon(key: 'rw-rename-own', value: hostname);
    return true;
  } catch (_) {
    return false;
  }
}

String _jsonStr(String s) => '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

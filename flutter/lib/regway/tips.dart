import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Tooltip that opens on hover AND keyboard focus (C3) or hover AND click (C6).
class RwTip extends StatefulWidget {
  final String message;
  final Widget child;
  final bool click;
  final bool focus;
  const RwTip({
    super.key,
    required this.message,
    required this.child,
    this.click = false,
    this.focus = true,
  });

  @override
  State<RwTip> createState() => _RwTipState();
}

class _RwTipState extends State<RwTip> {
  final _layer = OverlayPortalController();
  bool _hover = false;
  bool _focus = false;
  bool _pinned = false;

  void _sync() {
    final show = _hover || (_focus && widget.focus) || _pinned;
    if (show) {
      if (!_layer.isShowing) _layer.show();
    } else {
      if (_layer.isShowing) _layer.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    return OverlayPortal(
      controller: _layer,
      overlayChildBuilder: (ctx) {
        return TapRegion(
          onTapOutside: (_) {
            if (_pinned) {
              setState(() {
                _pinned = false;
                _sync();
              });
            }
          },
          child: Align(
            alignment: Alignment.topLeft,
            child: CompositedTransformFollower(
              link: _link,
              offset: const Offset(0, 28),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 280),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.cardBorder),
                    boxShadow: p.cardShadow,
                  ),
                  child: Text(widget.message, style: p.textMuted.copyWith(fontSize: 12.5)),
                ),
              ),
            ),
          ),
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: FocusableActionDetector(
          onShowHoverHighlight: (v) {
            setState(() {
              _hover = v;
              _sync();
            });
          },
          onFocusChange: (v) {
            setState(() {
              _focus = v;
              _sync();
            });
          },
          actions: {
            if (widget.click)
              ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
                setState(() {
                  _pinned = !_pinned;
                  _sync();
                });
                return null;
              }),
          },
          shortcuts: widget.click
              ? const {
                  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                }
              : null,
          child: GestureDetector(
            onTap: widget.click
                ? () => setState(() {
                      _pinned = !_pinned;
                      _sync();
                    })
                : null,
            child: widget.child,
          ),
        ),
      ),
    );
  }

  final _link = LayerLink();
}

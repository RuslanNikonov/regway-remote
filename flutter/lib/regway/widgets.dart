import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

class RwPanel extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final bool expand;
  final bool hoverable;
  const RwPanel({
    super.key,
    required this.child,
    this.padding,
    this.width,
    this.expand = false,
    this.hoverable = false,
  });

  @override
  State<RwPanel> createState() => _RwPanelState();
}

class _RwPanelState extends State<RwPanel> {
  bool hover = false;
  bool focus = false;

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    final body = Material(
      color: Colors.transparent,
      child: MouseRegion(
        onEnter: widget.hoverable ? (_) => setState(() => hover = true) : null,
        onExit: widget.hoverable ? (_) => setState(() => hover = false) : null,
        child: Focus(
          canRequestFocus: false,
          onFocusChange: widget.hoverable
              ? (v) => setState(() => focus = v)
              : null,
          child: Container(
            width: widget.width,
            padding: widget.padding ?? const EdgeInsets.all(18),
            decoration: RwDecor.panelOf(p, hover: hover, focus: focus),
            child: DefaultTextStyle(
              style: p.textBody,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
    if (widget.expand) {
      return SizedBox.expand(child: body);
    }
    return body;
  }
}

class RwButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool ghost;
  final bool danger;
  final EdgeInsetsGeometry? padding;
  const RwButton({
    super.key,
    required this.label,
    this.onPressed,
    this.ghost = false,
    this.danger = false,
    this.padding,
  });

  @override
  State<RwButton> createState() => _RwButtonState();
}

class _RwButtonState extends State<RwButton> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    final enabled = widget.onPressed != null;
    final Color bg;
    final Color fg;
    if (widget.danger) {
      bg = hover && enabled ? p.dangerHover : p.danger;
      fg = p.white;
    } else if (widget.ghost) {
      bg = p.ghostFill;
      fg = enabled ? p.text : p.muted.withOpacity(0.6);
    } else {
      bg = !enabled
          ? p.accent.withOpacity(0.35)
          : (hover ? p.accentHover : p.accent);
      fg = p.onAccent;
    }
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      cursor:
          enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          alignment: Alignment.center,
          padding: widget.padding ??
              const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(RwDim.radiusField),
            border: widget.ghost ? Border.all(color: p.cardBorder) : null,
          ),
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: p.textBtn.copyWith(
              color: fg,
              fontWeight: widget.ghost ? FontWeight.w600 : FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class RwSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const RwSwitch({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: RwDim.switchW,
        height: RwDim.switchH,
        decoration: BoxDecoration(
          color: value ? p.accent : p.toggleOff,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Align(
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: RwDim.switchThumb,
            height: RwDim.switchThumb,
            decoration: BoxDecoration(
              color: p.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class RwAvatar extends StatelessWidget {
  final String letter;
  final double size;
  const RwAvatar({super.key, required this.letter, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    final ch = letter.trim().isEmpty
        ? '?'
        : letter.trim().substring(0, 1).toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RwDecor.avatar,
      ),
      alignment: Alignment.center,
      child: Text(
        ch,
        style: TextStyle(
          fontFamily: RwFonts.head,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.42,
          color: p.onAccent,
        ),
      ),
    );
  }
}

class RwStatusDot extends StatelessWidget {
  final bool online;
  final String? label;
  const RwStatusDot({super.key, required this.online, this.label});

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    final color = online ? p.accent : p.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: online
                ? [
                    BoxShadow(
                      color: p.accent.withOpacity(0.9),
                      blurRadius: 8,
                    )
                  ]
                : null,
          ),
        ),
        if (label != null) ...[
          const SizedBox(width: 7),
          Text(
            label!,
            style: p.textBodyStrong.copyWith(
              fontSize: 13,
              color: color,
            ),
          ),
        ],
      ],
    );
  }
}

class RwIconHit extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  const RwIconHit({super.key, required this.icon, this.onTap, this.tooltip});

  @override
  State<RwIconHit> createState() => _RwIconHitState();
}

class _RwIconHitState extends State<RwIconHit> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    final child = MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: p.cardBorder),
            color: hover ? p.ghostFill : Colors.transparent,
          ),
          child: Icon(widget.icon, size: 15, color: p.muted),
        ),
      ),
    );
    if (widget.tooltip == null) return child;
    return Tooltip(message: widget.tooltip!, child: child);
  }
}

class RwTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hint;
  final bool obscure;
  final bool readOnly;
  final bool big;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;
  final FocusNode? focusNode;
  final String? errorText;
  const RwTextField({
    super.key,
    this.controller,
    this.hint,
    this.obscure = false,
    this.readOnly = false,
    this.big = false,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.suffix,
    this.focusNode,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: RwDecor.inputOf(p),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  obscureText: obscure,
                  readOnly: readOnly,
                  keyboardType: keyboardType,
                  inputFormatters: inputFormatters,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  style: (big ? p.textNum : p.textBody).copyWith(
                    fontFeatures: kRwTabularFigures,
                    fontSize: big ? 22 : 13,
                    fontWeight: big ? FontWeight.w700 : FontWeight.w400,
                    color: p.text,
                  ),
                  cursorColor: p.accent,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    // Hint only when there is no external label with the same text.
                    hintText: hint,
                    hintStyle: p.textMuted.copyWith(fontSize: 13),
                    labelText: null,
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              if (suffix != null) suffix!,
            ],
          ),
        ),
        if (errorText != null && errorText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(errorText!, style: p.textError),
          ),
      ],
    );
  }
}

class RwLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double fontSize;
  const RwLink({
    super.key,
    required this.label,
    this.onTap,
    this.fontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          label,
          style: p.textLink.copyWith(fontSize: fontSize),
        ),
      ),
    );
  }
}

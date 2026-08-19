import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Highlight color used for D-pad focus rings across the app.
const Color kDpadGold = Color(0xFFFFD700);

/// Global D-pad / TV-remote navigation setup.
///
/// * Forces the traditional focus-highlight mode so Material widgets render
///   their focus rings on every platform (including touch).
/// * Listens for focus changes and auto-scrolls the enclosing scrollables so
///   the focused element stays in view when moving with arrow keys / D-pad.
class DpadNavigation {
  DpadNavigation._();

  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    // FocusManager notifies whenever the primary focus changes.
    FocusManager.instance.addListener(_ensureFocusedVisible);
  }

  static void _ensureFocusedVisible() {
    final node = FocusManager.instance.primaryFocus;
    if (node == null || !node.hasFocus) return;
    final context = node.context;
    if (context == null) return;
    // Scrolls the nearest scrollable(s) so the focused item is centered.
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }
}

/// Wraps any custom tappable (movie card, hero slide, dock item, arrow) so it
/// can be reached and activated with arrow keys / a TV remote, drawing a gold
/// highlight ring + glow while focused. For custom widgets only — Material
/// buttons already render their own focus rings once [DpadNavigation] is on.
class DpadFocus extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool autoFocus;
  final double radius;
  final Color ringColor;

  const DpadFocus({
    super.key,
    required this.child,
    this.onPressed,
    this.focusNode,
    this.autoFocus = false,
    this.radius = 14,
    this.ringColor = kDpadGold,
  });

  @override
  State<DpadFocus> createState() => _DpadFocusState();
}

class _DpadFocusState extends State<DpadFocus> {
  late final FocusNode _node = widget.focusNode ?? FocusNode();

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChanged);
    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _node.requestFocus();
      });
    }
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant DpadFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChanged);
      if (oldWidget.focusNode == null && widget.focusNode != null) {
        _node.removeListener(_onFocusChanged);
      }
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChanged);
    if (widget.focusNode == null) _node.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final activate =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA;
    if (activate) {
      widget.onPressed?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final focused = _node.hasFocus;
    return Focus(
      focusNode: _node,
      onKeyEvent: _handleKey,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (focused)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.radius),
                    border: Border.all(
                      color: widget.ringColor,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.ringColor.withValues(alpha: 0.45),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: widget.ringColor.withValues(alpha: 0.25),
                        blurRadius: 36,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
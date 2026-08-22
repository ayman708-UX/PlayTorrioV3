import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../services/dock_theme_settings.dart';
import 'dock_theme_styles.dart';
import 'performance_liquid_lens.dart';

class DockItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const DockItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// A single retained liquid lens containing lightweight dock items.
///
/// One lens preserves the refraction effect without the previous cost of a
/// separate shader and jelly simulation for every item.
class LiquidDock extends StatefulWidget {
  final List<DockItem> items;
  final double baseItemSize;
  final double maxItemSize;
  final double maxWidth;

  const LiquidDock({
    super.key,
    required this.items,
    this.baseItemSize = 48,
    this.maxItemSize = 72,
    this.maxWidth = 600,
  });

  @override
  State<LiquidDock> createState() => _LiquidDockState();
}

class _LiquidDockState extends State<LiquidDock> {
  final ScrollController _scrollController = ScrollController();
  double? _mouseX;
  bool _dockHovered = false;
  bool _isWarmingUp = false;

  @override
  void initState() {
    super.initState();
    _prewarmDockAnimation();
  }

  /// Pre-warms GPU shaders, layer composition, jelly physics, and proximity layout
  /// by sweeping mouse state across all dock items under the intro overlay.
  void _prewarmDockAnimation() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !DockThemeSettings.theme.value.usesLiquidGlass) return;

      final itemExtent = widget.baseItemSize + 10;
      final totalWidth = widget.items.length * itemExtent + 32;

      // Start prewarm sweep after initial layout stabilizes during intro screen
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;

      setState(() {
        _dockHovered = true;
        _isWarmingUp = true;
      });

      // Sweep hover position across all dock items so every item's shader/jelly texture is warmed up
      const steps = 12;
      for (int i = 0; i <= steps; i++) {
        await Future.delayed(const Duration(milliseconds: 30));
        if (!mounted || !_isWarmingUp) break;
        final progress = i / steps;
        setState(() {
          _mouseX = progress * totalWidth;
        });
      }

      await Future.delayed(const Duration(milliseconds: 40));

      if (mounted && _isWarmingUp) {
        setState(() {
          _dockHovered = false;
          _mouseX = null;
          _isWarmingUp = false;
        });
      }
    });
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (_scrollController.offset + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final effectiveMaxWidth = math.min(widget.maxWidth, screenWidth * 0.88);
    final itemExtent = widget.baseItemSize + 10;
    final contentWidth = widget.items.length * itemExtent + 32;
    final needsScrolling = contentWidth > effectiveMaxWidth;

    final dockContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (needsScrolling)
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, color: Colors.white70),
            onPressed: () => _scrollBy(-200),
          ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: needsScrolling ? effectiveMaxWidth : contentWidth,
          ),
          child: ScrollConfiguration(
            behavior: const MaterialScrollBehavior().copyWith(
              scrollbars: false,
              overscroll: false,
            ),
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(widget.items.length, (index) {
                  double proximity = 0;
                  if (_dockHovered && _mouseX != null) {
                    final arrowOffset = needsScrolling ? 48.0 : 0.0;
                    final center =
                        arrowOffset +
                        16 +
                        index * itemExtent +
                        itemExtent / 2 -
                        (_scrollController.hasClients
                            ? _scrollController.offset
                            : 0);
                    final distance = (_mouseX! - center).abs();
                    final range = widget.baseItemSize * 2.6;
                    if (distance < range) {
                      proximity = math
                          .pow(1 - distance / range, 1.45)
                          .toDouble();
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: _DockItemWidget(
                      item: widget.items[index],
                      size: widget.baseItemSize,
                      hoverSize: widget.maxItemSize,
                      proximity: proximity,
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
        if (needsScrolling)
          IconButton(
            icon: const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white70,
            ),
            onPressed: () => _scrollBy(200),
          ),
      ],
    );

    return ValueListenableBuilder<DockTheme>(
      valueListenable: DockThemeSettings.theme,
      builder: (context, theme, _) {
        Widget dockBody = Container(
          decoration: DockThemeStyles.dockInnerDecoration(theme),
          child: dockContent,
        );

        if (theme == DockTheme.carbonFiber) {
          dockBody = CarbonFiberPattern(
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: dockBody,
            ),
          );
        } else if (theme == DockTheme.retro90s) {
          dockBody = Padding(
            padding: const EdgeInsets.all(4),
            child: dockBody,
          );
        }

        final shell = DecoratedBox(
          decoration: DockThemeStyles.dockShellDecoration(theme),
          child: theme == DockTheme.liquidGlass
              ? PerformanceLiquidLens(
                  style: PerformanceGlassStyles.dock,
                  child: dockBody,
                )
              : dockBody,
        );

        return MouseRegion(
          onEnter: (_) {
            if (theme.usesLiquidGlass) {
              setState(() => _dockHovered = true);
            }
          },
          onHover: (event) {
            if (theme.usesLiquidGlass) {
              setState(() => _mouseX = event.localPosition.dx);
            }
          },
          onExit: (_) {
            if (_dockHovered || _mouseX != null) {
              setState(() {
                _dockHovered = false;
                _mouseX = null;
              });
            }
          },
          child: RepaintBoundary(child: shell),
        );
      },
    );
  }
}

class _DockItemWidget extends StatefulWidget {
  final DockItem item;
  final double size;
  final double hoverSize;
  final double proximity;

  const _DockItemWidget({
    required this.item,
    required this.size,
    required this.hoverSize,
    required this.proximity,
  });

  @override
  State<_DockItemWidget> createState() => _DockItemWidgetState();
}

class _DockItemWidgetState extends State<_DockItemWidget> {
  bool _pressed = false;
  bool _hovered = false;
  double _jellyValue = 0;

  Widget _icon(double size, DockTheme theme) => Tooltip(
    message: widget.item.label,
    child: Icon(
      widget.item.icon,
      size: size * 0.45,
      color: DockThemeStyles.dockIconColor(theme, hovered: _hovered),
    ),
  );

  void _setHover(bool value) {
    setState(() {
      _hovered = value;
      _jellyValue += value ? 10 : -10;
    });
  }

  void _setPressed(bool value) {
    setState(() {
      _pressed = value;
      _jellyValue += value ? 20 : -20;
    });
  }

  Widget _buildFullLiquid() {
    final hoverAmount = _hovered ? 1.0 : widget.proximity;
    final targetSize =
        widget.size + (widget.hoverSize - widget.size) * hoverAmount;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutBack,
        width: targetSize,
        height: targetSize,
        child: Listener(
          onPointerDown: (_) => _setPressed(true),
          onPointerUp: (_) => _setPressed(false),
          onPointerCancel: (_) => _setPressed(false),
          child: LiquidGlassJelly(
            value: _jellyValue,
            width: targetSize,
            height: targetSize,
            config: const LiquidGlassJellyConfig(
              style: LiquidGlassJellyStyle.squashStretch,
              stiffness: 180,
              damping: 12,
            ),
            child: SizedBox.square(
              dimension: targetSize,
              child: LiquidGlassButton.custom(
                padding: EdgeInsets.zero,
                style: const LiquidGlassStyle(
                  shape: LiquidGlassShape.squircle(
                    cornerRadius: 22,
                    clipQuality: LiquidGlassClipQuality.exact,
                    borderWidth: 1.5,
                    lightIntensity: 1.5,
                    lightColor: Color(0xEFFFFFFF),
                    lightDirection: 115,
                    borderType: OpticalBorder(
                      borderSaturation: 1.6,
                      ambientIntensity: 1.2,
                      borderSolidity: 0.2,
                      lightSpread: 0.72,
                    ),
                  ),
                  appearance: LiquidGlassAppearance(
                    color: Color(0x20FFFFFF),
                    saturation: 1.12,
                    blur: LiquidGlassBlur(sigmaX: 2, sigmaY: 2),
                  ),
                  refraction: LiquidGlassRefraction(
                    magnification: 1.05,
                    chromaticAberration: 0.0025,
                    refractionType: OpticalRefraction(
                      refraction: 1.52,
                      refractionWidth: 22,
                      depth: 0.75,
                    ),
                  ),
                ),
                onPressed: widget.item.onTap,
                child: AnimatedScale(
                  scale: _pressed ? 0.76 : (_hovered ? 1.18 : 1),
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutBack,
                  child: _icon(targetSize, DockTheme.liquidGlass),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptimized(DockTheme theme) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.item.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.92 : (_hovered ? 1.08 : 1),
          duration: Duration(
            milliseconds: theme == DockTheme.retro90s ? 80 : 110,
          ),
          curve: theme == DockTheme.retro90s
              ? Curves.linear
              : Curves.easeOut,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: DockThemeStyles.dockItemDecoration(
              theme,
              hovered: _hovered,
              pressed: _pressed,
            ),
            child: _icon(widget.size, theme),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<DockTheme>(
        valueListenable: DockThemeSettings.theme,
        builder: (context, theme, _) =>
            theme.usesLiquidGlass ? _buildFullLiquid() : _buildOptimized(theme),
      ),
    );
  }
}

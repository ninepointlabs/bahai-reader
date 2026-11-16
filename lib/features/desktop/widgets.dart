import 'package:flutter/material.dart';

import '../../core/app/theme.dart';

/// Small pieces in the GTK app's style, shared by the desktop views.

const dimSize = 13.0;

TextStyle dimStyle(BuildContext context, {double size = dimSize}) =>
    TextStyle(fontSize: size, color: ReaderColors.of(context).dim, fontFeatures: const [FontFeature.tabularFigures()]);

/// A flat icon button for a header bar.
class HeaderButton extends StatelessWidget {
  const HeaderButton({super.key, required this.icon, required this.tooltip, this.onPressed, this.color});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 20, color: color),
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(minimumSize: const Size(36, 34), padding: const EdgeInsets.all(6)),
      );
}

/// A centred title with an optional dim subtitle, like libadwaita's AdwWindowTitle.
class WindowTitle extends StatelessWidget {
  const WindowTitle({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(title,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
      if (sub != null && sub.isNotEmpty)
        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: dimStyle(context, size: 12.5)),
    ]);
  }
}

/// A header bar: start widgets, a centred title and end widgets, with a hairline below.
class HeaderBar extends StatelessWidget {
  const HeaderBar({super.key, this.start = const [], required this.title, this.end = const [], this.color});
  final List<Widget> start;
  final Widget title;
  final List<Widget> end;
  final Color? color;

  static const height = 46.0;

  @override
  Widget build(BuildContext context) {
    final p = ReaderColors.of(context);
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: color ?? p.background, border: Border(bottom: BorderSide(color: p.selection))),
      child: NavigationToolbar(
        leading: Row(mainAxisSize: MainAxisSize.min, children: start),
        middle: title,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: end),
        middleSpacing: 8,
      ),
    );
  }
}

/// A bordered card that reacts to the pointer, like a libadwaita `.card` button.
class CardButton extends StatefulWidget {
  const CardButton({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(12), this.tooltip});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final String? tooltip;

  @override
  State<CardButton> createState() => _CardButtonState();
}

class _CardButtonState extends State<CardButton> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final p = ReaderColors.of(context);
    Widget card = MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: hover && widget.onTap != null ? mix(p.card, p.foreground, 0.04) : p.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.foreground.withValues(alpha: 0.08)),
          ),
          child: widget.child,
        ),
      ),
    );
    if (widget.tooltip != null) card = Tooltip(message: widget.tooltip!, child: card);
    return Semantics(button: widget.onTap != null, child: card);
  }
}

/// A row in the sidebar: rounded, filled when hovered or current.
class SideRow extends StatefulWidget {
  const SideRow({super.key, required this.child, this.onTap, this.selected = false, this.padding, this.tooltip});
  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final EdgeInsets? padding;
  final String? tooltip;

  @override
  State<SideRow> createState() => _SideRowState();
}

class _SideRowState extends State<SideRow> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final p = ReaderColors.of(context);
    final fill = widget.selected
        ? p.foreground.withValues(alpha: 0.1)
        : hover
            ? p.foreground.withValues(alpha: 0.06)
            : Colors.transparent;
    Widget row = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(6)),
          child: DefaultTextStyle.merge(
            style: TextStyle(fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400),
            child: widget.child,
          ),
        ),
      ),
    );
    if (widget.tooltip != null) row = Tooltip(message: widget.tooltip!, waitDuration: const Duration(seconds: 1), child: row);
    return Semantics(button: true, selected: widget.selected, child: row);
  }
}

/// A thin, rounded progress bar in the accent colour.
class Bar extends StatelessWidget {
  const Bar({super.key, required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: value.clamp(0, 1), minHeight: 7),
      );
}

/// Shows [builder]'s content in a small floating panel pointing at [anchor] (global coordinates): above it when there
/// is room, else below. Tapping outside or Esc closes it. Like a GtkPopover over the text.
Future<T?> showPopoverAt<T>(BuildContext context, Rect anchor, WidgetBuilder builder, {bool below = false}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 90),
    pageBuilder: (dialogContext, _, _) {
      final p = ReaderColors.of(dialogContext);
      return CustomSingleChildLayout(
        delegate: _PopoverLayout(anchor, below: below),
        child: Material(
          color: p.raised,
          elevation: 6,
          shadowColor: Colors.black54,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.foreground.withValues(alpha: 0.12))),
          child: Builder(builder: builder),
        ),
      );
    },
    transitionBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
  );
}

class _PopoverLayout extends SingleChildLayoutDelegate {
  _PopoverLayout(this.anchor, {this.below = false});
  final Rect anchor;
  final bool below;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(Size(constraints.maxWidth - 24, constraints.maxHeight - 24));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = (anchor.center.dx - child.width / 2).clamp(12.0, size.width - child.width - 12);
    final above = anchor.top - child.height - 8;
    final under = (anchor.bottom + 8).clamp(12.0, size.height - child.height - 12);
    final y = below || above < 12 ? under : above;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PopoverLayout old) => old.anchor != anchor || old.below != below;
}

/// A short message at the bottom of the window, like a libadwaita toast.
void toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text, textAlign: TextAlign.center), duration: const Duration(seconds: 2)));
}

/// An index in a card: one row per entry (a book, a prayer category, a prayer), its title in the reading face and a
/// detail on the right. Shared by the Library and the Prayers index.
class IndexCard extends StatelessWidget {
  const IndexCard({super.key, required this.entries});
  final List<IndexEntry> entries;

  @override
  Widget build(BuildContext context) {
    final p = ReaderColors.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.foreground.withValues(alpha: 0.08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final e in entries)
          SideRow(
            tooltip: e.tooltip,
            selected: e.selected,
            onTap: e.onTap,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: Text(
                  e.title,
                  maxLines: e.lines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: readingFonts.first,
                    fontFamilyFallback: readingFonts.sublist(1),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(e.detail, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: dimStyle(context)),
              ),
            ]),
          ),
      ]),
    );
  }
}

class IndexEntry {
  const IndexEntry(this.title, this.detail, this.onTap, {this.tooltip, this.selected = false, this.lines = 1});
  final String title, detail;
  final VoidCallback onTap;
  final String? tooltip;
  final bool selected;
  final int lines;
}

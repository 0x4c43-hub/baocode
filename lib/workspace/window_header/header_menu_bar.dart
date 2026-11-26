import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chat/floating/floating_layer.dart';
import '../../chat/floating/floating_placement.dart';
import '../../chat/floating/floating_registry.dart';
import '../../chat/widgets/hover_builder.dart';
import '../../l10n/l10n.dart';
import '../../l10n/custom_strings.dart';
import '../../sidebar/sidebar.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'header_menu.dart';

/// The header's menu bar: a label for each menu, opening its commands under
/// it. Once one is open, resting on another opens that one, as the bars the
/// platforms draw themselves do.
///
/// [compact], the labels fold into one button, as an editor's narrow window
/// has it: its list of the menus, each opening its commands beside it.
class HeaderMenuBar extends StatefulWidget {
  const HeaderMenuBar({super.key, required this.items, this.compact = false});

  /// What a menu holds, asked for when it is opened: what is ticked and the
  /// recent projects are the app's, and change as it does.
  final List<HeaderMenuItem> Function(HeaderMenu menu) items;

  final bool compact;

  @override
  State<HeaderMenuBar> createState() => _HeaderMenuBarState();
}

class _HeaderMenuBarState extends State<HeaderMenuBar> {
  /// The menu whose commands are down, if any.
  HeaderMenu? _open;

  /// Compact, whether the list of the menus is down ([_open], the one of
  /// them whose commands are beside it).
  bool _listOpen = false;

  /// One group for the whole bar, so that a click on a label of it counts as
  /// inside and does not close what that label opens.
  final Object _tapRegion = Object();

  /// The open submenu's item, and its parents (for a nested one).
  List<HeaderMenuItem> _submenuPath = [];

  // Items are rebuilt as the menu opens (what is ticked changes), so the
  // path is matched by label, not by identity.
  bool _isSubmenuOpen(HeaderMenuItem item) =>
      _submenuPath.isNotEmpty && _submenuPath.last.label == item.label;

  void _openMenu(HeaderMenu menu) {
    setState(() {
      _open = menu;
      _submenuPath.clear();
    });
    // Esc puts them away; the focused input asks the registry first (see
    // FloatingRegistry.handleKey).
    FloatingRegistry.openPopover(this, _close, onKey: _handleKey);
  }

  void _openList() {
    setState(() => _listOpen = true);
    FloatingRegistry.openPopover(this, _close, onKey: _handleKey);
  }

  void _close() {
    if (_open == null && !_listOpen) return;
    setState(() {
      _open = null;
      _listOpen = false;
      _submenuPath.clear();
    });
    FloatingRegistry.closePopover(this);
  }

  void _openSubmenu(HeaderMenuItem item) {
    if (_isSubmenuOpen(item)) return;
    setState(() => _submenuPath = [item]);
  }

  @override
  void didUpdateWidget(HeaderMenuBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Folded or unfolded, what was down goes.
    if (oldWidget.compact != widget.compact) _close();
  }

  KeyEventResult? _handleKey(KeyEvent event) =>
      event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape
      ? KeyEventResult.handled
      : null;

  @override
  Widget build(BuildContext context) {
    if (widget.compact) return _buildFolded();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (final menu in HeaderMenu.values) _buildLabel(menu)],
    );
  }

  /// The one button, and the menus' list under it.
  Widget _buildFolded() {
    return FloatingLayer(
      visible: _listOpen,
      placement: (side: FloatingSide.bottom, align: FloatingAlign.start),
      gap: 2,
      tapRegionGroupId: _tapRegion,
      onTapOutside: _close,
      builder: (context) => _panel(
        width: 160,
        children: [for (final menu in HeaderMenu.values) _buildEntry(menu)],
      ),
      child: TapRegion(
        groupId: _tapRegion,
        child: SidebarIconButton(
          icon: Codicons.menu,
          tooltip: context.l10n.menuApplication,
          onTap: () => _listOpen ? _close() : _openList(),
        ),
      ),
    );
  }

  /// A menu in the list: its commands beside it, as the pointer rests on it
  /// (or it is clicked).
  Widget _buildEntry(HeaderMenu menu) {
    final open = _open == menu;
    return FloatingLayer(
      visible: open,
      placement: (side: FloatingSide.right, align: FloatingAlign.start),
      gap: 6,
      tapRegionGroupId: _tapRegion,
      builder: (context) => _buildCommands(menu),
      child: MouseRegion(
        onEnter: (_) => setState(() => _open = menu),
        child: _MenuRow(
          item: HeaderMenuItem(
            menu.localizedLabel(context.l10n, context.custom),
            onSelected: () {},
          ),
          selected: open,
          submenu: true,
          onSelected: (_) => setState(() => _open = menu),
        ),
      ),
    );
  }

  Widget _buildLabel(HeaderMenu menu) {
    final open = _open == menu;
    final colors = themeColors;
    return FloatingLayer(
      visible: open,
      placement: (side: FloatingSide.bottom, align: FloatingAlign.start),
      gap: 2,
      tapRegionGroupId: _tapRegion,
      onTapOutside: _close,
      builder: (context) => _buildCommands(menu),
      child: TapRegion(
        groupId: _tapRegion,
        child: MouseRegion(
          // Another menu is down: resting here takes it there, as the
          // system's bars do.
          onEnter: (_) {
            if (_open != null && !open) _openMenu(menu);
          },
          child: HoverBuilder(
            cursor: SystemMouseCursors.basic,
            // As upstream's menubar in the title bar.
            builder: (context, hovered) {
              final selected = hovered || open;
              final outline = selected
                  ? colors.get('menubar.selectionBorder')
                  : null;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => open ? _close() : _openMenu(menu),
                child: Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? colors['menubar.selectionBackground']
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  foregroundDecoration: outline == null
                      ? null
                      : BoxDecoration(
                          border: Border.all(color: outline),
                          borderRadius: BorderRadius.circular(5),
                        ),
                  child: Text(
                    menu.localizedLabel(context.l10n, context.custom),
                    style: TextStyle(
                      color:
                          colors[selected
                              ? 'menubar.selectionForeground'
                              : 'titleBar.activeForeground'],
                      fontSize: 12.5,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// The menu's commands.
  Widget _buildCommands(HeaderMenu menu) => _buildPanel(widget.items(menu));

  /// A panel of entries, each command or a submenu that opens to its right.
  Widget _buildPanel(List<HeaderMenuItem> items, {bool nested = false}) {
    return _panel(
      width: 224,
      children: [
        for (final item in items)
          if (item.rule)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              child: SizedBox(
                height: 1,
                child: ColoredBox(
                  color: themeColors['menu.separatorBackground'],
                ),
              ),
            )
          else if (item.submenu case final submenu?)
            _SubmenuRow(
              item: item,
              selected: _isSubmenuOpen(item),
              panel: (context) => _buildPanel(submenu, nested: true),
              onEnter: () => _openSubmenu(item),
              onSelected: () => _openSubmenu(item),
              tapRegion: _tapRegion,
            )
          else
            _MenuRow(item: item, onSelected: nested ? _selectNested : _select),
      ],
    );
  }

  void _selectNested(HeaderMenuItem item) {
    _close();
    item.onSelected?.call();
  }

  /// A panel of the same make as the app's other menus (see SidebarMenu).
  Widget _panel({required double width, required List<Widget> children}) {
    final colors = themeColors;
    return Container(
      width: width,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors['menu.background'],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors['menu.border']),
        boxShadow: [
          BoxShadow(
            color: colors['widget.shadow'],
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  void _select(HeaderMenuItem item) {
    _close();
    item.onSelected?.call();
  }
}

/// One command of a menu: its label, a tick when it is on, its shortcut;
/// or, [submenu], a menu of the folded bar's list, its arrow at the right.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.item,
    required this.onSelected,
    this.selected = false,
    this.submenu = false,
  });

  final HeaderMenuItem item;
  final ValueChanged<HeaderMenuItem> onSelected;

  /// Shown as hovered: the menu whose commands are open beside it.
  final bool selected;
  final bool submenu;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return HoverBuilder(
      cursor: SystemMouseCursors.basic,
      builder: (context, hovered) {
        hovered = hovered || selected;
        // As upstream's menus: the hovered item selected.
        final foreground =
            colors[hovered ? 'menu.selectionForeground' : 'menu.foreground'];
        final outline = hovered ? colors.get('menu.selectionBorder') : null;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelected(item),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: hovered
                  ? colors['menu.selectionBackground']
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            foregroundDecoration: outline == null
                ? null
                : BoxDecoration(
                    border: Border.all(color: outline),
                    borderRadius: BorderRadius.circular(5),
                  ),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  child: item.checked
                      ? Icon(Icons.check_rounded, size: 14, color: foreground)
                      : item.leading?.call(foreground),
                ),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: foreground, fontSize: 12.5),
                  ),
                ),
                if (submenu)
                  Icon(Codicons.chevronRight, size: 14, color: foreground)
                else if (item.shortcut case final shortcut?) ...[
                  const SizedBox(width: 16),
                  Text(
                    shortcut,
                    style: TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A command that opens a submenu beside it as the pointer rests on it or it
/// is tapped (the folded bar's [HeaderMenu] entries do the same).
class _SubmenuRow extends StatelessWidget {
  const _SubmenuRow({
    required this.item,
    required this.selected,
    required this.panel,
    required this.onEnter,
    required this.onSelected,
    required this.tapRegion,
  });

  final HeaderMenuItem item;
  final bool selected;
  final WidgetBuilder panel;
  final VoidCallback onEnter;
  final VoidCallback onSelected;
  final Object tapRegion;

  @override
  Widget build(BuildContext context) {
    return FloatingLayer(
      visible: selected,
      placement: (side: FloatingSide.right, align: FloatingAlign.start),
      gap: 6,
      tapRegionGroupId: tapRegion,
      builder: panel,
      child: MouseRegion(
        onEnter: (_) => onEnter(),
        child: _MenuRow(
          item: item,
          selected: selected,
          submenu: true,
          onSelected: (_) => onSelected(),
        ),
      ),
    );
  }
}

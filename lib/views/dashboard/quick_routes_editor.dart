import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/quick_route_helpers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

void _saveRoutes(
  WidgetRef ref,
  int profileId,
  List<QuickRouteShortcut> routes,
) {
  if (!ref.read(profilesProvider).any((profile) => profile.id == profileId)) {
    return;
  }
  ref
      .read(appSettingProvider.notifier)
      .update(
        (state) => state.copyWith(
          profileQuickRoutes: {
            ...state.profileQuickRoutes,
            '$profileId': routes,
          },
        ),
      );
}

Future<void> editQuickRoute(
  BuildContext context,
  WidgetRef ref,
  int profileId,
  QuickRouteShortcut? route,
) async {
  final initial = route ?? QuickRouteShortcut(id: uuidV4);
  final value = await showFormSheet<QuickRouteShortcut>(
    context: context,
    builder: (_) => _QuickRouteForm(profileId: profileId, route: initial),
  );
  if (value == null || !context.mounted) return;
  final routes = quickRoutesFor(ref.read(appSettingProvider), profileId);
  final index = routes.indexWhere((item) => item.id == value.id);
  final updated = [...routes];
  if (index < 0) {
    updated.add(value);
  } else {
    updated[index] = value;
  }
  _saveRoutes(ref, profileId, updated);
}

class QuickRoutesEditor extends ConsumerWidget {
  const QuickRoutesEditor({super.key, required this.profileId});

  final int profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListEditorPage<QuickRouteShortcut, String>(
      title: context.appLocalizations.quickRoutes,
      itemsOf: (ref) =>
          quickRoutesFor(ref.watch(appSettingProvider), profileId),
      idOf: (route) => route.id,
      searchFieldsOf: (route) => [
        quickRouteLabel(context, route),
        route.groupName,
      ],
      emptyLabel: context.appLocalizations.quickRoutesEmpty,
      onAdd: () => editQuickRoute(context, ref, profileId, null),
      onReorder: (from, to) {
        final routes = quickRoutesFor(ref.read(appSettingProvider), profileId);
        _saveRoutes(ref, profileId, routes.copyAndReorder(from, to));
      },
      onDelete: (ids) {
        final routes = quickRoutesFor(ref.read(appSettingProvider), profileId);
        _saveRoutes(
          ref,
          profileId,
          routes.where((route) => !ids.contains(route.id)).toList(),
        );
      },
      menuItemsOf: (route) => [
        CommonPopupMenuItem(
          glyph: AppGlyphs.edit,
          label: context.appLocalizations.edit,
          onPressed: () => editQuickRoute(context, ref, profileId, route),
        ),
      ],
      itemBuilder: (context, ref, route, index, editing, selected, toggle) {
        final title = quickRouteLabel(context, route);
        return DecorationListItem(
          title: Text(title),
          subtitle: Text(
            route.groupName.isEmpty
                ? context.appLocalizations.quickRouteAutomatic
                : route.groupName,
          ),
          isSelected: selected,
          trailing: editing
              ? Checkbox(value: selected, onChanged: (_) => toggle())
              : const GlyphIcon(AppGlyphs.chevronForward),
          onPressed: editing
              ? toggle
              : () => editQuickRoute(context, ref, profileId, route),
        );
      },
    );
  }
}

class _QuickRouteForm extends ConsumerStatefulWidget {
  const _QuickRouteForm({required this.profileId, required this.route});

  final int profileId;
  final QuickRouteShortcut route;

  @override
  ConsumerState<_QuickRouteForm> createState() => _QuickRouteFormState();
}

class _QuickRouteFormState extends ConsumerState<_QuickRouteForm> {
  late final _label = TextEditingController(text: widget.route.label);
  late var _groupName = widget.route.groupName;
  var _attempted = false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _chooseGroup() async {
    final name = await showSheet<String>(
      context: context,
      builder: (sheetContext) => Consumer(
        builder: (_, ref, _) {
          final groups = ref.watch(currentProfileIdProvider) == widget.profileId
              ? selectableQuickGroups(ref.watch(groupsProvider))
              : const <Group>[];
          return SelectionSheet<String>(
            title: context.appLocalizations.selectProxyGroup,
            sections: [
              SelectionSection(
                items: groups.map((group) => group.name).toList(),
              ),
            ],
            labelBuilder: (name) => name,
            selectedOf: (_) => _groupName,
            onSelected: (name) => Navigator.of(sheetContext).pop(name),
          );
        },
      ),
    );
    if (name != null && mounted) setState(() => _groupName = name);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final builtIn = defaultQuickRoutes.any(
      (route) => route.id == widget.route.id,
    );
    final invalid = _attempted && !builtIn && _label.text.trim().isEmpty;
    return FormPage(
      title: l.quickRoutes,
      error: invalid ? l.emptyTip(l.name) : null,
      onSave: () {
        if (!builtIn && _label.text.trim().isEmpty) {
          setState(() => _attempted = true);
          return;
        }
        Navigator.of(context).pop(
          widget.route.copyWith(
            label: _label.text.trim(),
            groupName: _groupName,
          ),
        );
      },
      children: [
        generateSection(
          items: [
            FormRow(
              title: l.name,
              invalid: invalid,
              trailing: FormRowTextField(
                controller: _label,
                hintText: builtIn
                    ? quickRouteLabel(context, widget.route.copyWith(label: ''))
                    : l.required,
                inputFormatters: TextInputLimits.limit(TextInputLimits.name),
                onChanged: (_) {
                  if (_attempted) setState(() {});
                },
              ),
            ),
            FormRow(
              title: l.proxyGroup,
              onPressed: _chooseGroup,
              trailing: Text(
                _groupName.isEmpty ? l.selectProxyGroup : _groupName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

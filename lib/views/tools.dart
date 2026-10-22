import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/about.dart';
import 'package:fl_clash/views/access.dart';
import 'package:fl_clash/views/backup_and_restore.dart';
import 'package:fl_clash/views/config/general.dart';
import 'package:fl_clash/views/config/dns.dart';
import 'package:fl_clash/views/config/network.dart';
import 'package:fl_clash/views/config/rules.dart';
import 'package:fl_clash/views/config/scripts.dart';
import 'package:fl_clash/views/hotkey.dart';
import 'package:fl_clash/views/settings/navigation_settings.dart';
import 'package:fl_clash/views/settings/search_destination.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/advanced.dart';
import 'config/custom_resources.dart';
import 'developer.dart';
import 'disclaimer.dart';
import 'theme.dart';

class ToolsView extends ConsumerStatefulWidget {
  const ToolsView({super.key, this.settingsOnly = false});

  final bool settingsOnly;

  @override
  ConsumerState<ToolsView> createState() => _ToolViewState();
}

class _ToolViewState extends ConsumerState<ToolsView> {
  var _query = SearchQuery('');

  Widget? _section(
    String title,
    List<({List<String> terms, Widget item})> entries,
  ) {
    final items = entries
        .where((entry) => _query.matches(entry.terms))
        .map((entry) => entry.item)
        .toList();
    return items.isEmpty ? null : generateSection(title: title, items: items);
  }

  Widget _buildNavigationMenuItem(NavigationItem navigationItem) {
    return ListItem.open(
      leading: GlyphIcon(navigationItem.glyph),
      title: Text(navigationItem.label.label),
      widget: navigationItem.builder(context),
      forceFull: navigationItem.modes.contains(NavigationItemMode.moreFull),
    );
  }

  Widget? _getOtherList(bool enableDeveloperMode) {
    final l = context.appLocalizations;
    return _section(l.other, [
      (terms: [l.disclaimer], item: const _DisclaimerItem()),
      if (enableDeveloperMode)
        (terms: [l.developerMode], item: const _DeveloperItem()),
      (terms: [l.about, l.checkUpdate, 'FlClash'], item: const _InfoItem()),
    ]);
  }

  Widget? _getSettingList() {
    final l = context.appLocalizations;
    if (_query.isNotEmpty) return _searchSettings();
    return _section(l.settings, [
      (terms: [l.language], item: const _LocaleItem()),
      (
        terms: [l.appearanceNavigation],
        item: ListItem.open(
          leading: const GlyphIcon(AppGlyphs.customize),
          title: Text(l.appearanceNavigation),
          widget: const NavigationSettingsView(),
        ),
      ),
      (
        terms: [
          l.theme,
          l.themeMode,
          l.liquidGlass,
          l.fontFamily,
          l.tabAnimation,
        ],
        item: const _ThemeItem(),
      ),
      (
        terms: [l.backupAndRestore, l.backup, l.restore, 'WebDAV'],
        item: const _BackupItem(),
      ),
      if (system.isDesktop)
        (terms: [l.hotkeyManagement], item: const _HotkeyItem()),
      if (system.isAndroid)
        (terms: [l.accessControl], item: const _AccessItem()),
      (
        terms: [l.advancedConfig, 'DNS', l.network, l.rules, l.script],
        item: const _AdvancedConfigItem(),
      ),
      (terms: [l.customProfileResources], item: const _CustomResourcesItem()),
      (
        terms: [l.general, l.systemProxy, l.tun, l.authentication, l.allowLan],
        item: const _GeneralItem(),
      ),
    ]);
  }

  Widget? _searchSettings() {
    final l = context.appLocalizations;
    final items = <Widget>[];
    void add(
      String id,
      String title,
      List<String> path,
      Widget page, {
      String? target,
      List<String> terms = const [],
    }) {
      if (!_query.matches([title, ...path, ...terms])) return;
      items.add(
        ListItem.open(
          key: ValueKey('setting-result-$id'),
          title: Text(title),
          subtitle: Text(path.join(' › ')),
          widget: SettingSearchDestination(
            target: target ?? title,
            child: page,
          ),
        ),
      );
    }

    if (_query.matches([l.language])) items.add(const _LocaleItem());
    add(
      'appearance',
      l.appearanceNavigation,
      [l.settings],
      const NavigationSettingsView(),
      target: l.uiDensity,
    );
    add(
      'density',
      l.uiDensity,
      [l.settings, l.appearanceNavigation],
      const NavigationSettingsView(),
      terms: [l.compact, l.comfortable],
    );
    if (system.isDesktop) {
      add('sidebar', l.pinnedSidebarTools, [
        l.settings,
        l.appearanceNavigation,
      ], const NavigationSettingsView());
    }
    for (final (id, title) in [
      ('theme-mode', l.themeMode),
      ('glass', l.liquidGlass),
      ('font', l.fontFamily),
      ('animation', l.tabAnimation),
      ('text-scale', l.textScale),
      ('theme-color', l.themeColor),
    ]) {
      add(id, title, [l.settings, l.theme], const ThemeView());
    }
    add(
      'webdav',
      'WebDAV',
      [l.settings, l.backupAndRestore, l.remote],
      const BackupAndRestore(),
      target: l.remote,
      terms: [l.backup, l.restore],
    );
    add('restore-strategy', l.restoreStrategy, [
      l.settings,
      l.backupAndRestore,
      l.options,
    ], const BackupAndRestore());
    if (system.isDesktop) {
      add('hotkeys', l.hotkeyManagement, [l.settings], const HotKeyView());
    }
    if (system.isAndroid) {
      add('access', l.accessControl, [l.settings], const AccessView());
    }
    add('dns', 'DNS', [l.settings, l.advancedConfig], const DnsView());
    add(
      'rules',
      l.addedRules,
      [l.settings, l.advancedConfig],
      const AddedRulesView(),
      terms: [l.rules],
    );
    add('scripts', l.script, [
      l.settings,
      l.advancedConfig,
    ], const ScriptsView());
    final network = BaseScaffold(
      title: l.network,
      body: const NetworkListView(),
    );
    for (final (id, title) in [
      ('system-proxy', l.systemProxy),
      ('tun', system.isAndroid ? 'VPN' : l.tun),
      ('tun-stack', l.stackMode),
      ('bypass', l.bypassDomain),
    ]) {
      add(id, title, [l.settings, l.advancedConfig, l.network], network);
    }
    for (final (id, title) in [
      if (system.isDesktop) ...[
        ('auto-launch', l.autoLaunch),
        ('silent-launch', l.silentLaunch),
      ],
      ('auto-run', l.autoRun),
      ('minimize', l.minimizeOnExit),
      ('certificate', l.checkCertificate),
      ('auto-update', l.autoCheckUpdate),
      ('user-agent', l.userAgent),
      ('port', l.port),
      ('allow-lan', l.allowLan),
      ('controller', l.externalController),
      ('authentication', l.authentication),
      ('test-url', l.testUrl),
      ('close-connections', l.autoCloseConnections),
      ('log-level', l.logLevel),
      ('logs', l.logcat),
      ('hosts', 'Hosts'),
      ('ipv6', 'IPv6'),
    ]) {
      add(id, title, [l.settings, l.general], const GeneralView());
    }
    add('custom-resources', l.customProfileResources, [
      l.settings,
    ], const CustomResourcesView());
    return items.isEmpty
        ? null
        : generateSection(title: l.settings, items: items);
  }

  @override
  Widget build(BuildContext context) {
    final developerMode = ref.watch(
      appSettingProvider.select((state) => state.developerMode),
    );
    final moreItems = ref.watch(moreToolsSelectorStateProvider).navigationItems;
    final items = <Widget>[
      if (!widget.settingsOnly)
        ?_section(context.appLocalizations.more, [
          for (final item in moreItems)
            (terms: [item.label.label], item: _buildNavigationMenuItem(item)),
        ]),
      if (widget.settingsOnly || !system.isDesktop) ...[
        ?_getSettingList(),
        ?_getOtherList(developerMode),
      ],
    ];
    return CommonScaffold(
      title: widget.settingsOnly
          ? context.appLocalizations.settings
          : context.appLocalizations.tools,
      searchState: AppBarSearchState(
        onSearch: (value) => setState(() => _query = SearchQuery(value)),
      ),
      body: Builder(
        builder: (context) => NullStatusSwitcher(
          isEmpty: items.isEmpty,
          isSearching: _query.isNotEmpty,
          nullStatus: NullStatus(
            label: context.appLocalizations.nullTip(
              context.appLocalizations.settings,
            ),
          ),
          child: ListView.builder(
            key: toolsStoreKey,
            itemCount: items.length,
            itemBuilder: (_, index) => items[index],
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: context.appBarInset,
              bottom: 20 + BottomInsetScope.of(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _LocaleItem extends ConsumerWidget {
  const _LocaleItem();

  String _getLocaleString(BuildContext context, Locale? locale) {
    if (locale == null) return context.appLocalizations.defaultText;
    return locale.label;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(
      appSettingProvider.select((state) => state.locale),
    );
    final currentLocale = getLocaleForString(locale);
    return ListItem<Locale?>.options(
      leading: const GlyphIcon(AppGlyphs.language),
      title: Text(context.appLocalizations.language),
      options: [null, ...AppLocalizations.delegate.supportedLocales],
      onChanged: (Locale? locale) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(locale: locale?.toString()));
      },
      textBuilder: (locale) => _getLocaleString(context, locale),
      value: currentLocale,
    );
  }
}

class _ThemeItem extends StatelessWidget {
  const _ThemeItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.paintbrush),
      title: Text(context.appLocalizations.theme),
      widget: const ThemeView(),
    );
  }
}

class _BackupItem extends StatelessWidget {
  const _BackupItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.cloudSync),
      title: Text(context.appLocalizations.backupAndRestore),
      widget: const BackupAndRestore(),
    );
  }
}

class _HotkeyItem extends StatelessWidget {
  const _HotkeyItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.keyboard),
      title: Text(context.appLocalizations.hotkeyManagement),
      widget: const HotKeyView(),
    );
  }
}

class _AccessItem extends StatelessWidget {
  const _AccessItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.appsList),
      title: Text(context.appLocalizations.accessControl),
      widget: const AccessView(),
    );
  }
}

class _GeneralItem extends StatelessWidget {
  const _GeneralItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.settings),
      title: Text(context.appLocalizations.general),
      widget: const GeneralView(),
    );
  }
}

class _AdvancedConfigItem extends StatelessWidget {
  const _AdvancedConfigItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.wrench),
      title: Text(context.appLocalizations.advancedConfig),
      widget: const AdvancedConfigView(),
    );
  }
}

class _CustomResourcesItem extends StatelessWidget {
  const _CustomResourcesItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.customize),
      title: Text(context.appLocalizations.customProfileResources),
      widget: const CustomResourcesView(),
    );
  }
}

class _DisclaimerItem extends StatelessWidget {
  const _DisclaimerItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.gavel),
      title: Text(context.appLocalizations.disclaimer),
      widget: const DisclaimerView(),
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.info),
      title: Text(context.appLocalizations.about),
      widget: const AboutView(),
    );
  }
}

class _DeveloperItem extends StatelessWidget {
  const _DeveloperItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.cpu),
      title: Text(context.appLocalizations.developerMode),
      widget: const DeveloperView(),
    );
  }
}

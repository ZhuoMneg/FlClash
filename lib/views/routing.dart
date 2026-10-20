import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/profiles/custom/rules.dart';
import 'package:fl_clash/views/profiles/extend/extend.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class RoutingView extends ConsumerWidget {
  const RoutingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    if (profile == null) {
      return CommonScaffold(
        title: context.appLocalizations.routing,
        body: Center(
          child: TextButton(
            onPressed: () => ref.read(currentPageLabelProvider.notifier).value =
                PageLabel.profiles,
            child: Text(context.appLocalizations.profiles),
          ),
        ),
      );
    }
    return switch (profile.type) {
      ProfileType.custom => CustomRulesView(
        profile.id,
        key: ValueKey(profile.id),
      ),
      _ => ExtendView(profileId: profile.id, key: ValueKey(profile.id)),
    };
  }
}

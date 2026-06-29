import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/localization/strings.dart';

const _ltscWarningPrefKey = 'mirror_ltsc_expert_warning_hidden';
bool _acceptedThisSession = false;

Future<bool> showLtscExpertWarning(BuildContext context) async {
  if (_acceptedThisSession) return true;

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_ltscWarningPrefKey) ?? false) {
    _acceptedThisSession = true;
    return true;
  }

  if (!context.mounted) return false;

  var doNotShowAgain = false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(tr(ctx, 'mirror_ltsc_warning_title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(ctx, 'mirror_ltsc_warning_message')),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: doNotShowAgain,
                onChanged: (value) =>
                    setState(() => doNotShowAgain = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(tr(ctx, 'tool_warning_do_not_show_again')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr(ctx, 'tool_warning_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr(ctx, 'tool_warning_continue')),
          ),
        ],
      ),
    ),
  );

  if (confirmed == true && doNotShowAgain) {
    await prefs.setBool(_ltscWarningPrefKey, true);
  }

  if (confirmed == true) {
    _acceptedThisSession = true;
  }

  return confirmed == true;
}

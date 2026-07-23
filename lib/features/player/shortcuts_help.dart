import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// One keyboard shortcut: the key cap(s) to show and what they do. [keys] are
/// intentionally left as literal symbols (Space, ←, `[`) — key caps read the
/// same in any language — while [description] is localized.
class _Shortcut {
  final List<String> keys;
  final String description;
  const _Shortcut(this.keys, this.description);
}

/// Shows the player keyboard-shortcuts reference. Opened by the help button in
/// the player controls or by pressing `?`. Lists only shortcuts that actually
/// exist in the player's key handler; [isVod] hides the speed row for live
/// streams (where playback speed doesn't apply), matching the key handler.
Future<void> showShortcutsHelp(BuildContext context, {required bool isVod}) {
  final l = AppLocalizations.of(context)!;
  final shortcuts = <_Shortcut>[
    _Shortcut(const ['Space'], l.shortcutPlayPause),
    _Shortcut(const ['←', '→'], l.shortcutSeek),
    _Shortcut(const ['↑', '↓'], l.shortcutVolume),
    if (isVod) _Shortcut(const ['[', ']'], l.shortcutSpeed),
    if (!isVod) _Shortcut(const ['Page Up', 'Page Down'], l.shortcutChannel),
    _Shortcut(const ['?'], l.shortcutHelp),
  ];

  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.keyboardShortcutsTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in shortcuts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final k in s.keys) _KeyCap(label: k),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Text(
                        s.description,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    ),
  );
}

/// A small keyboard-key styled chip, e.g. `[ Space ]`.
class _KeyCap extends StatelessWidget {
  final String label;
  const _KeyCap({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

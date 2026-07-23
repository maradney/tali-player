import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/services/pin_lock_service.dart';
import '../../l10n/app_localizations.dart';

const _minPinLength = 4;

/// Prompts for the PIN and returns true only once the correct one is
/// entered; false if the user cancels. Verification happens inline (wrong
/// PIN shows an error and clears the field, dialog stays open) rather than
/// closing and reopening. [title] defaults to the localized "Enter PIN".
Future<bool> requirePin(BuildContext context, {String? title}) async {
  final l = AppLocalizations.of(context)!;
  final dialogTitle = title ?? l.pinEnter;
  final controller = TextEditingController();
  String? error;

  try {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          void submit() {
            if (PinLockService.instance.verifyPin(controller.text)) {
              Navigator.pop(context, true);
            } else {
              setState(() {
                error = l.pinIncorrect;
                controller.clear();
              });
            }
          }

          return AlertDialog(
            title: Text(dialogTitle),
            content: TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration:
                  InputDecoration(labelText: l.pinLabel, errorText: error),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.cancel),
              ),
              FilledButton(onPressed: submit, child: Text(l.unlock)),
            ],
          );
        },
      ),
    );
    return result == true;
  } finally {
    controller.dispose();
  }
}

/// Handles both "set PIN for the first time" and "change PIN" - if a PIN
/// already exists, the current one must be verified first.
Future<void> showSetOrChangePinDialog(BuildContext context) async {
  final l = AppLocalizations.of(context)!;
  if (PinLockService.instance.hasPin) {
    final ok = await requirePin(context, title: l.pinEnterCurrent);
    if (!ok || !context.mounted) return;
  }

  final pinController = TextEditingController();
  final confirmController = TextEditingController();
  String? error;

  final String? newPin;
  try {
    newPin = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          void submit() {
            final pin = pinController.text;
            if (pin.length < _minPinLength) {
              setState(() => error = l.pinTooShort(_minPinLength));
              return;
            }
            if (pin != confirmController.text) {
              setState(() => error = l.pinMismatch);
              return;
            }
            Navigator.pop(context, pin);
          }

          return AlertDialog(
            title: Text(l.settingsSetPin),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pinController,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: l.pinNew),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                      labelText: l.pinConfirm, errorText: error),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.cancel),
              ),
              FilledButton(onPressed: submit, child: Text(l.save)),
            ],
          );
        },
      ),
    );
  } finally {
    pinController.dispose();
    confirmController.dispose();
  }

  if (newPin != null) {
    await PinLockService.instance.setPin(newPin);
  }
}

/// Verifies the current PIN, confirms the consequence (all locks clear
/// too), then removes it.
Future<void> showRemovePinDialog(BuildContext context) async {
  final l = AppLocalizations.of(context)!;
  final ok = await requirePin(context, title: l.pinEnterCurrent);
  if (!ok || !context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(l.pinRemoveTitle),
      content: Text(l.pinRemoveBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.remove),
        ),
      ],
    ),
  );
  if (confirmed == true) await PinLockService.instance.clearPin();
}

/// Long-press entry point for locking/unlocking a single category. Nudges
/// toward Settings if no PIN exists yet rather than silently doing nothing.
Future<void> toggleCategoryLockPrompt(
  BuildContext context, {
  required String type,
  required String categoryId,
  required String name,
}) async {
  final l = AppLocalizations.of(context)!;
  if (!PinLockService.instance.hasPin) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.pinSetFirst)),
    );
    return;
  }
  final locked = PinLockService.instance.isCategoryLocked(type, categoryId);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(locked ? l.unlockCategoryTitle : l.lockCategoryTitle),
      content: Text(
        locked ? l.lockRemovedBody(name) : l.lockAddedBody(name),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(locked ? l.unlock : l.lock),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await PinLockService.instance.setCategoryLocked(type, categoryId, !locked);
  }
}

/// Long-press entry point for locking/unlocking a single item (channel,
/// movie, or series).
Future<void> toggleItemLockPrompt(
  BuildContext context, {
  required String type,
  required String id,
  required String name,
}) async {
  final l = AppLocalizations.of(context)!;
  if (!PinLockService.instance.hasPin) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.pinSetFirst)),
    );
    return;
  }
  final locked = PinLockService.instance.isItemLocked(type, id);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(locked ? l.unlockItemTitle : l.lockItemTitle),
      content: Text(
        locked ? l.lockRemovedBody(name) : l.lockAddedBody(name),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(locked ? l.unlock : l.lock),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await PinLockService.instance.setItemLocked(type, id, !locked);
  }
}

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// A simple "type to filter the list that's already loaded" field - pure
/// client-side filtering over one category's worth of channels/movies/
/// series. Distinct from the Search tab, which queries the full on-device
/// index across every category and content type.
class QuickFilterField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;

  const QuickFilterField({
    super.key,
    required this.controller,
    required this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.filter_alt_outlined),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: AppLocalizations.of(context)!.clear,
                    onPressed: controller.clear,
                  ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// The tappable "Search" field at the top of the Home dashboard.
///
/// Deliberately not a real [TextField]. Typing happens on the Search screen,
/// which owns the query, the tabs and the debounce; a second input here would
/// either duplicate that or have to hand its text over mid-keystroke. This
/// only has to look like somewhere you can type, because that is what makes
/// people reach for it - a plain button reads as navigation and gets skipped.
///
/// Phone-only. On a desktop window Search is already a permanent entry in the
/// navigation rail, so a second affordance would be clutter rather than a
/// shortcut - see [showsHomeSearchPill].
class HomeSearchPill extends StatelessWidget {
  /// Placeholder copy. Uses the Search screen's own hint so the two surfaces
  /// promise the same thing.
  final String hint;
  final VoidCallback onTap;

  const HomeSearchPill({super.key, required this.hint, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      // The label comes from the Text below. Setting it here as well made the
      // node read the hint twice to a screen reader.
      child: Semantics(
        button: true,
        container: true,
        child: Material(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.search, size: 20, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Text that clamps to [collapsedLines] with a "More" toggle, and only shows
/// the toggle when the text genuinely doesn't fit.
///
/// A plain `Text(maxLines: 4, overflow: ellipsis)` leaves a long plot ending in
/// "..." with no way to read the rest, which on a phone is most of them. The
/// fit is measured rather than guessed at from string length, because whether
/// it overflows depends on the width it's given, the font, and the user's text
/// scale - a character count is wrong on all three.
class ExpandableText extends StatefulWidget {
  final String text;
  final int collapsedLines;
  final TextStyle? style;

  const ExpandableText({
    super.key,
    required this.text,
    this.collapsedLines = 4,
    this.style,
  });

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;

  @override
  void didUpdateWidget(ExpandableText old) {
    super.didUpdateWidget(old);
    // A recycled widget showing different text starts collapsed again.
    if (old.text != widget.text) _expanded = false;
  }

  /// Whether [text] needs more than [collapsedLines] at this width.
  static bool overflows(
    String text, {
    required int maxLines,
    required double maxWidth,
    required TextStyle style,
    required TextScaler textScaler,
    required TextDirection textDirection,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final style = widget.style ?? DefaultTextStyle.of(context).style;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tooLong = overflows(
          widget.text,
          maxLines: widget.collapsedLines,
          maxWidth: constraints.maxWidth,
          style: style,
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.text,
              style: style,
              maxLines: _expanded ? null : widget.collapsedLines,
              overflow: _expanded ? null : TextOverflow.ellipsis,
            ),
            if (tooLong)
              // Aligned to the text's own start edge so it reads as part of
              // the paragraph in both LTR and RTL.
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(_expanded ? l.showLess : l.showMore),
                ),
              ),
          ],
        );
      },
    );
  }
}

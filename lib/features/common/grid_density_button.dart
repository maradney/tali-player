import 'package:flutter/material.dart';

import '../../data/services/settings_service.dart';
import '../../l10n/app_localizations.dart';

/// App-bar action that adjusts the global poster-grid density in place, shown
/// on the screens that use a poster grid (Movies/Series/Watch History). The
/// setting is still global + persisted (see [SettingsService]); this just
/// puts the control where you're actually looking at the grid. The icon
/// reflects the current density and updates live.
class GridDensityButton extends StatelessWidget {
  const GridDensityButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final current = SettingsService.instance.gridDensity;
        return PopupMenuButton<GridDensity>(
          tooltip: l.gridDensity,
          icon: Icon(_iconFor(current)),
          initialValue: current,
          onSelected: SettingsService.instance.setGridDensity,
          itemBuilder: (context) => [
            for (final density in GridDensity.values)
              CheckedPopupMenuItem(
                value: density,
                checked: density == current,
                child: Text(_labelFor(density, l)),
              ),
          ],
        );
      },
    );
  }

  IconData _iconFor(GridDensity density) => switch (density) {
        GridDensity.compact => Icons.density_small,
        GridDensity.comfortable => Icons.density_medium,
        GridDensity.spacious => Icons.density_large,
      };

  String _labelFor(GridDensity density, AppLocalizations l) =>
      switch (density) {
        GridDensity.compact => l.gridDensityCompact,
        GridDensity.comfortable => l.gridDensityComfortable,
        GridDensity.spacious => l.gridDensitySpacious,
      };
}

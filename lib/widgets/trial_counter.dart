import 'package:flutter/material.dart';

/// Local, screen-specific interaction: the count only matters while this
/// widget is on screen, so it's a StatefulWidget rather than global state.
class TrialCounter extends StatefulWidget {
  final String label;
  const TrialCounter({super.key, this.label = 'Trial Count'});

  @override
  State<TrialCounter> createState() => _TrialCounterState();
}

class _TrialCounterState extends State<TrialCounter> {
  int _count = 0;

  void _increment() => setState(() => _count++);
  void _reset() => setState(() => _count = 0);

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(widget.label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text('$_count', style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 12),
            // Row + Flexible/Expanded keep the buttons from overflowing on
            // narrow widths (e.g. small phones or split-screen).
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: ElevatedButton.icon(
                    onPressed: _increment,
                    icon: const Icon(Icons.add),
                    label: const Text('Record Trial'),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: OutlinedButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reset'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
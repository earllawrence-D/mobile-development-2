import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../widgets/trial_counter.dart';

class ActivityOneScreen extends StatelessWidget {
  const ActivityOneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity 1: Titration Log')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Use the counter below to log each titration trial performed '
                'during this lab session.',
              ),
              const SizedBox(height: 20),
              const TrialCounter(label: 'Titration Trials'),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.save_alt),
                label: const Text('Save Session to Dashboard'),
                onPressed: () {
                  context.read<AppState>().logActivity('Logged a titration trial session');
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Saved to Home Dashboard activity log')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
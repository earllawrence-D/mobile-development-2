import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final nameController = TextEditingController(text: appState.profileName);
    // Keep the cursor at the end instead of jumping to the start on rebuild.
    nameController.selection = TextSelection.fromPosition(
      TextPosition(offset: nameController.text.length),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Toggling this calls AppState.toggleTheme(), which calls
              // notifyListeners() — every screen watching AppState
              // (including the Home Dashboard) rebuilds instantly.
              SwitchListTile(
                title: const Text('Dark Theme'),
                subtitle: const Text('Applies instantly across the whole app'),
                value: appState.isDarkMode,
                onChanged: (value) => context.read<AppState>().toggleTheme(value),
              ),
              const Divider(height: 32),
              Text('Profile Name', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onSubmitted: (value) => _applyNameChange(context, appState, value),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () =>
                    _applyNameChange(context, appState, nameController.text),
                child: const Text('Update Name'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Applies [rawName] as the new profile name and shows a SnackBar
  /// describing what happened: updated, unchanged, or rejected (blank).
  void _applyNameChange(BuildContext context, AppState appState, String rawName) {
    // Look the messenger up before mutating state: notifyListeners() below
    // rebuilds this screen synchronously, so resolve it while we know
    // this context is mounted.
    final messenger = ScaffoldMessenger.of(context);
    final previousName = appState.profileName;
    final applied = appState.updateProfileName(rawName);

    if (!applied) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Profile name can't be empty")),
      );
    } else if (appState.profileName == previousName) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Name is unchanged')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('Name updated to "${appState.profileName}"')),
      );
    }
  }
}
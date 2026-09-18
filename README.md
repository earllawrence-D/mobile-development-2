# Lab Compiler App

A master Flutter application for compiling and managing future laboratory activities. This project demonstrates **multi-screen navigation, declarative widget architecture, responsive layouts, and global state management** using Flutter and the `provider` package.

## Features

* Multi-screen navigation using named routes
* Reusable Flutter widget architecture
* Responsive layout for phone and tablet/wider screens
* Global state management with `Provider`
* Light/dark theme switching
* Editable profile name
* Recent activity tracking
* Local screen-specific state management
* Modular structure for adding future laboratory activities

## Getting Started

### Prerequisites

Make sure you have the following installed:

* [Flutter SDK](https://docs.flutter.dev/get-started/install)
* Dart SDK — included with Flutter
* Android Studio or another Flutter-compatible IDE
* An emulator or physical device

### Installation

Clone the repository:

```bash
git clone <your-repository-url>
cd lab-compiler-app
```

Install the project dependencies:

```bash
flutter pub get
```

If the repository only contains the Dart source and `pubspec.yaml`, generate the required platform folders:

```bash
flutter create .
```

> You only need to run `flutter create .` once if the `android/`, `ios/`, `web/`, or other platform-specific folders are missing.

### Run the Application

```bash
flutter run
```

To check that the project is properly configured:

```bash
flutter doctor
```

## Project Structure

```text
lib/
├── main.dart
│   └── App root, MaterialApp, and named routes
│
├── models/
│   └── app_state.dart
│       └── Global ChangeNotifier for:
│           ├── Theme
│           ├── Profile name
│           └── Activity log
│
├── screens/
│   ├── home_dashboard.dart
│   │   └── Responsive dashboard and activity menu
│   │
│   ├── activity_one_screen.dart
│   │   └── Activity 1 — Titration Log
│   │
│   ├── activity_two_screen.dart
│   │   └── Activity 2 — Data Notes
│   │
│   └── settings_screen.dart
│       └── Theme and profile settings
│
└── widgets/
    ├── activity_menu_card.dart
    │   └── Reusable StatelessWidget dashboard card
    │
    └── trial_counter.dart
        └── StatefulWidget for the local trial counter
```

## How Each Requirement Is Met

### Multi-Screen Navigation

The application uses `MaterialApp.routes` in `main.dart` to define four named routes.

The Home Dashboard can navigate to:

* Activity One
* Activity Two
* Settings

Navigation is handled using:

```dart
Navigator.pushNamed(context, '/routeName');
```

### Widget Architecture

The project demonstrates both stateless and stateful widgets.

**Stateless widget:**

`ActivityMenuCard` is a reusable `StatelessWidget` used for displaying activity options. It does not maintain internal state.

**Stateful widgets:**

* `TrialCounter` manages the local trial counter.
* `ActivityTwoScreen` manages local text input state.

This keeps screen-specific state within the components that actually need it.

### Responsive Layout

`HomeDashboard` uses `LayoutBuilder` to adapt its layout based on the available screen width.

On narrow screens, activities are displayed in a vertical `Column`.

On wider screens, activities are displayed side-by-side using a `Row` with `Expanded` children.

`TrialCounter` also uses `Flexible` for its button layout to prevent overflow on smaller screens.

### Global State Management

The application uses the [`provider`](https://pub.dev/packages/provider) package for global state management.

`AppState` extends `ChangeNotifier` and stores application-wide state such as:

* Theme mode
* Profile name
* Recent activity history

The state is provided at the application level using:

```dart
ChangeNotifierProvider
```

Screens can access the state using:

```dart
context.watch<AppState>()
```

or:

```dart
context.read<AppState>()
```

When global values are changed, `notifyListeners()` triggers the necessary widgets to rebuild automatically.

This allows the application to update without manual refreshes or unnecessary prop drilling.

## Adding a New Laboratory Activity

The project is designed to be extended as a master laboratory application.

To add a new activity:

### 1. Create a new screen

Add a new file inside:

```text
lib/screens/
```

For example:

```text
activity_three_screen.dart
```

### 2. Add a named route

Register the new screen in `main.dart`:

```dart
routes: {
  '/activity-three': (context) => const ActivityThreeScreen(),
},
```

### 3. Add an Activity Menu Card

Add a new `ActivityMenuCard` to `HomeDashboard` so users can access the activity.

### 4. Log the Activity

Any activity screen can update the global activity history using:

```dart
context.read<AppState>().logActivity('Activity Three');
```

The activity will then appear in the dashboard's **Recent Activity** section.

## Technologies Used

* **Flutter**
* **Dart**
* **Provider**
* **Material Design**
* **ChangeNotifier**
* **Named Routes**
* **Responsive Flutter Layouts**

## Purpose

This project serves as a foundation for a centralized laboratory application where additional laboratory activities can be added over time without restructuring the entire application.

The architecture separates:

* **Screens** — application pages and activities
* **Widgets** — reusable UI components
* **Models** — global application state

This makes the project easier to maintain and extend as more laboratory activities are introduced.

## License

This project is for educational purposes.

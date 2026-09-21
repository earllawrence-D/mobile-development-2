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
* **Network Diagnostic Dashboard** — background speed/ping diagnostics
* Connection-health tiers: Excellent / Fair / Poor / Degraded / Offline
* Adaptive content delivery: high-res multimedia ⇄ lightweight placeholders

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

To run the unit tests (`test/diagnostic_report_test.dart` covers the threshold, packet-loss and lag classification logic):

```bash
flutter test
```

> The Network Diagnostic Dashboard performs **real** HTTP probes against
> Cloudflare's speed-test endpoints, so it requires internet access. The
> probes use `dart:io`, targeting mobile/desktop platforms (not web).
> The release manifest (`android/app/src/main/AndroidManifest.xml`) declares
> `<uses-permission android:name="android.permission.INTERNET" />`
> so debug and release builds both get real network access.

## Project Structure

```text
lib/
├── main.dart
│   └── App root, MaterialApp, named routes, and global providers
│
├── models/
│   ├── app_state.dart
│   │   └── Global ChangeNotifier for:
│   │       ├── Theme
│   │       ├── Profile name
│   │       └── Activity log
│   │
│   ├── network_monitor.dart
│   │   └── Connectivity stream listener + simulated request queue
│   │
│   ├── diagnostic_report.dart
│   │   └── Pure data + thresholds:
│   │       ├── HealthTier (Excellent / Fair / Poor / Degraded / Offline)
│   │       ├── DiagnosticReport (one full cycle's measurements)
│   │       └── NetworkThresholds.classify()
│   │
│   └── network_diagnostics.dart
│       └── Background diagnostic tool (ChangeNotifier):
│           ├── Step 1 — baseline idle ping
│           ├── Step 2 — download bandwidth + concurrent pings
│           └── Step 3 — upload bandwidth + concurrent upload pings
│
├── screens/
│   ├── home_dashboard.dart
│   │   └── Responsive dashboard, activity menu, and health pill
│   │
│   ├── activity_one_screen.dart
│   │   └── Activity 1 — Titration Log
│   │
│   ├── activity_two_screen.dart
│   │   └── Activity 2 — Data Notes
│   │
│   ├── network_monitor_screen.dart
│   │   └── Live interface status, queuing, and handover recovery
│   │
│   ├── network_diagnostic_dashboard.dart
│   │   └── Tier banner, live metrics, phase checklist, history
│   │       sparkline, adaptive media panel, threshold legend
│   │
│   └── settings_screen.dart
│       └── Theme and profile settings
│
└── widgets/
    ├── activity_menu_card.dart
    │   └── Reusable StatelessWidget dashboard card
    │
    ├── trial_counter.dart
    │   └── StatefulWidget for the local trial counter
    │
    ├── adaptive_media_panel.dart
    │   └── High-res multimedia ⇄ lightweight placeholder switching
    │
    ├── health_status_pill.dart
    │   └── App-wide connection-health badge (subscribes itself)
    │
    └── health_tier_visuals.dart
        └── Shared color/icon/label mapping for HealthTier
```

## How Each Requirement Is Met

### Multi-Screen Navigation

The application uses `MaterialApp.routes` in `main.dart` to define six named routes.

The Home Dashboard can navigate to:

* Activity One
* Activity Two
* Network Monitor
* Network Diagnostics
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

### Network Diagnostic Dashboard

A dedicated screen (`/network-diagnostics`) built on top of a **background
diagnostic tool** that regularly measures the real connection and
classifies its health for the whole app.

#### Diagnostic Tool Implementation

`NetworkDiagnostics` is a global `ChangeNotifier` provider (registered in
`main.dart`). It runs a repeating multi-step cycle entirely in the
background, using real `dart:io` HTTP probes against Cloudflare's public
speed-test endpoints:

1. **Idle ping** — five sequential unloaded probes measure the baseline
   round-trip time (median) and the packet-loss baseline.
2. **Download bandwidth** — a ~3 MB payload is streamed from
   `speed.cloudflare.com` *while* four concurrent pings run, capturing
   throughput **and** latency degradation under load (bufferbloat).
3. **Upload bandwidth** — a ~1 MB payload is POSTed to `/__up` *while*
   the same concurrent ping sequence runs, capturing upload throughput
   together with the upload-side ping.

Each cycle finishes by classifying a `DiagnosticReport` into a tier and
calling `notifyListeners()`, so every screen watching the provider
updates instantly — the definition of "global state injection".

#### Threshold Logic

Classification is a pure, unit-tested function
(`NetworkThresholds.classify` in `lib/models/diagnostic_report.dart`):

| Tier | Rule |
| --- | --- |
| Excellent | download > 10 Mbps |
| Fair | download 2 – 10 Mbps |
| Poor | download < 2 Mbps |
| Degraded | packet loss ≥ 25% **or** idle ping ≥ 400 ms **or** severe bufferbloat — overrides the speed tiers |
| Offline | every probe failed |

The dashboard screen renders the tier banner, live metrics, a live
step-checklist while a cycle runs, a download-history sparkline, the
threshold legend, and a **Lag Under Load** card showing how far the ping
inflates while a transfer saturates the link (bufferbloat).

When a cycle fails every probe the dashboard also shows *why* — the red note
reports the underlying exception (e.g. `SocketException: Failed host lookup`,
`Connection refused`, HTTP status) so an "Offline" verdict can be traced to
its real cause instead of silently rendering dashes.

#### Adaptive UI

The **Adaptive Content Delivery** panel demonstrates the objective:

* Excellent → high-resolution multimedia fetched over the network
* Fair → a single reduced-resolution image
* Poor / Degraded / Offline → lightweight local placeholders with zero
  network requests

A reusable `HealthStatusPill` on the Home app bar broadcasts the tier
app-wide and deep-links into the dashboard.

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
* **connectivity_plus**
* **dart:io HTTP** — real bandwidth/ping probes (Cloudflare speed-test)
* **flutter_test** — unit-tested threshold logic

## Purpose

This project serves as a foundation for a centralized laboratory application where additional laboratory activities can be added over time without restructuring the entire application.

The architecture separates:

* **Screens** — application pages and activities
* **Widgets** — reusable UI components
* **Models** — global application state

This makes the project easier to maintain and extend as more laboratory activities are introduced.

## License

This project is for educational purposes.

# FocusFlow

A Flutter focus-routine app styled from the supplied design reference.

- **Home:** live local weekly dial, countdown and weekday, Monday 06:00 through Sunday 20:00 (158 hours in a non-DST week). The rest window counts down to the next Monday. Selected apps appear grey.
- **App Block:** consent-gated Android installed-app list with native icons, search, all/selected/user/system filters and persistent selections. Pull down to refresh installed packages.
- **Tracker:** daily source tasks, progress bars, an editable status/hours/work-description popup, and a local Python scoring API with SQLite persistence. See [backend setup and scoring](backend/README.md).

## Run

```sh
flutter pub get
flutter run
```

App enumeration requires Android. Other platforms show an explanatory empty state.

## Android permissions and scope

`QUERY_ALL_PACKAGES` is a normal manifest permission, not a runtime permission dialog. An in-app disclosure asks for consent before reading installed apps. Names/icons are queried locally with PackageManager; consent and selected package names are stored in Android SharedPreferences. No app inventory is uploaded.

## Enable protection on Android

1. In App Block, allow installed-app access and select apps.
2. Under **Enable focus protection**, open **App blocking → Settings**, accept the disclosure, then enable **FocusFlow app blocking** in Android Accessibility settings.
3. Open **Dismiss notifications → Settings** and grant FocusFlow notification access.
4. Optionally enable **Blocking banner** (display over other apps). Blocking works without this; a toast is used instead.

The accessibility service observes window-state package names without reading screen contents. During Monday 06:00–Sunday 20:00 local time, selected launches redirect to Home. Android does not expose a public force-stop intent for other apps: this does not terminate their processes, stop media, or disable their packages. Settings, launchers, the active keyboard, and core system UI remain available. Turn services off in Settings to revoke access.

The notification service dismisses selected apps' posted notifications and clears existing ones on connection, selection changes, and the next schedule boundary. Initial sound/vibration may occur before Android delivers the callback; some ongoing/system notifications cannot be dismissed. Long-press an app row to open its notification settings for guaranteed silence by disabling its notifications. This manual setting is not automatically restored after the weekly cycle.

Both services read the same local SharedPreferences independently of Flutter. Android binds them after the user enables them. Force-stopping FocusFlow, restricted settings, battery policies, or OEM service restrictions can interrupt enforcement. Tracker uses the separate local Python service described in backend/README.md.

The two BIND permissions protect the service declarations (`android:permission`); they are system binding permissions, not runtime permissions requested by Flutter. `SYSTEM_ALERT_WINDOW` is declared as a uses-permission and granted through special access settings.

### Device smoke test

- Select a nonessential app; enable both services. During the focus window, launch it: Home should appear. Confirm an unselected app remains usable.
- Post a notification from the selected app: it should be dismissed; compare with an unselected app.
- Change selections and confirm both services respond without restarting Flutter.
- Leave/close the Flutter activity and repeat. Reopen it and confirm saved selections and access status.
- Check Monday 05:59/06:00 and Sunday 19:59/20:00; selected apps are unrestricted outside the window.
- Revoke each access and confirm its status updates when returning. Check overlay-off fallback and that Settings remains accessible.

Google Play restricts broad package visibility and requires an eligible use case and declaration before distribution: https://support.google.com/googleplay/android-developer/answer/10158779

## Verify

```sh
flutter analyze
flutter test
flutter build apk --debug
```

Tests cover weekly start/end and calendar rollover, consent, selection persistence, save failure, search/filter, navigation, tracker submission/validation and Settings access.



## Weekly selection lock

During Monday 06:00–Sunday 20:00, selected apps cannot be removed from the focus list. Flutter disables their toggles and Android rejects removal requests independently with `CYCLE_LOCKED`. Apps added midweek lock immediately for the remainder of that cycle. At Sunday 20:00 the services stop enforcing and toggles become editable; retained selections automatically apply again Monday 06:00. This is the original 158-hour weekly focus window, not a rolling 168-hour timer. Tracker scores do not unlock apps.

The Android Accessibility service must remain enabled. This is voluntary focus protection, not tamper-proof device management: disabling access, force-stopping/uninstalling FocusFlow, or changing the device clock can bypass enforcement. The app never blocks access to Android Settings.

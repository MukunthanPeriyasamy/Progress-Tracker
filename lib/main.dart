import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_repository.dart';
import 'weekly_cycle.dart';
import 'tracker_page.dart';

const blue = Color(0xff004ac6);
const ink = Color(0xff0b1c30);
const muted = Color(0xff737686);
const pale = Color(0xffeff4ff);
const track = Color(0xffdce9ff);

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.clock});
  final DateTime Function()? clock;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FocusFlow',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xfff8f9ff),
      colorScheme: ColorScheme.fromSeed(
        seedColor: blue,
        primary: blue,
        surface: const Color(0xfff8f9ff),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -1,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyMedium: TextStyle(fontSize: 14, color: ink),
        bodySmall: TextStyle(fontSize: 12, color: muted),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfff8f9ff),
        foregroundColor: ink,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: FocusShell(clock: clock),
  );
}

class FocusShell extends StatefulWidget {
  const FocusShell({super.key, this.clock});
  final DateTime Function()? clock;
  @override
  State<FocusShell> createState() => _FocusShellState();
}

class _FocusShellState extends State<FocusShell> with WidgetsBindingObserver {
  final repository = AppRepository();
  final search = TextEditingController();
  late final Timer ticker;
  late DateTime now;
  DateTime readClock() => (widget.clock ?? DateTime.now)();
  bool locked(String package) =>
      WeeklyCycle(now).active && selected.contains(package);
  int page = 0;
  bool loading = true, consent = false, supported = true, saving = false;
  String? error;
  String filter = 'All apps';
  List<InstalledApp> apps = [];
  Set<String> selected = {};

  Map<Object?, Object?> permissions = {};
  bool permissionsKnown = false;

  Future<void> refreshPermissions() async {
    try {
      final value = await repository.permissions();
      if (mounted) {
        setState(() {
          permissions = value;
          permissionsKnown = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => permissionsKnown = false);
    }
  }

  Future<void> openAccess(String target, {String? package}) async {
    if (target == 'accessibility' || target == 'notifications') {
      final allow = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            target == 'accessibility'
                ? 'Enable app blocking?'
                : 'Enable notification dismissal?',
          ),
          content: Text(
            target == 'accessibility'
                ? 'FocusFlow observes foreground app names and returns you to Home when a selected app opens during your focus week. It does not read screen contents or force-stop apps. You can turn it off in Android Settings at any time.'
                : 'Android notification access exposes notifications to this service. FocusFlow checks only their app package and dismissal key to clear selected apps’ alerts during your focus week. Nothing is stored or uploaded. Initial sound or vibration may occur before dismissal. For guaranteed silence, turn off notifications in the app’s system settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      if (allow != true || !mounted) return;
    }
    try {
      await repository.openSettings(target, package: package);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open Android Settings. Please try again.'),
          ),
        );
      }
    }
  }

  Widget accessPanel() => Panel(
    color: pale,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Enable focus protection',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Mon 6 AM – Sun 8 PM. Grant each access manually in Android Settings.',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        for (final entry in {
          'accessibility': 'App blocking',
          'notifications': 'Dismiss notifications',
          'overlay': 'Blocking banner (optional)',
        }.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(entry.value, style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              !permissionsKnown
                  ? 'Status unavailable'
                  : permissions[entry.key] == true
                  ? 'Enabled'
                  : 'Not enabled',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: TextButton(
              onPressed: supported ? () => openAccess(entry.key) : null,
              child: const Text('Settings'),
            ),
          ),
        const Text(
          'Alerts are dismissed after posting; sound may play first. Long-press an app below to turn off its notifications in system settings. Settings, Home and the keyboard remain available.',
          style: TextStyle(fontSize: 12, color: muted, height: 1.5),
        ),
      ],
    ),
  );

  @override
  void initState() {
    super.initState();
    now = readClock();
    WidgetsBinding.instance.addObserver(this);
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => now = readClock());
    });
    restore();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => now = readClock());
      refreshPermissions();
      if (consent && !loading && !saving) loadApps();
    }
  }

  Future<void> restore() async {
    try {
      final prefs = await repository.preferences();
      if (!mounted) return;
      consent = prefs['consent'] == true;
      selected = Set<String>.from(prefs['selected'] as List? ?? []);
      await refreshPermissions();
      if (!mounted) return;
      if (consent) {
        await loadApps();
        return;
      }
    } on MissingPluginException {
      supported = false;
    } catch (_) {
      error = 'Could not read saved settings. Please retry.';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> loadApps() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await repository.apps();
      if (!mounted) return;
      setState(() => apps = result);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not load installed apps. Please retry.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> requestAccess() async {
    final allowed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Show installed apps?'),
        content: const Text(
          'FocusFlow reads app names and icons so you can choose your focus list. This list and your selections stay on this device. App visibility does not grant permission to disable other apps.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Allow access'),
          ),
        ],
      ),
    );
    if (allowed != true || !mounted) return;
    try {
      await repository.consent();
      if (!mounted) return;
      setState(() => consent = true);
      await loadApps();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save consent. Try again.')),
        );
      }
    }
  }

  Future<void> toggle(InstalledApp app, bool value) async {
    if (!value && locked(app.package)) return;
    final next = {...selected};
    value ? next.add(app.package) : next.remove(app.package);
    setState(() => saving = true);
    try {
      await repository.save(next);
      if (mounted) setState(() => selected = next);
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.code == 'CYCLE_LOCKED'
                  ? 'Selected apps stay blocked until Sunday at 8 PM.'
                  : 'Selection could not be saved. Please retry.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selection could not be saved. Please retry.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    ticker.cancel();
    search.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          const IconTile(Icons.spa_outlined),
          const SizedBox(width: 12),
          Text(
            ['Home', 'App Block', 'Tracker'][page],
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 20),
          child: CircleAvatar(
            radius: 17,
            backgroundColor: blue,
            child: Icon(Icons.person_outline, color: Colors.white, size: 20),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: switch (page) {
            0 => home(),
            1 => appBlock(),
            _ => tracker(),
          },
        ),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: page,
      onDestinationSelected: (value) => setState(() => page = value),
      backgroundColor: Colors.white,
      indicatorColor: track,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.schedule_outlined),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.shield_outlined),
          label: 'App Block',
        ),
        NavigationDestination(
          icon: Icon(Icons.bar_chart_rounded),
          label: 'Tracker',
        ),
      ],
    ),
  );

  Widget home() {
    final cycle = WeeklyCycle(now);
    final chosen = apps.where((app) => selected.contains(app.package)).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow('CURRENT SANCTUARY'),
                  SizedBox(height: 4),
                  Text(
                    'Focus Routine',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
            BadgeLabel(cycle.active ? '●  Active cycle' : '○  Rest period'),
          ],
        ),
        const SizedBox(height: 20),
        const Panel(
          color: pale,
          child: Row(
            children: [
              IconTile(Icons.calendar_month_outlined),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Active Cycle Window',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Mon 6:00 AM – Sun 8:00 PM',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Panel(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Eyebrow('CYCLE GAUGE', color: muted),
                  Text(
                    cycle.active
                        ? 'Day ${now.weekday} of 7'
                        : 'Recharge & reset',
                    style: const TextStyle(color: blue, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Semantics(
                label:
                    '${cycle.day}, ${cycle.countdown} ${cycle.active ? 'remaining' : 'until next cycle'}',
                child: SizedBox(
                  width: 270,
                  height: 270,
                  child: CustomPaint(
                    painter: CycleDial(cycle.progress),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            cycle.active ? 'WEEKLY FOCUS' : 'NEXT CYCLE IN',
                            style: const TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.7,
                              color: muted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            cycle.countdown,
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1.4,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            cycle.day,
                            style: const TextStyle(
                              fontSize: 18,
                              color: blue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} · Local time',
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: MiniStat(
                      Icons.hourglass_top,
                      cycle.active ? 'Time remaining' : 'Next start',
                      cycle.active ? cycle.countdown : 'Monday 6 AM',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MiniStat(
                      Icons.shield_outlined,
                      'Focus list',
                      '${selected.length} selected',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Weekly Cadence',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              Row(
                children: List.generate(
                  7,
                  (i) => Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: now.weekday == i + 1 ? blue : pale,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i],
                            style: TextStyle(
                              color: now.weekday == i + 1
                                  ? Colors.white
                                  : muted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Icon(
                            now.weekday == i + 1
                                ? Icons.circle
                                : Icons.radio_button_unchecked,
                            size: 12,
                            color: now.weekday == i + 1
                                ? Colors.white
                                : muted.withValues(alpha: .45),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const IconTile(Icons.shield_outlined),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Selected for Focus',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Manage apps',
                    onPressed: () => setState(() => page = 1),
                    icon: const Icon(Icons.tune, color: blue),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                permissions['accessibility'] == true
                    ? (cycle.active
                          ? 'Selected app launches return to Home during focus time.'
                          : 'Rest period. App blocking resumes Monday at 6 AM.')
                    : 'Enable App blocking in App Block to protect your focus time.',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
              const SizedBox(height: 12),
              if (chosen.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    selected.isEmpty
                        ? 'Make room for focus. Choose apps in App Block.'
                        : 'Open App Block to load your selected apps.',
                    style: const TextStyle(color: muted),
                  ),
                ),
              ...chosen.map(
                (app) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xfff1f2f5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      AppIcon(app, grey: true),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          app.name,
                          style: const TextStyle(
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Text(
                        'Selected',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Panel(
          color: pale,
          child: Row(
            children: [
              Icon(Icons.spa_outlined, color: blue),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'A little less noise. A little more space for what matters.',
                  style: TextStyle(color: blue, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget appBlock() {
    final query = search.text.toLowerCase().trim();
    final visible = apps
        .where(
          (app) =>
              (app.name.toLowerCase().contains(query) ||
                  app.package.toLowerCase().contains(query)) &&
              switch (filter) {
                'Selected' => selected.contains(app.package),
                'User apps' => !app.system,
                'System apps' => app.system,
                _ => true,
              },
        )
        .toList();
    return RefreshIndicator(
      onRefresh: () async {
        if (consent) await loadApps();
      },
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('PROTECT YOUR ATTENTION'),
                  const SizedBox(height: 5),
                  const Text(
                    'Your focus, your rules.',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose the apps to set aside during your weekly routine.',
                    style: TextStyle(color: muted, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Search installed apps',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: search.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    onPressed: () {
                                      search.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        tooltip: 'Filter apps',
                        initialValue: filter,
                        onSelected: (value) => setState(() => filter = value),
                        itemBuilder: (_) =>
                            ['All apps', 'Selected', 'User apps', 'System apps']
                                .map(
                                  (value) => CheckedPopupMenuItem(
                                    value: value,
                                    checked: value == filter,
                                    child: Text(value),
                                  ),
                                )
                                .toList(),
                        icon: const Icon(Icons.tune, color: blue),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      BadgeLabel(filter),
                      const Spacer(),
                      Text(
                        '${selected.length} selected',
                        style: const TextStyle(color: blue, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  accessPanel(),
                ],
              ),
            ),
          ),
          if (loading ||
              !supported ||
              error != null ||
              !consent ||
              visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : !supported
                  ? const EmptyState(
                      icon: Icons.android,
                      title: 'Available on Android',
                      message:
                          'Run this app on an Android device to view installed apps.',
                    )
                  : error != null
                  ? EmptyState(
                      icon: Icons.error_outline,
                      title: 'Something went wrong',
                      message: error!,
                      action: TextButton(
                        onPressed: consent ? loadApps : restore,
                        child: const Text('Retry'),
                      ),
                    )
                  : !consent
                  ? EmptyState(
                      icon: Icons.apps,
                      title: 'Build your focus list',
                      message:
                          'Allow access to see the apps installed on this device.',
                      action: FilledButton.icon(
                        onPressed: requestAccess,
                        icon: const Icon(Icons.apps),
                        label: const Text('Show installed apps'),
                      ),
                    )
                  : const EmptyState(
                      icon: Icons.search_off,
                      title: 'No apps found',
                      message: 'Try another search or change the filter.',
                    ),
            ),
          if (!loading &&
              supported &&
              error == null &&
              consent &&
              visible.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              sliver: SliverList.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final app = visible[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        leading: AppIcon(app),
                        onLongPress: () => openAccess(
                          'appNotifications',
                          package: app.package,
                        ),
                        title: Text(
                          app.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          app.protected
                              ? 'Essential app · always available'
                              : locked(app.package)
                              ? 'Locked until Sunday 8 PM'
                              : app.system
                              ? 'System app'
                              : 'Installed app',
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                        trailing: Semantics(
                          label: 'Select ${app.name} for focus',
                          child: Switch(
                            value: selected.contains(app.package),
                            onChanged:
                                saving || app.protected || locked(app.package)
                                ? null
                                : (value) => toggle(app, value),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget tracker() => const TrackerPage();
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.color = Colors.white});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}

class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key});
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: track,
      borderRadius: BorderRadius.circular(11),
    ),
    child: Icon(icon, color: blue, size: 21),
  );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color = blue});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.3,
      color: color,
    ),
  );
}

class BadgeLabel extends StatelessWidget {
  const BadgeLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: track,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: blue,
      ),
    ),
  );
}

class MiniStat extends StatelessWidget {
  const MiniStat(this.icon, this.label, this.value, {super.key});
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: pale,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: blue),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 10, color: muted)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
      ],
    ),
  );
}

class AppIcon extends StatelessWidget {
  const AppIcon(this.app, {super.key, this.grey = false});
  final InstalledApp app;
  final bool grey;
  @override
  Widget build(BuildContext context) {
    final icon = app.icon == null
        ? const Icon(Icons.android, color: muted)
        : Image.memory(
            app.icon!,
            width: 40,
            height: 40,
            errorBuilder: (_, error, stack) =>
                const Icon(Icons.apps, color: muted),
          );
    return SizedBox(
      width: 40,
      height: 40,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: grey
            ? ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  Colors.grey,
                  BlendMode.saturation,
                ),
                child: Opacity(opacity: .55, child: icon),
              )
            : icon,
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: blue, size: 42),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, height: 1.5),
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    ),
  );
}

class CycleDial extends CustomPainter {
  CycleDial(this.progress);
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 10;
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawCircle(center, radius, pen);
    pen.color = blue;
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        pen,
      );
    }
    for (var i = 0; i < 56; i++) {
      final angle = i * 2 * math.pi / 56 - math.pi / 2;
      final unit = Offset(math.cos(angle), math.sin(angle));
      pen
        ..strokeWidth = i % 8 == 0 ? 2 : 1
        ..color = muted.withValues(alpha: i % 8 == 0 ? .6 : .25);
      canvas.drawLine(
        center + unit * (radius - 14),
        center + unit * (radius - (i % 8 == 0 ? 23 : 19)),
        pen,
      );
    }
    final angle = 2 * math.pi * progress - math.pi / 2;
    final unit = Offset(math.cos(angle), math.sin(angle));
    // An outer needle leaves the countdown unobstructed.
    pen
      ..color = blue
      ..strokeWidth = 3;
    canvas.drawLine(
      center + unit * (radius - 28),
      center + unit * (radius - 12),
      pen,
    );
    canvas.drawCircle(center + unit * radius, 6, Paint()..color = blue);
    canvas.drawCircle(
      center + unit * radius,
      2.5,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(CycleDial oldDelegate) => oldDelegate.progress != progress;
}

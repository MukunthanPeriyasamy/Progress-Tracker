import 'package:flutter/material.dart';
import 'tracker_api.dart';

class TrackerPage extends StatefulWidget {
  const TrackerPage({super.key, this.api});
  final TrackerApi? api;
  @override
  State<TrackerPage> createState() => _TrackerPageState();
}

class _TrackerPageState extends State<TrackerPage> {
  late final TrackerApi api = widget.api ?? TrackerApi();
  List<String> dates = [];
  String? selectedDate, error;
  Map<String, dynamic>? day;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final plan = await api.plan();
      final values = List<String>.from(plan['dates'] as List);
      if (values.isEmpty) {
        throw TrackerException('The source has no daily tasks.');
      }
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final initial = values.contains(today)
          ? today
          : today.compareTo(values.first) < 0
          ? values.first
          : values.last;
      if (!mounted) return;
      dates = values;
      await loadDay(selectedDate ?? initial);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  Future<void> loadDay(String date) async {
    setState(() {
      selectedDate = date;
      loading = true;
      error = null;
      day = null;
    });
    try {
      final value = await api.day(date);
      if (mounted) setState(() => day = value);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(selectedDate!),
      firstDate: DateTime.parse(dates.first),
      lastDate: DateTime.parse(dates.last),
      selectableDayPredicate: (date) =>
          dates.contains(date.toIso8601String().substring(0, 10)),
    );
    if (date != null && mounted) {
      await loadDay(date.toIso8601String().substring(0, 10));
    }
  }

  Future<void> update() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateWorkDialog(api: api, day: day!),
    );
    if (result != null && mounted) {
      setState(() => day = result);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Daily progress saved.')));
    }
  }

  Widget card(Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final data = day;
    final result = data?['result'] as Map<String, dynamic>?;
    final summary = data?['summary'] as Map<String, dynamic>?;
    final score = (result?['score'] as num? ?? 0).toDouble();
    final overall = (summary?['score'] as num? ?? 0).toDouble();
    final saved = data?['update'] as Map<String, dynamic>?;
    return ListView(
      key: const PageStorageKey('tracker'),
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Daily Work Tracker',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Your study plan, one day at a time.',
          style: TextStyle(color: Color(0xff737686)),
        ),
        const SizedBox(height: 16),
        if (selectedDate != null)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: loading ? null : chooseDate,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(selectedDate!),
                ),
              ),
              IconButton(
                tooltip: 'Previous day',
                onPressed: loading || dates.indexOf(selectedDate!) <= 0
                    ? null
                    : () => loadDay(dates[dates.indexOf(selectedDate!) - 1]),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Next day',
                onPressed:
                    loading || dates.indexOf(selectedDate!) >= dates.length - 1
                    ? null
                    : () => loadDay(dates[dates.indexOf(selectedDate!) + 1]),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        const SizedBox(height: 16),
        if (loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          )
        else if (error != null)
          card(
            Column(
              children: [
                const Icon(Icons.cloud_off, size: 40),
                const SizedBox(height: 12),
                Text(error!, textAlign: TextAlign.center),
                TextButton(onPressed: initialize, child: const Text('Retry')),
              ],
            ),
          )
        else if (data != null) ...[
          card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['phase'] as String,
                  style: const TextStyle(
                    color: Color(0xff004ac6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 18,
                  runSpacing: 8,
                  children: [
                    Text(
                      '${score.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: (data['planned_hours'] as num) > 0
                          ? update
                          : null,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Update Tracker'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  value: score / 100,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(8),
                  semanticsLabel: 'Daily task progress',
                  semanticsValue: '$score',
                ),
                const SizedBox(height: 12),
                Text(
                  (data['planned_hours'] as num) == 0
                      ? 'No planned study hours. This day is excluded from scoring.'
                      : '${saved?['status'] ?? 'Not completed'} · ${saved?['hours'] ?? 0} / ${data['planned_hours']} hours',
                ),
                if (saved != null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Your latest update',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(saved['description'] as String),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Daily totals replace your previous entry. Scores are estimates based on task text, status and hours.',
                  style: TextStyle(fontSize: 12, color: Color(0xff737686)),
                ),
              ],
            ),
          ),
          card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Today’s plan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                for (final task in data['tasks'] as List)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task['label'] as String,
                          style: const TextStyle(
                            color: Color(0xff004ac6),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(task['text'] as String),
                      ],
                    ),
                  ),
                if ((data['schedule_note'] as String).isNotEmpty) ...[
                  const Divider(height: 28),
                  Text(data['schedule_note'] as String),
                ],
              ],
            ),
          ),
          if (result != null)
            card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'How your score was calculated',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(result['explanation'] as String),
                  const SizedBox(height: 12),
                  Text(
                    'Task coverage: ${result['coverage']}% · Hours: ${result['hours_progress']}%',
                  ),
                  for (final task in result['breakdown'] as List)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '${task['label']}: ${task['coverage']}% match\nMatched: ${(task['matched_terms'] as List).isEmpty ? 'none' : (task['matched_terms'] as List).join(', ')}',
                      ),
                    ),
                ],
              ),
            ),
          card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Overall plan progress',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  '${overall.toStringAsFixed(1)}% · ${summary?['updated_days']} of ${summary?['total_days']} days updated',
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(value: overall / 100, minHeight: 8),
                const SizedBox(height: 12),
                Text(
                  '${summary?['logged_hours']} hours logged · ${summary?['planned_hours']} planned',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Weighted by each day’s planned hours across the full plan. Days without an update count as zero.',
                  style: TextStyle(fontSize: 12, color: Color(0xff737686)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class UpdateWorkDialog extends StatefulWidget {
  const UpdateWorkDialog({super.key, required this.api, required this.day});
  final TrackerApi api;
  final Map<String, dynamic> day;
  @override
  State<UpdateWorkDialog> createState() => _UpdateWorkDialogState();
}

class _UpdateWorkDialogState extends State<UpdateWorkDialog> {
  final form = GlobalKey<FormState>();
  late final TextEditingController hours;
  late final TextEditingController description;
  late String status;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final saved = widget.day['update'] as Map<String, dynamic>?;
    status = saved?['status'] as String? ?? 'Not completed';
    hours = TextEditingController(text: '${saved?['hours'] ?? ''}');
    description = TextEditingController(
      text: saved?['description'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    hours.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await widget.api.save({
        'date': widget.day['date'],
        'status': status,
        'hours': double.parse(hours.text.trim()),
        'description': description.text.trim(),
      });
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: Text('Update work · ${widget.day['date']}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter the total work and hours for this day. Saving replaces the previous entry.',
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Task status'),
                  items: ['Not completed', 'In Progress', 'Completed']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) => setState(() => status = value!),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: hours,
                  enabled: !saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Total hours spent',
                    hintText: 'For example, 2.5',
                  ),
                  validator: (text) {
                    final value = double.tryParse(text?.trim() ?? '');
                    if (value == null ||
                        !value.isFinite ||
                        value < 0 ||
                        value > 24) {
                      return 'Enter a number from 0 to 24.';
                    }
                    if (status != 'Not completed' && value == 0) {
                      return 'Enter the time spent on your work.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: description,
                  enabled: !saving,
                  minLines: 4,
                  maxLines: 7,
                  maxLength: 5000,
                  decoration: const InputDecoration(
                    labelText: 'What did you work on?',
                    alignLabelWithHint: true,
                    hintText:
                        'Describe the topics covered, exercises solved and review you finished.',
                  ),
                  validator: (text) => text == null || text.trim().isEmpty
                      ? 'Describe your work before saving.'
                      : null,
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : submit,
          child: Text(saving ? 'Calculating…' : 'Save progress'),
        ),
      ],
    ),
  );
}

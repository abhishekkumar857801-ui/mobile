import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/session.dart';

Color hexColor(String hex, [Color? fallback]) {
  final color = hex.toLowerCase();
  if (color == '#14213d') return AppColors.navy;
  if (color == '#f4ede0') return AppColors.cream;
  if (color == '#ff6b5b') return AppColors.coral;
  return fallback ?? AppColors.primary;
}

/// The three brand colors and blends for borders, surfaces and muted text.
class AppColors {
  static bool dark = false;
  static const navy = Color(0xFF14213D);
  static const cream = Color(0xFFF4EDE0);
  static const coral = Color(0xFFFF6B5B);

  static Color _blend(Color base, Color tint, double amount) =>
      Color.lerp(base, tint, amount)!;

  static Color get bg => dark ? navy : cream;
  static Color get surface => dark ? _blend(navy, cream, .06) : cream;
  static Color get surface2 => _blend(bg, text, .09);
  static Color get border => _blend(bg, text, .16);
  static Color get borderStrong => _blend(bg, text, .35);
  static Color get text => dark ? cream : navy;
  static Color get text2 => _blend(text, bg, .20);
  static Color get muted => _blend(text, bg, .28);
  static Color get navy2 => _blend(navy, cream, .12);
  static Color get navyInk => _blend(cream, navy, .15);
  static Color get strong => text;
  static Color get onStrong => bg;
  static Color get strongSoft => _blend(bg, text, .10);
  static Color get primary => coral;
  static Color get primarySoft => _blend(bg, coral, .20);
  static Color get onPrimary => navy;
  static Color get danger => dangerInk;
  static Color get dangerInk => dark ? coral : _blend(navy, coral, .28);
  static Color get dangerSoft => primarySoft;
  static Color get board => surface2;
  static Color get boardLine => border;
  static Color get accent => text;
  static Color get onAccent => bg;
  static Color get accentSoft => strongSoft;
  static Color get accentInk => text;
  static Color get live => coral;
  static Color get success => text;
  static Color get warn => text;
  static Color get info => text;
}

const monoFont = 'ChivoMono';

final _figure = RegExp(r'(\d+d|\b[A-Z][a-z]{2} \d{1,2}\b|\b\d{1,2} [A-Z][a-z]{2}\b|\btoday\b|\btomorrow\b)');

/// "Due in 3d", "1d overdue", "12 Dec": only the date or count is set in
/// Chivo Mono; the words around it stay in Chivo.
Widget figureText(String text, TextStyle style) {
  final spans = <TextSpan>[];
  var last = 0;
  for (final m in _figure.allMatches(text)) {
    if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
    spans.add(TextSpan(text: m.group(0), style: const TextStyle(fontFamily: monoFont)));
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return Text.rich(TextSpan(style: style, children: spans));
}

/// Only critical tickets get a coral tint; every other ticket is plain.
Color fareColor(String priority) => priority == 'critical' ? AppColors.dangerSoft : AppColors.surface;

class BrandLogo extends StatelessWidget {
  final double size;
  /// Adds a cream ring so the icon stands out on coloured backgrounds.
  final bool onColor;
  const BrandLogo({super.key, this.size = 44, this.onColor = false});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.25),
          border: onColor ? Border.all(color: AppColors.cream, width: 2) : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.22),
          child: Image.asset('assets/icon/icon.png', width: size, height: size, filterQuality: FilterQuality.medium),
        ),
      );
}

Color avatarColorFor(AppUser user) {
  final key = user.id.isEmpty ? user.name : user.id;
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0xFFFFFFFF;
  }
  return hash.isEven ? AppColors.navy : Color.lerp(AppColors.navy, AppColors.coral, .40)!;
}

String initials(String name) =>
    name.split(' ').where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();

class UserAvatar extends StatelessWidget {
  final AppUser? user;
  final double radius;
  const UserAvatar(this.user, {super.key, this.radius = 14});

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.person_outline, size: radius, color: Theme.of(context).colorScheme.outline),
      );
    }
    final u = user!;
    return CircleAvatar(
      radius: radius,
      backgroundColor: avatarColorFor(u),
      foregroundImage: u.avatarUrl.isNotEmpty ? NetworkImage(session.api.fileUrl(u.avatarUrl)) : null,
      child: Text(initials(u.name), style: TextStyle(color: AppColors.cream, fontSize: radius * 0.75, fontWeight: FontWeight.w700)),
    );
  }
}

// Two colours: red for critical/high/late/overloaded, quiet ink for the rest.
Map<String, Color> get priorityColors => {
      'low': AppColors.muted,
      'medium': AppColors.muted,
      'high': AppColors.danger,
      'critical': AppColors.danger,
    };

Map<String, Color> get statusColors => {
      'todo': AppColors.muted,
      'in_progress': AppColors.text2,
      'review': AppColors.text2,
      'done': AppColors.text2,
    };

Map<String, Color> get levelColors => {
      'overloaded': AppColors.danger,
      'critical': AppColors.danger,
      'high': AppColors.danger,
      'busy': AppColors.text2,
      'medium': AppColors.text2,
      'balanced': AppColors.text2,
      'available': AppColors.muted,
      'low': AppColors.muted,
      'done': AppColors.muted,
    };

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

/// "Due today", "2d overdue", ... plus a colour for urgency.
(String, Color?) dueLabel(Task t) {
  if (t.isDone) return ('Completed', null);
  final d = t.dueDate;
  if (d == null) return ('No due date', null);
  final today = DateTime.now();
  final days = DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
  if (days < 0) return ('${-days}d overdue', AppColors.danger);
  if (days == 0) return ('Due today', AppColors.danger);
  if (days == 1) return ('Due tomorrow', null);
  if (days <= 7) return ('Due in ${days}d', null);
  return (DateFormat('d MMM').format(d), null);
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              SizedBox(height: 4),
              Text(subtitle!, style: TextStyle(color: Theme.of(context).colorScheme.outline), textAlign: TextAlign.center),
            ],
          ]),
        ),
      );
}

/// The punch row: each stage the task has passed is punched (navy), in fixed
/// positions so any two tickets compare at a glance.
class PunchRow extends StatelessWidget {
  final String status;
  /// When set, each stage is a real button that moves the ticket there.
  final ValueChanged<String>? onPunch;
  const PunchRow(this.status, {super.key, this.onPunch});

  static const _labels = {'todo': 'To do', 'in_progress': 'Doing', 'review': 'Review', 'done': 'Done'};

  @override
  Widget build(BuildContext context) {
    final current = taskStatuses.indexOf(status);
    final interactive = onPunch != null;
    return Row(children: [
      for (var i = 0; i < taskStatuses.length; i++) ...[
        if (i > 0) SizedBox(width: 4),
        Expanded(child: _cell(i, current, interactive)),
      ],
    ]);
  }

  Widget _cell(int i, int current, bool interactive) {
    final key = taskStatuses[i];
    final punched = i <= current;
    final label = _labels[key] ?? key;
    final box = Container(
      constraints: BoxConstraints(minHeight: interactive ? 48 : 30),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: punched ? AppColors.accent : AppColors.accentSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: punched ? AppColors.onAccent : AppColors.accentInk),
      ),
    );
    if (!interactive) {
      return Semantics(label: '$label${i == current ? ', current stage' : ''}', child: ExcludeSemantics(child: box));
    }
    return Semantics(
      button: true,
      selected: i == current,
      label: i == current ? '$label, current stage' : 'Move to $label',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: i == current ? null : () => onPunch!(key),
            child: box,
          ),
        ),
      ),
    );
  }
}

/// A task drawn as a bus ticket: serial and fare class (priority) on the stub,
/// title, where/when, and the punch row. The fare colour owns the whole ticket.
class TaskTile extends StatelessWidget {
  final Task task;
  final VoidCallback onTap;
  final bool showTeam;
  /// Move the ticket to another stage straight from the punch row (only when allowed).
  final ValueChanged<String>? onPunch;
  const TaskTile({super.key, required this.task, required this.onTap, this.showTeam = true, this.onPunch});

  @override
  Widget build(BuildContext context) {
    final (due, dueColor) = dueLabel(task);
    final late = task.isOverdue;
    final ground = task.isDone ? AppColors.surface : fareColor(task.priority);
    final meta = TextStyle(fontSize: 13, color: AppColors.text2);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: ground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: task.priority == 'critical' && !task.isDone ? AppColors.danger.withValues(alpha: 0.35) : AppColors.boardLine),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(task.serial, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.muted)),
                Spacer(),
                _PriorityPill(task.priority),
              ]),
              SizedBox(height: 6),
              Text(
                task.title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  height: 1.3,
                  color: task.isDone ? AppColors.text2 : AppColors.text,
                ),
              ),
              SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if ((showTeam && task.teamName.isNotEmpty) || task.project != null)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          [if (showTeam && task.teamName.isNotEmpty) task.teamName, task.project?.name ?? ''].where((s) => s.isNotEmpty).join(' · '),
                          style: meta,
                        ),
                      ]),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(task.isDone ? Icons.check_circle_outline : Icons.event_outlined, size: 15, color: late ? AppColors.dangerInk : AppColors.text2),
                      SizedBox(width: 3),
                      figureText(due, meta.copyWith(color: late ? AppColors.dangerInk : null, fontWeight: late ? FontWeight.w700 : null)),
                    ]),
                    if (task.attachments.isNotEmpty)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.attach_file, size: 15, color: AppColors.text2),
                        Text('${task.attachments.length}', style: meta),
                      ]),
                  ]),
                ),
                if (!showTeam) ...[SizedBox(width: 8), UserAvatar(task.assignee)],
              ]),
              Padding(
                padding: EdgeInsets.only(top: 10),
                child: CustomPaint(painter: _PerforationPainter(), child: SizedBox(height: 2, width: double.infinity)),
              ),
              SizedBox(height: 8),
              PunchRow(task.status, onPunch: onPunch),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Dashed tear line between the ticket body and its punch row.
class _PerforationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.boardLine
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(0, 1), Offset(size.width, 1), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


/// Soft priority label: critical red, high orange, medium blue, low grey.
class _PriorityPill extends StatelessWidget {
  final String priority;
  const _PriorityPill(this.priority);

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (priority) {
      'critical' => (AppColors.dangerSoft, AppColors.dangerInk),
      'high' => (AppColors.surface2, AppColors.dangerInk),
      'low' => (AppColors.surface2, AppColors.muted),
      _ => (AppColors.accentSoft, AppColors.accentInk),
    };
    final label = priority.isEmpty ? priority : priority[0].toUpperCase() + priority.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

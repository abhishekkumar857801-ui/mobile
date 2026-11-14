import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';

Color hexColor(String hex, [Color fallback = AppColors.primary]) {
  final h = hex.replaceFirst('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v == null ? fallback : Color(v);
}

/// Light palette with bright accents, shared with the web app.
class AppColors {
  static const bg = Color(0xFFF4F7FC);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF1F5FB);
  static const border = Color(0xFFE2E8F0);
  static const text = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const primary = Color(0xFF2563EB);
  static const primarySoft = Color(0xFFE0EBFF);
  static const onPrimary = Colors.white;
  static const yellow = Color(0xFFFACC15);
  static const pink = Color(0xFFEC4899);
  static const violet = Color(0xFF8B5CF6);
  static const orange = Color(0xFFF97316);
  static const success = Color(0xFF16A34A);
  static const warn = Color(0xFFEA580C);
  static const danger = Color(0xFFE11D48);
  static const info = Color(0xFF0EA5E9);
}

class BrandLogo extends StatelessWidget {
  final double size;
  /// Adds a white ring so the blue icon stands out on coloured backgrounds.
  final bool onColor;
  const BrandLogo({super.key, this.size = 44, this.onColor = false});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.25),
          border: onColor ? Border.all(color: Colors.white, width: 2) : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.22),
          child: Image.asset('assets/icon/icon.png', width: size, height: size, filterQuality: FilterQuality.medium),
        ),
      );
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
    return CircleAvatar(
      radius: radius,
      backgroundColor: hexColor(user!.avatarColor),
      child: Text(initials(user!.name), style: TextStyle(color: Colors.white, fontSize: radius * 0.75, fontWeight: FontWeight.w700)),
    );
  }
}

const priorityColors = {
  'low': Color(0xFF16A34A),
  'medium': Color(0xFF0EA5E9),
  'high': Color(0xFFF97316),
  'critical': Color(0xFFE11D48),
};

const statusColors = {
  'todo': Color(0xFF94A3B8),
  'in_progress': Color(0xFF0EA5E9),
  'review': Color(0xFFF97316),
  'done': Color(0xFF16A34A),
};

const levelColors = {
  'overloaded': Color(0xFFE11D48),
  'critical': Color(0xFFE11D48),
  'busy': Color(0xFFF97316),
  'high': Color(0xFFF97316),
  'balanced': Color(0xFF0EA5E9),
  'medium': Color(0xFF0EA5E9),
  'available': Color(0xFF16A34A),
  'low': Color(0xFF16A34A),
  'done': Color(0xFF16A34A),
};

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

/// "Due today", "2d overdue", ... plus a colour for urgency.
(String, Color?) dueLabel(Task t) {
  if (t.isDone) return ('Completed', const Color(0xFF16A34A));
  final d = t.dueDate;
  if (d == null) return ('No due date', null);
  final today = DateTime.now();
  final days = DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
  if (days < 0) return ('${-days}d overdue', const Color(0xFFE11D48));
  if (days == 0) return ('Due today', const Color(0xFFF97316));
  if (days == 1) return ('Due tomorrow', const Color(0xFFF97316));
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
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: TextStyle(color: Theme.of(context).colorScheme.outline), textAlign: TextAlign.center),
            ],
          ]),
        ),
      );
}

class TaskTile extends StatelessWidget {
  final Task task;
  final VoidCallback onTap;
  final bool showTeam;
  const TaskTile({super.key, required this.task, required this.onTap, this.showTeam = true});

  @override
  Widget build(BuildContext context) {
    final (due, dueColor) = dueLabel(task);
    final projectColor = hexColor(task.project?.color ?? '#6366f1');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: projectColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
              child: Icon(
                task.isDone ? Icons.check_circle_rounded : (task.isOverdue ? Icons.local_fire_department_rounded : Icons.radio_button_unchecked),
                color: task.isDone ? const Color(0xFF16A34A) : (task.isOverdue ? const Color(0xFFE11D48) : projectColor),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  task.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    decoration: task.isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [if (showTeam && task.teamName.isNotEmpty) task.teamName, task.project?.name ?? ''].where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Pill(statusLabels[task.status] ?? task.status, statusColors[task.status] ?? Colors.grey),
                  const SizedBox(width: 6),
                  Pill(task.priority, priorityColors[task.priority] ?? Colors.grey),
                  const Spacer(),
                  Text(due, style: TextStyle(fontSize: 12, color: dueColor, fontWeight: dueColor != null ? FontWeight.w600 : null)),
                ]),
              ]),
            ),
            if (!showTeam) ...[const SizedBox(width: 10), UserAvatar(task.assignee)],
          ]),
        ),
      ),
    );
  }
}

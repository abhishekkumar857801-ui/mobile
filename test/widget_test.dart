import 'package:flutter_test/flutter_test.dart';
import 'package:teamflow/models.dart';

void main() {
  test('Task parses API JSON and flags overdue work', () {
    final t = Task.fromJson({
      '_id': 't1',
      'team': {'_id': 'team1', 'name': 'Club'},
      'project': {'_id': 'p1', 'name': 'Hackathon', 'color': '#ef4444'},
      'title': 'Email sponsors',
      'assignee': {'_id': 'u1', 'name': 'Rahul Menon'},
      'status': 'in_progress',
      'priority': 'critical',
      'dueDate': DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String(),
      'estimateHours': 8,
      'progress': 30,
      'attachments': [],
    });
    expect(t.teamName, 'Club');
    expect(t.project?.name, 'Hackathon');
    expect(t.assignee?.name, 'Rahul Menon');
    expect(t.isOverdue, isTrue);
    expect(t.progress, 30);
  });
}

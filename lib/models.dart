// Plain data classes mirroring the MongoDB documents returned by the API.

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
double _num(dynamic v, [double fallback = 0]) => v is num ? v.toDouble() : double.tryParse('$v') ?? fallback;

class AppUser {
  final String id;
  final String name;
  final String email;
  final String avatarColor;
  final double weeklyCapacity;

  AppUser({required this.id, required this.name, this.email = '', this.avatarColor = '#6366f1', this.weeklyCapacity = 20});

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['_id'].toString(),
        name: j['name'] ?? '',
        email: j['email'] ?? '',
        avatarColor: j['avatarColor'] ?? '#6366f1',
        weeklyCapacity: _num(j['weeklyCapacity'], 20),
      );

  /// Accepts a populated user object or a bare id.
  static AppUser? maybe(dynamic v) {
    if (v is Map<String, dynamic>) return AppUser.fromJson(v);
    return null;
  }
}

class TeamMember {
  final AppUser user;
  final String role;
  TeamMember(this.user, this.role);
}

class Team {
  final String id;
  final String name;
  final String description;
  final String joinCode;
  final String myRole;
  final List<TeamMember> members;

  Team({required this.id, required this.name, required this.description, required this.joinCode, required this.myRole, required this.members});

  bool get isManager => myRole == 'owner' || myRole == 'manager';

  factory Team.fromJson(Map<String, dynamic> j) => Team(
        id: j['_id'].toString(),
        name: j['name'] ?? '',
        description: j['description'] ?? '',
        joinCode: j['joinCode'] ?? '',
        myRole: j['myRole'] ?? 'member',
        members: ((j['members'] as List?) ?? [])
            .where((m) => m['user'] is Map)
            .map((m) => TeamMember(AppUser.fromJson(m['user']), m['role'] ?? 'member'))
            .toList(),
      );
}

class Project {
  final String id;
  final String name;
  final String color;
  final DateTime? deadline;
  final int taskCount;
  final int doneCount;

  Project({required this.id, required this.name, this.color = '#6366f1', this.deadline, this.taskCount = 0, this.doneCount = 0});

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['_id'].toString(),
        name: j['name'] ?? '',
        color: j['color'] ?? '#6366f1',
        deadline: _date(j['deadline']),
        taskCount: (j['taskCount'] ?? 0) as int,
        doneCount: (j['doneCount'] ?? 0) as int,
      );

  static Project? maybe(dynamic v) => v is Map<String, dynamic> ? Project.fromJson(v) : null;
}

class Attachment {
  final String id;
  final String url;
  final String name;
  final String mimeType;
  Attachment({required this.id, required this.url, required this.name, required this.mimeType});

  bool get isImage => mimeType.startsWith('image/');

  factory Attachment.fromJson(Map<String, dynamic> j) =>
      Attachment(id: j['_id'].toString(), url: j['url'] ?? '', name: j['name'] ?? '', mimeType: j['mimeType'] ?? '');
}

const taskStatuses = ['todo', 'in_progress', 'review', 'done'];
const statusLabels = {'todo': 'To do', 'in_progress': 'In progress', 'review': 'In review', 'done': 'Done'};
const taskPriorities = ['low', 'medium', 'high', 'critical'];

class Task {
  final String id;
  final String teamId;
  final String teamName;
  final Project? project;
  final String title;
  final String description;
  final AppUser? assignee;
  final String status;
  final String priority;
  final DateTime? dueDate;
  final double estimateHours;
  final double progress;
  final List<Attachment> attachments;

  Task({
    required this.id,
    required this.teamId,
    this.teamName = '',
    this.project,
    required this.title,
    this.description = '',
    this.assignee,
    this.status = 'todo',
    this.priority = 'medium',
    this.dueDate,
    this.estimateHours = 2,
    this.progress = 0,
    this.attachments = const [],
  });

  bool get isDone => status == 'done';
  bool get isOverdue => !isDone && dueDate != null && dueDate!.isBefore(DateTime.now());

  factory Task.fromJson(Map<String, dynamic> j) {
    final team = j['team'];
    return Task(
      id: j['_id'].toString(),
      teamId: team is Map ? team['_id'].toString() : team.toString(),
      teamName: team is Map ? (team['name'] ?? '') : '',
      project: Project.maybe(j['project']),
      title: j['title'] ?? '',
      description: j['description'] ?? '',
      assignee: AppUser.maybe(j['assignee']),
      status: j['status'] ?? 'todo',
      priority: j['priority'] ?? 'medium',
      dueDate: _date(j['dueDate']),
      estimateHours: _num(j['estimateHours'], 2),
      progress: _num(j['progress']),
      attachments: ((j['attachments'] as List?) ?? []).map((a) => Attachment.fromJson(a)).toList(),
    );
  }
}

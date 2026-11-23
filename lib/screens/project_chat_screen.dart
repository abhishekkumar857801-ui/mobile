import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../services/session.dart';
import '../widgets/common.dart';

class ChatMessage {
  final String id;
  final String text;
  final bool hasPhoto;
  final AppUser? sender;
  final DateTime createdAt;

  ChatMessage({required this.id, required this.text, required this.hasPhoto, required this.sender, required this.createdAt});

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['_id'].toString(),
        text: j['text'] ?? '',
        hasPhoto: j['photoType'] != null,
        sender: j['sender'] is Map<String, dynamic> ? AppUser.fromJson(j['sender']) : null,
        createdAt: DateTime.tryParse('${j['createdAt']}')?.toLocal() ?? DateTime.now(),
      );
}

/// Chat for one project. Every team member can read and post; messages
/// arrive live from the web app and other phones.
class ProjectChatScreen extends StatefulWidget {
  final Project project;
  final bool isManager;
  const ProjectChatScreen({super.key, required this.project, required this.isManager});

  @override
  State<ProjectChatScreen> createState() => _ProjectChatScreenState();
}

class _ProjectChatScreenState extends State<ProjectChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage>? _messages;
  bool _hasMore = false;
  bool _sending = false;
  String? _error;
  StreamSubscription<LiveEvent>? _sub;

  String get _base => '/projects/${widget.project.id}/messages';

  @override
  void initState() {
    super.initState();
    _load();
    _sub = session.events.listen((e) {
      final data = e.data;
      if (data is! Map || data['projectId'] != widget.project.id || !mounted) return;
      if (e.name == 'chat:message') {
        final m = ChatMessage.fromJson(Map<String, dynamic>.from(data['message'] as Map));
        setState(() {
          if (_messages != null && !_messages!.any((x) => x.id == m.id)) _messages!.add(m);
        });
        _scrollToBottom();
      } else if (e.name == 'chat:deleted') {
        setState(() => _messages?.removeWhere((x) => x.id == data['messageId']));
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _load() async {
    try {
      final res = await session.api.get(_base);
      if (!mounted) return;
      setState(() {
        _messages = (res['messages'] as List).map((m) => ChatMessage.fromJson(m)).toList();
        _hasMore = res['hasMore'] == true;
        _error = null;
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _loadOlder() async {
    final first = _messages?.firstOrNull;
    if (first == null) return;
    try {
      final before = Uri.encodeQueryComponent(first.createdAt.toUtc().toIso8601String());
      final res = await session.api.get('$_base?before=$before');
      if (!mounted) return;
      setState(() {
        _messages = [...(res['messages'] as List).map((m) => ChatMessage.fromJson(m)), ..._messages!];
        _hasMore = res['hasMore'] == true;
      });
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  Future<void> _sharePhoto() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final photo = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
      if (photo == null || !mounted) return;
      if (await photo.length() > 8 * 1024 * 1024) {
        if (mounted) showSnack(context, 'Choose a photo under 8 MB.');
        return;
      }
      if (!mounted) return;
      final res = await session.api.uploadFile('$_base/photo', File(photo.path));
      if (!mounted) return;
      final message = ChatMessage.fromJson(res['message']);
      setState(() {
        if (!_messages!.any((m) => m.id == message.id)) _messages!.add(message);
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await session.api.post(_base, {'text': text});
      final m = ChatMessage.fromJson(res['message']);
      if (!mounted) return;
      setState(() {
        if (!_messages!.any((x) => x.id == m.id)) _messages!.add(m);
        _input.clear();
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(ChatMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete message?'),
        content: Text(m.hasPhoto ? 'Shared photo' : m.text, maxLines: 3, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await session.api.delete('$_base/${m.id}');
      if (mounted) setState(() => _messages!.removeWhere((x) => x.id == m.id));
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    final diff = DateTime(now.year, now.month, now.day).difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('d MMM yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final me = session.user?.id;
    final messages = _messages;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.project.name, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Text('Project chat', style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: messages == null
              ? (_error != null
                  ? EmptyState(icon: Icons.cloud_off, title: 'Could not load chat', subtitle: _error)
                  : Center(child: CircularProgressIndicator()))
              : messages.isEmpty
                  ? EmptyState(icon: Icons.chat_bubble_outline, title: 'No messages yet', subtitle: 'Start the conversation about ${widget.project.name}.')
                  : ListView.builder(
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
                      itemCount: messages.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_hasMore && index == 0) {
                          return Center(child: TextButton(onPressed: _loadOlder, child: Text('Load older messages')));
                        }
                        final i = index - (_hasMore ? 1 : 0);
                        final m = messages[i];
                        final prev = i > 0 ? messages[i - 1] : null;
                        final newDay = prev == null || _dayLabel(prev.createdAt) != _dayLabel(m.createdAt);
                        final grouped = !newDay &&
                            prev.sender?.id == m.sender?.id &&
                            m.createdAt.difference(prev.createdAt).inMinutes < 5;
                        final mine = m.sender?.id == me;
                        return Column(children: [
                          if (newDay)
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Pill(_dayLabel(m.createdAt), AppColors.muted),
                            ),
                          _Bubble(
                            message: m,
                            photoPath: '$_base/${m.id}/photo',
                            mine: mine,
                            grouped: grouped,
                            onLongPress: mine || widget.isManager ? () => _delete(m) : null,
                          ),
                        ]);
                      },
                    ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              IconButton(
                tooltip: 'Share photo',
                onPressed: _sending || messages == null ? null : _sharePhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined),
              ),
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Message ${widget.project.name}…',
                    counterText: '',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(width: 6),
              IconButton.filled(
                tooltip: 'Send',
                onPressed: _input.text.trim().isEmpty || _sending ? null : _send,
                icon: _sending
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cream))
                    : Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final String photoPath;
  final bool mine;
  final bool grouped;
  final VoidCallback? onLongPress;
  const _Bubble({required this.message, required this.photoPath, required this.mine, required this.grouped, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(message.createdAt);
    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        padding: EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          color: mine ? AppColors.navy : AppColors.surface,
          border: mine ? null : Border.all(color: AppColors.border),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          if (message.hasPhoto)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                session.api.endpointUrl(photoPath),
                headers: {'Authorization': 'Bearer ${session.api.token}'},
                height: 200,
                fit: BoxFit.contain,
                semanticLabel: 'Shared photo',
                errorBuilder: (_, error, stack) => const Text('Photo unavailable'),
              ),
            ),
          if (message.text.isNotEmpty) Text(message.text, style: TextStyle(color: mine ? AppColors.cream : AppColors.text, fontSize: 15, height: 1.35)),
          SizedBox(height: 2),
          Text(time, style: TextStyle(fontSize: 10, color: mine ? AppColors.cream.withValues(alpha: .70) : AppColors.muted)),
        ]),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: grouped ? 2 : 8),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            grouped ? SizedBox(width: 28) : UserAvatar(message.sender),
            SizedBox(width: 8),
          ],
          Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            if (!mine && !grouped)
              Padding(
                padding: EdgeInsets.only(left: 4, bottom: 2),
                child: Text(message.sender?.name ?? 'Former member',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted)),
              ),
            bubble,
          ]),
        ],
      ),
    );
  }
}

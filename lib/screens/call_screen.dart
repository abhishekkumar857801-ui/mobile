import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/session.dart';
import '../widgets/common.dart';

// Public STUN servers let two devices discover how to reach each other.
const _iceServers = {
  'iceServers': [
    {'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']},
  ],
  'sdpSemantics': 'unified-plan',
};

class _Peer {
  final String socketId;
  String name = 'Joining…';
  String color = '#14213d';
  RTCPeerConnection? pc;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  bool hasStream = false;
  bool audio = true;
  bool video = true;
  bool failed = false;
  bool hasRemote = false;
  final List<RTCIceCandidate> pendingIce = [];

  _Peer(this.socketId);
}

/// Built-in project video meeting (WebRTC mesh). Every participant connects
/// directly to every other one; the TeamFlow server only relays the set-up
/// messages. Works together with the web app's meeting room.
class CallScreen extends StatefulWidget {
  final String projectId;
  final String projectName;
  final bool isManager;
  const CallScreen({super.key, required this.projectId, required this.projectName, required this.isManager});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  final Map<String, _Peer> _peers = {};
  StreamSubscription<LiveEvent>? _sub;
  String _status = 'Connecting…';
  String? _warning;
  bool _micOn = true;
  bool _camOn = true;
  bool _hasMic = false;
  bool _hasCam = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _localRenderer.initialize();
    _sub = session.events.listen(_onEvent);

    // 1. Camera + mic (fall back to mic only, then to joining without media).
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': 'user', 'width': 640, 'height': 360},
      });
    } catch (_) {
      try {
        _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
        _warning = 'Camera not available. You joined with audio only.';
      } catch (_) {
        _warning = 'Camera and microphone are not allowed. You can still see and hear others.';
      }
    }
    if (_closed) {
      await _stopLocal();
      return;
    }
    _hasMic = _localStream?.getAudioTracks().isNotEmpty ?? false;
    _hasCam = _localStream?.getVideoTracks().isNotEmpty ?? false;
    _micOn = _hasMic;
    _camOn = _hasCam;
    _localRenderer.srcObject = _localStream;
    Helper.setSpeakerphoneOn(true).catchError((_) {});
    if (mounted) setState(() {});

    // 2. Join the call and connect to everyone already in it.
    final res = await session.emitAck('call:join', {'projectId': widget.projectId});
    if (_closed) return;
    if (res['ok'] != true) {
      setState(() => _status = '${res['error'] ?? 'Could not join the meeting'}');
      return;
    }
    setState(() => _status = '');
    _sendMedia();
    for (final p in (res['peers'] as List? ?? [])) {
      final peer = await _createPeer(p['socketId'].toString(), user: p['user']);
      final offer = await peer.pc!.createOffer({});
      await peer.pc!.setLocalDescription(offer);
      session.emit('call:signal', {
        'to': peer.socketId,
        'data': {'type': 'offer', 'sdp': offer.sdp},
      });
    }
  }

  Future<_Peer> _createPeer(String socketId, {dynamic user}) async {
    final existing = _peers[socketId];
    if (existing?.pc != null) return existing!;
    final peer = existing ?? _Peer(socketId);
    if (user is Map) {
      peer.name = '${user['name'] ?? peer.name}';
      peer.color = '${user['avatarColor'] ?? peer.color}';
    }
    _peers[socketId] = peer;
    await peer.renderer.initialize();

    final pc = await createPeerConnection(_iceServers);
    peer.pc = pc;
    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
    }
    // Still receive audio/video even if we have no camera or mic.
    if (!_hasMic) {
      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
    }
    if (!_hasCam) {
      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
    }
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      session.emit('call:signal', {
        'to': socketId,
        'data': {'type': 'candidate', 'candidate': candidate.toMap()},
      });
    };
    pc.onTrack = (event) {
      if (event.streams.isEmpty) return;
      peer.renderer.srcObject = event.streams.first;
      peer.hasStream = true;
      if (mounted) setState(() {});
    };
    pc.onConnectionState = (state) {
      peer.failed = state == RTCPeerConnectionState.RTCPeerConnectionStateFailed;
      if (mounted) setState(() {});
    };
    if (mounted) setState(() {});
    return peer;
  }

  Future<void> _flushIce(_Peer peer) async {
    final queued = List<RTCIceCandidate>.from(peer.pendingIce);
    peer.pendingIce.clear();
    for (final c in queued) {
      await peer.pc?.addCandidate(c).catchError((_) {});
    }
  }

  Future<void> _onEvent(LiveEvent e) async {
    if (_closed) return;
    final data = e.data;
    if (data is! Map) return;
    switch (e.name) {
      case 'call:signal':
        await _onSignal(data['from'].toString(), Map<String, dynamic>.from(data['data'] as Map));
      case 'call:peer-joined':
        if (data['projectId'] != widget.projectId) return;
        final id = data['socketId'].toString();
        final user = data['user'];
        final peer = _peers.putIfAbsent(id, () => _Peer(id));
        if (user is Map) {
          peer.name = '${user['name'] ?? peer.name}';
          peer.color = '${user['avatarColor'] ?? peer.color}';
        }
        setState(() {});
      case 'call:peer-left':
        await _removePeer(data['socketId'].toString());
      case 'call:peer-media':
        final peer = _peers[data['socketId'].toString()];
        if (peer != null) {
          setState(() {
            peer.audio = data['audio'] == true;
            peer.video = data['video'] == true;
          });
        }
      case 'call:ended':
        if (data['projectId'] != widget.projectId) return;
        setState(() => _status = data['reason'] == 'empty' ? 'Everyone left the meeting.' : 'The meeting was ended by the host.');
        await _teardown(sendLeave: false);
        await Future.delayed(Duration(milliseconds: 1400));
        if (mounted) Navigator.of(context).maybePop();
    }
  }

  Future<void> _onSignal(String from, Map<String, dynamic> data) async {
    try {
      switch (data['type']) {
        case 'offer':
          final peer = await _createPeer(from);
          await peer.pc!.setRemoteDescription(RTCSessionDescription(data['sdp'], 'offer'));
          peer.hasRemote = true;
          await _flushIce(peer);
          final answer = await peer.pc!.createAnswer({});
          await peer.pc!.setLocalDescription(answer);
          session.emit('call:signal', {
            'to': from,
            'data': {'type': 'answer', 'sdp': answer.sdp},
          });
          _sendMedia(); // tell the newcomer whether our mic/camera are on
        case 'answer':
          final peer = _peers[from];
          if (peer?.pc == null || peer!.hasRemote) return;
          await peer.pc!.setRemoteDescription(RTCSessionDescription(data['sdp'], 'answer'));
          peer.hasRemote = true;
          await _flushIce(peer);
        case 'candidate':
          final c = Map<String, dynamic>.from(data['candidate'] as Map);
          final candidate = RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']);
          final peer = _peers[from];
          if (peer?.pc != null && peer!.hasRemote) {
            await peer.pc!.addCandidate(candidate).catchError((_) {});
          } else {
            _peers.putIfAbsent(from, () => _Peer(from)).pendingIce.add(candidate);
          }
      }
    } catch (err) {
      debugPrint('WebRTC signal error: $err');
    }
  }

  void _sendMedia() => session.emit('call:media', {'audio': _micOn, 'video': _camOn});

  Future<void> _removePeer(String socketId) async {
    final peer = _peers.remove(socketId);
    if (peer == null) return;
    await peer.pc?.close();
    peer.renderer.srcObject = null;
    await peer.renderer.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _stopLocal() async {
    for (final t in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
  }

  Future<void> _teardown({bool sendLeave = true}) async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    for (final id in _peers.keys.toList()) {
      await _removePeer(id);
    }
    _localRenderer.srcObject = null;
    await _stopLocal();
    if (sendLeave) session.emit('call:leave', {});
  }

  void _toggleMic() {
    final tracks = _localStream?.getAudioTracks() ?? [];
    if (tracks.isEmpty) return;
    setState(() => _micOn = !_micOn);
    for (final t in tracks) {
      t.enabled = _micOn;
    }
    _sendMedia();
  }

  void _toggleCam() {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    setState(() => _camOn = !_camOn);
    for (final t in tracks) {
      t.enabled = _camOn;
    }
    _sendMedia();
  }

  Future<void> _switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  Future<void> _endForAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('End meeting for everyone?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('End meeting')),
        ],
      ),
    );
    if (ok != true) return;
    final res = await session.emitAck('call:end', {'projectId': widget.projectId});
    if (res['ok'] != true && mounted) showSnack(context, '${res['error']}');
  }

  @override
  void dispose() {
    _teardown();
    _localRenderer.dispose();
    super.dispose();
  }

  Widget _tile({required String name, required String color, required RTCVideoRenderer renderer, required bool showVideo, required bool micOn, bool mirror = false, bool failed = false}) {
    return Container(
      decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: [
        // Keep the renderer mounted so audio plays even with the camera off.
        Opacity(
          opacity: showVideo ? 1 : 0,
          child: RTCVideoView(renderer, mirror: mirror, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
        ),
        if (!showVideo)
          Center(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: hexColor(color),
              child: Text(initials(name), style: TextStyle(color: AppColors.cream, fontSize: 24, fontWeight: FontWeight.w700)),
            ),
          ),
        Positioned(
          left: 8,
          bottom: 8,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: const Color(0x8A14213D), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (!micOn) Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.mic_off, size: 14, color: AppColors.cream)),
              Text(failed ? '$name · connection problem' : name, style: TextStyle(color: AppColors.cream, fontSize: 12)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _roundButton({required IconData icon, required VoidCallback? onTap, bool off = false, Color? color, String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: color ?? (off ? AppColors.cream : AppColors.cream.withValues(alpha: .24)),
        shape: CircleBorder(),
        child: InkWell(
          customBorder: CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Icon(icon, color: off ? AppColors.navy : AppColors.cream, size: 24),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = session.user;
    final tiles = <Widget>[
      _tile(
        name: '${me?.name ?? 'You'} (you)',
        color: me?.avatarColor ?? '#14213d',
        renderer: _localRenderer,
        showVideo: _hasCam && _camOn,
        micOn: _micOn,
        mirror: true,
      ),
      for (final p in _peers.values)
        _tile(name: p.name, color: p.color, renderer: p.renderer, showVideo: p.hasStream && p.video, micOn: p.audio, failed: p.failed),
    ];
    final columns = tiles.length <= 2 ? 1 : 2;

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: AppColors.navy,
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.coral, borderRadius: BorderRadius.circular(6)),
                  child: Text('LIVE', style: TextStyle(color: AppColors.navy, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.projectName, style: TextStyle(color: AppColors.cream, fontWeight: FontWeight.w700, fontSize: 16), overflow: TextOverflow.ellipsis),
                    Text('${tiles.length} in meeting', style: TextStyle(color: AppColors.cream.withValues(alpha: .60), fontSize: 12)),
                  ]),
                ),
                if (_hasCam)
                  IconButton(onPressed: _switchCamera, icon: Icon(Icons.cameraswitch_outlined, color: AppColors.cream), tooltip: 'Switch camera'),
              ]),
            ),
            if (_status.isNotEmpty)
              Padding(padding: EdgeInsets.all(8), child: Text(_status, style: TextStyle(color: AppColors.cream.withValues(alpha: .70)))),
            if (_warning != null)
              Container(
                margin: EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(color: Color(0x26FF6B5B), borderRadius: BorderRadius.circular(10)),
                child: Text(_warning!, style: TextStyle(color: AppColors.cream, fontSize: 13)),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: LayoutBuilder(builder: (context, box) {
                  final rows = (tiles.length / columns).ceil();
                  final height = (box.maxHeight - (rows - 1) * 8) / rows;
                  final width = (box.maxWidth - (columns - 1) * 8) / columns;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final t in tiles) SizedBox(width: width, height: height, child: t)],
                  );
                }),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 18),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _roundButton(icon: _micOn ? Icons.mic : Icons.mic_off, off: !_micOn, onTap: _hasMic ? _toggleMic : null, tooltip: 'Microphone'),
                SizedBox(width: 14),
                _roundButton(icon: _camOn ? Icons.videocam : Icons.videocam_off, off: !_camOn, onTap: _hasCam ? _toggleCam : null, tooltip: 'Camera'),
                SizedBox(width: 14),
                _roundButton(
                  icon: Icons.call_end,
                  color: AppColors.coral,
                  tooltip: 'Leave',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                if (widget.isManager) ...[
                  SizedBox(width: 14),
                  TextButton(
                    onPressed: _endForAll,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.cream,
                      side: BorderSide(color: AppColors.cream.withValues(alpha: .38)),
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      shape: StadiumBorder(),
                    ),
                    child: Text('End for all'),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

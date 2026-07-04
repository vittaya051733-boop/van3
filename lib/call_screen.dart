import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models/user_profile.dart';
import 'services/agora_call_audio.dart';
import 'services/notification_service.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.channelName,
    required this.isVideo,
    required this.targetProfile,
    this.isIncoming = false,
    this.appIdOverride,
    this.tokenOverride,
    this.channelOverride,
  });

  final String channelName;
  final bool isVideo;
  final UserProfile targetProfile;
  final bool isIncoming;
  final String? appIdOverride;
  final String? tokenOverride;
  final String? channelOverride;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  static const String _defaultAgoraAppId = '37050f5308fd450ba070b53c01596c06';

  // Connection-stuck guards: end the call automatically if Agora cannot
  // establish a remote connection within these windows.
  static const Duration _joinChannelTimeout = Duration(seconds: 15);
  static const Duration _remoteConnectTimeout = Duration(seconds: 30);

  RtcEngine? _engine;
  bool _joined = false;
  int? _remoteUid;
  bool _speakerOn = false;
  bool _micMuted = false;
  bool _videoMuted = true;
  bool _incomingAccepted = false;
  bool _acceptingIncoming = false;
  bool _remoteConnected = false;
  bool _talkPhaseActive = false;
  DateTime? _callStart;
  Timer? _durationTimer;
  Timer? _joinChannelTimer;
  Timer? _remoteConnectTimer;
  bool _resultSent = false;
  bool _cancelSignalSent = false;
  String? _fatalError;
  String? _connectStatusOverride;

  late final String _activeToken;
  late final String _activeChannelId;
  AudioPlayer? _ringbackPlayer;

  DocumentReference<Map<String, dynamic>>? _sessionDocRef;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSubscription;
  bool _callSessionMarkedEnded = false;

  String get _effectiveAppId {
    final override = widget.appIdOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return _defaultAgoraAppId;
  }

  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    // วิดีโอคอลเปิดกล้องทันที, โทรเสียงไม่ใช้กล้อง
    _videoMuted = !widget.isVideo;
    _activeToken = widget.tokenOverride?.trim() ?? '';
    final overrideChannel = widget.channelOverride?.trim();
    _activeChannelId = (overrideChannel != null && overrideChannel.isNotEmpty)
        ? overrideChannel
        : widget.channelName.trim();

    if (_activeToken.isEmpty || _activeChannelId.isEmpty) {
      _fatalError = 'ไม่พบข้อมูลการโทรจากเซิร์ฟเวอร์ กรุณาลองใหม่อีกครั้ง';
      return;
    }

    _setupCallSessionTracking();

    if (!widget.isIncoming) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startOutgoingCall();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startRingtone('k-pop-ringtone-no-copyright-357142.mp3');
      });
    }
  }

  @override
  void dispose() {
    _stopRingback();
    _stopDurationTicker();
    _joinChannelTimer?.cancel();
    _remoteConnectTimer?.cancel();
    _sessionSubscription?.cancel();
    _sessionSubscription = null;
    _engine?.leaveChannel();
    _engine?.release();
    unawaited(_endCall());
    super.dispose();
  }

  Future<void> _startOutgoingCall() async {
    if (!await _ensurePermissions()) {
      return;
    }
    _startRingtone('topping-pop-sound-245150.mp3');
    await _initAgora();
    if (!mounted || _fatalError != null) {
      return;
    }
  }

  Future<bool> _ensurePermissions() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      _showPermissionError('ไมโครโฟน');
      return false;
    }

    if (widget.isVideo) {
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        _showPermissionError('กล้อง');
        return false;
      }
    }

    return true;
  }

  void _showPermissionError(String permissionName) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('ต้องอนุญาต$permissionNameก่อนจึงจะใช้การโทรได้')),
    );
  }

  Future<void> _initAgora() async {
    if (_engine != null) {
      return;
    }

    RtcEngine? engine;
    try {
      engine = createAgoraRtcEngine();
      await engine.initialize(
        RtcEngineContext(
          appId: _effectiveAppId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            debugPrint('[call] joined channel=${connection.channelId} uid=${connection.localUid} elapsed=${elapsed}ms');
            _joinChannelTimer?.cancel();
            if (!mounted) return;
            setState(() {
              _joined = true;
              _connectStatusOverride = null;
            });
            _armRemoteConnectTimer();
          },
          onUserJoined: (connection, remoteUid, elapsed) {
            if (connection.channelId != _activeChannelId || !mounted) return;
            debugPrint('[call] remote user joined uid=$remoteUid elapsed=${elapsed}ms');
            _remoteConnectTimer?.cancel();
            setState(() {
              _remoteUid = remoteUid;
              _remoteConnected = true;
              _callStart = DateTime.now();
              _connectStatusOverride = null;
            });
            unawaited(_updateCallSessionStatus('connected', extra: {
              'connectedAt': FieldValue.serverTimestamp(),
              'remoteAgoraUid': remoteUid,
            }));
            _startDurationTicker();
            unawaited(_beginTalkPhase());
          },
          onUserOffline: (connection, remoteUid, reason) {
            if (!mounted) return;
            setState(() {
              _remoteUid = null;
              _remoteConnected = false;
            });
            _stopDurationTicker();
            unawaited(_endCall(remoteEnded: true));
          },
          onConnectionStateChanged: (connection, state, reason) {
            debugPrint('[call] connectionState=$state reason=$reason');
            if (!mounted) return;
            if (state == ConnectionStateType.connectionStateReconnecting) {
              setState(() => _connectStatusOverride = 'กำลังเชื่อมต่อใหม่...');
            } else if (state == ConnectionStateType.connectionStateFailed) {
              setState(() {
                _fatalError = 'การเชื่อมต่อล้มเหลว กรุณาลองใหม่อีกครั้ง';
              });
              unawaited(_endCall());
            } else if (state == ConnectionStateType.connectionStateConnected) {
              setState(() => _connectStatusOverride = null);
            }
          },
          onError: (err, msg) {
            debugPrint('[call] agora error code=$err msg=$msg');
            if (!mounted) return;
            if (err == ErrorCodeType.errInvalidToken ||
                err == ErrorCodeType.errTokenExpired) {
              setState(() {
                _fatalError = 'Agora token ไม่ถูกต้องหรือหมดอายุ';
              });
              unawaited(_endCall(declined: true));
            }
          },
          onNetworkQuality: (connection, remoteUid, txQuality, rxQuality) {
            if (kDebugMode) {
              debugPrint(
                '[call] network channel=${connection.channelId} '
                'remoteUid=$remoteUid tx=$txQuality rx=$rxQuality',
              );
            }
          },
        ),
      );

      await AgoraCallAudio.configureCallEngine(
        engine,
        isVideo: widget.isVideo,
      );
      if (widget.isVideo && _videoMuted) {
        await engine.enableLocalVideo(false);
        await engine.muteLocalVideoStream(true);
      }
      await engine.muteLocalAudioStream(true);
      await engine.joinChannel(
        token: _activeToken,
        channelId: _activeChannelId,
        uid: 0,
        options: AgoraCallAudio.ringingMediaOptions(),
      );

      _armJoinChannelTimer();

      if (!mounted) {
        await engine.leaveChannel();
        await engine.release();
        return;
      }

      setState(() {
        _engine = engine;
      });
    } catch (error) {
      if (!mounted) {
        if (engine != null) {
          await engine.release();
        }
        return;
      }
      setState(() {
        _fatalError = 'ไม่สามารถเชื่อมต่อบริการโทรได้ ($error)';
      });
    }
  }

  void _startRingtone(String assetName) {
    _ringbackPlayer?.stop();
    _ringbackPlayer?.dispose();
    _ringbackPlayer = AudioPlayer();
    _ringbackPlayer!.setReleaseMode(ReleaseMode.loop);
    _ringbackPlayer!.play(AssetSource(assetName));
  }

  void _stopRingback() {
    _ringbackPlayer?.stop();
    _ringbackPlayer?.dispose();
    _ringbackPlayer = null;
  }

  void _setupCallSessionTracking() {
    if (_activeChannelId.isEmpty) return;
    _sessionDocRef = FirebaseFirestore.instance.collection('call_sessions').doc(_activeChannelId);
    _sessionSubscription = _sessionDocRef!.snapshots().listen(_handleSessionSnapshot);
    if (!widget.isIncoming) {
      unawaited(_createCallSessionDocument());
    }
  }

  void _handleSessionSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) return;
    final status = data['status'] as String?;
    if (status == 'accepted' || status == 'connected') {
      if (!mounted) return;
      _stopRingback();
      return;
    }
    if (status == 'ended') {
      final endedBy = data['endedBy'] as String?;
      if (endedBy != null && endedBy == _currentUserId) return;
      unawaited(_endCall(remoteEnded: true));
    }
  }

  Future<void> _createCallSessionDocument() async {
    final docRef = _sessionDocRef;
    if (docRef == null) return;

    await docRef.set({
      'channelId': _activeChannelId,
      'status': 'ringing',
      'isVideo': widget.isVideo,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (_currentUserId != null) 'callerId': _currentUserId,
      if (widget.targetProfile.uid.isNotEmpty) 'calleeId': widget.targetProfile.uid,
    }, SetOptions(merge: true));
  }

  Future<void> _updateCallSessionStatus(
    String status, {
    Map<String, dynamic>? extra,
    bool allowDuplicateEnd = false,
  }) async {
    final docRef = _sessionDocRef;
    if (docRef == null) return;
    if (status == 'ended' && _callSessionMarkedEnded && !allowDuplicateEnd) {
      return;
    }

    final data = <String, dynamic>{
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      if (_currentUserId != null) 'lastUpdatedBy': _currentUserId,
      ...?extra,
    };

    if (status == 'ended' && !_callSessionMarkedEnded) {
      _callSessionMarkedEnded = true;
      data['endedAt'] = FieldValue.serverTimestamp();
      if (_currentUserId != null) {
        data['endedBy'] = _currentUserId;
      }
    }

    await docRef.set(data, SetOptions(merge: true));
  }

  Future<void> _beginTalkPhase() async {
    final engine = _engine;
    if (engine == null || _talkPhaseActive) return;

    _stopRingback();
    await AgoraCallAudio.startTalkPhase(
      engine,
      isVideo: widget.isVideo,
      videoMuted: _videoMuted,
    );
    if (!mounted) return;
    setState(() {
      _talkPhaseActive = true;
      _micMuted = false;
      _speakerOn = widget.isVideo;
    });
  }

  Future<void> _acceptIncomingCall() async {
    if (_acceptingIncoming) return;
    setState(() {
      _acceptingIncoming = true;
      _incomingAccepted = true;
    });

    _stopRingback();
    unawaited(_updateCallSessionStatus('accepted', extra: {
      'acceptedAt': FieldValue.serverTimestamp(),
      if (_currentUserId != null) 'acceptedBy': _currentUserId,
    }));

    if (!await _ensurePermissions()) {
      if (!mounted) return;
      await _endCall(declined: true);
      return;
    }

    await _initAgora();
    if (!mounted) return;
    setState(() {
      _acceptingIncoming = false;
    });
  }

  Future<void> _endCall({bool declined = false, bool remoteEnded = false}) async {
    if (_resultSent) return;

    final duration = _callDuration;
    final answered = _remoteConnected && _remoteUid != null;

    if (!remoteEnded) {
      final reason = declined ? 'declined' : (answered ? 'completed' : (widget.isIncoming ? 'missed' : 'cancelled'));
      await _updateCallSessionStatus('ended', extra: {
        'endedReason': reason,
        'answered': answered,
        'declined': declined,
      });
    }

    if (!widget.isIncoming && !answered && !remoteEnded) {
      unawaited(_notifyCallCancelled());
    }

    final result = <String, dynamic>{
      'answered': answered,
      if (duration != null && answered) 'durationMillis': duration.inMilliseconds,
      'isVideo': widget.isVideo,
      if (declined) 'declined': true,
    };

    _resultSent = true;
    _stopDurationTicker();

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _notifyCallCancelled() async {
    if (_cancelSignalSent || _activeChannelId.isEmpty || widget.targetProfile.uid.isEmpty) {
      return;
    }
    _cancelSignalSent = true;
    await NotificationService().cancelCallInvite(
      channelId: _activeChannelId,
      calleeId: widget.targetProfile.uid,
    );
  }

  void _startDurationTicker() {
    if (_durationTimer != null || _callStart == null) return;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _stopDurationTicker() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  Duration? get _callDuration {
    final start = _callStart;
    if (start == null) return null;
    return DateTime.now().difference(start);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  String _statusText({required bool isVideo}) {
    final override = _connectStatusOverride;
    if (override != null && override.isNotEmpty) return override;
    if (!_joined) return 'กำลังเชื่อมต่อ...';
    if (!_remoteConnected) {
      return isVideo ? 'กำลังโทรหา (วิดีโอ)' : 'กำลังโทรหา';
    }
    return 'กำลังสนทนากับ';
  }

  void _armJoinChannelTimer() {
    _joinChannelTimer?.cancel();
    _joinChannelTimer = Timer(_joinChannelTimeout, () {
      if (!mounted || _joined) return;
      debugPrint('[call] joinChannel timeout after ${_joinChannelTimeout.inSeconds}s');
      setState(() {
        _fatalError = 'เชื่อมต่อบริการโทรไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
      });
      unawaited(_endCall());
    });
  }

  void _armRemoteConnectTimer() {
    _remoteConnectTimer?.cancel();
    _remoteConnectTimer = Timer(_remoteConnectTimeout, () {
      if (!mounted || _remoteConnected) return;
      debugPrint('[call] remote connect timeout after ${_remoteConnectTimeout.inSeconds}s');
      setState(() {
        _fatalError = widget.isIncoming
            ? 'ไม่สามารถเชื่อมต่อกับผู้โทรได้'
            : 'ปลายทางไม่ตอบรับการโทร';
      });
      unawaited(_endCall());
    });
  }

  Future<void> _toggleSpeaker() async {
    final engine = _engine;
    if (engine == null || !_joined) return;
    final next = !_speakerOn;
    await engine.setEnableSpeakerphone(next);
    if (mounted) setState(() => _speakerOn = next);
  }

  Future<void> _toggleMute() async {
    final engine = _engine;
    if (engine == null || !_joined || !_talkPhaseActive) return;
    final next = !_micMuted;
    await engine.muteLocalAudioStream(next);
    await engine.updateChannelMediaOptions(
      AgoraCallAudio.talkMediaOptions(
        isVideo: widget.isVideo,
        videoMuted: _videoMuted,
        micMuted: next,
      ),
    );
    if (mounted) setState(() => _micMuted = next);
  }

  Future<void> _toggleVideo() async {
    final engine = _engine;
    if (engine == null || !_joined || !_talkPhaseActive) return;
    final nextMuted = !_videoMuted;
    await engine.enableLocalVideo(!nextMuted);
    await engine.muteLocalVideoStream(nextMuted);
    await engine.updateChannelMediaOptions(
      AgoraCallAudio.talkMediaOptions(
        isVideo: widget.isVideo,
        videoMuted: nextMuted,
        micMuted: _micMuted,
      ),
    );
    if (mounted) setState(() => _videoMuted = nextMuted);
  }

  Widget _avatar() {
    final imageUrl = widget.targetProfile.photoUrl?.trim();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _avatarFallback(),
        ),
      );
    }
    return _avatarFallback();
  }

  Widget _avatarFallback() {
    final char = widget.targetProfile.displayName.isEmpty
        ? '?'
        : widget.targetProfile.displayName.characters.first.toUpperCase();
    return Center(
      child: Text(
        char,
        style: const TextStyle(
          fontSize: 64,
          color: Colors.white70,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_fatalError != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF1F252B),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 72),
                  const SizedBox(height: 16),
                  Text(
                    _fatalError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => _endCall(declined: true),
                    child: const Text('ปิด'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (widget.isIncoming && !_incomingAccepted) {
      return Scaffold(
        backgroundColor: widget.isVideo ? Colors.black : const Color(0xFFF5F5F7),
        body: _buildIncomingContent(),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _endCall();
      },
      child: Scaffold(
        backgroundColor: widget.isVideo ? Colors.black : const Color(0xFFF5F5F7),
        body: widget.isVideo ? _buildVideoContent() : _buildVoiceContent(),
      ),
    );
  }

  Widget _buildIncomingContent() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF374049), Color(0xFF1F252B)],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Column(
                children: [
                  const Text('มีสายเข้า', style: TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 12),
                  Text(
                    widget.targetProfile.displayName,
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Container(
              width: 160,
              height: 160,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white10),
              child: _avatar(),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CallActionButton(
                    icon: Icons.call,
                    label: 'รับสาย',
                    color: const Color(0xFF00B900),
                    onTap: _acceptIncomingCall,
                  ),
                  const SizedBox(width: 32),
                  _CallActionButton(
                    icon: Icons.call_end,
                    label: 'ไม่รับ',
                    color: Colors.redAccent,
                    onTap: () => _endCall(declined: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoContent() {
    return _buildCallUI(
      statusText: _statusText(isVideo: true),
      durationText: _remoteConnected && _callDuration != null ? _formatDuration(_callDuration!) : null,
      centerContent: const SizedBox.shrink(),
      bottomControls: _buildVideoCallButtons(),
      stackBackground: Positioned.fill(child: _remoteVideoView()),
      stackTopRight: Positioned(
        top: 40,
        right: 20,
        child: SafeArea(
          child: SizedBox(
            width: 100,
            height: 150,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _localVideoView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceContent() {
    return _buildCallUI(
      statusText: _statusText(isVideo: false),
      durationText: _remoteConnected && _callDuration != null ? _formatDuration(_callDuration!) : null,
      centerContent: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 160,
            height: 160,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white10),
            child: _avatar(),
          ),
          const SizedBox(height: 24),
          if (_remoteUid == null) const CircularProgressIndicator(color: Colors.white),
        ],
      ),
      bottomControls: _buildVoiceCallButtons(),
    );
  }

  Widget _buildCallUI({
    required String statusText,
    required String? durationText,
    required Widget centerContent,
    required Widget bottomControls,
    Widget? stackBackground,
    Widget? stackTopRight,
  }) {
    final content = Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF374049), Color(0xFF1F252B)],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Column(
                children: [
                  Text(statusText, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                  if (durationText != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(48),
                      ),
                      child: Text(
                        durationText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    widget.targetProfile.displayName,
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            centerContent,
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: bottomControls,
            ),
          ],
        ),
      ),
    );

    if (stackBackground == null) {
      return content;
    }

    return Stack(
      children: [
        stackBackground,
        if (stackTopRight != null) stackTopRight,
        content,
      ],
    );
  }

  Widget _localVideoView() {
    final engine = _engine;
    if (_joined && !_videoMuted && engine != null) {
      return AgoraVideoView(
        controller: VideoViewController(
          rtcEngine: engine,
          canvas: const VideoCanvas(uid: 0),
        ),
      );
    }
    return Container(
      color: Colors.grey[800],
      child: const Center(
        child: Text('คุณปิดกล้อง', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _remoteVideoView() {
    final engine = _engine;
    if (_remoteUid != null && engine != null) {
      return AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: engine,
          canvas: VideoCanvas(uid: _remoteUid!),
          connection: RtcConnection(channelId: _activeChannelId),
        ),
      );
    }
    return Container(
      color: Colors.grey[900],
      child: const Center(
        child: Text('กำลังรอคู่สนทนา...', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildVideoCallButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CallActionButton(
          icon: _videoMuted ? Icons.videocam_off : Icons.videocam,
          label: _videoMuted ? 'เปิดกล้อง' : 'ปิดกล้อง',
          color: Colors.white24,
          onTap: () => unawaited(_toggleVideo()),
        ),
        const SizedBox(width: 16),
        _CallActionButton(
          icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
          label: 'ลำโพง',
          color: Colors.white24,
          onTap: () => unawaited(_toggleSpeaker()),
        ),
        const SizedBox(width: 16),
        _CallActionButton(
          icon: Icons.call_end,
          label: 'วางสาย',
          color: Colors.redAccent,
          onTap: _endCall,
        ),
        const SizedBox(width: 16),
        _CallActionButton(
          icon: _micMuted ? Icons.mic_off : Icons.mic,
          label: _micMuted ? 'เปิดไมค์' : 'ปิดไมค์',
          color: Colors.white24,
          onTap: () => unawaited(_toggleMute()),
        ),
      ],
    );
  }

  Widget _buildVoiceCallButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CallActionButton(
          icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
          label: 'ลำโพง',
          color: Colors.white24,
          onTap: () => unawaited(_toggleSpeaker()),
        ),
        const SizedBox(width: 24),
        _CallActionButton(
          icon: Icons.call_end,
          label: 'วางสาย',
          color: Colors.redAccent,
          onTap: _endCall,
        ),
        const SizedBox(width: 24),
        _CallActionButton(
          icon: _micMuted ? Icons.mic_off : Icons.mic,
          label: _micMuted ? 'เปิดไมค์' : 'ปิดไมค์',
          color: Colors.white24,
          onTap: () => unawaited(_toggleMute()),
        ),
      ],
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}

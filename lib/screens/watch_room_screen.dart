import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models/room.dart';
import '../services/server.dart';
import '../theme.dart';
import '../utils.dart';

class _YtPos {
  final double t;
  final double d;
  const _YtPos(this.t, this.d);
}

class _Float {
  final int id;
  final String emoji;
  final double dx;
  const _Float(this.id, this.emoji, this.dx);
}

class WatchRoomScreen extends StatefulWidget {
  final JoinResult join;
  const WatchRoomScreen({super.key, required this.join});

  @override
  State<WatchRoomScreen> createState() => _WatchRoomScreenState();
}

class _WatchRoomScreenState extends State<WatchRoomScreen> with WidgetsBindingObserver {
  // ── room state
  late Room room;
  late String myName;
  late String myColor;
  late String password;
  late bool amHost;
  late bool hostOnly;
  late int viewerCount;
  bool _offline = false;
  bool _wasDisconnected = false;
  bool _left = false;

  // ── chat state
  final List<ChatMsg> msgs = [];
  final Set<String> typing = {};
  final ScrollController _scroll = ScrollController();
  final TextEditingController _chatCtl = TextEditingController();
  final TextEditingController _urlCtl = TextEditingController();
  final FocusNode _chatFocus = FocusNode();
  Timer? _typingTimer;
  bool _isTyping = false;

  // ── media state
  VideoPlayerController? _vc;
  YoutubePlayerController? _yc;
  StreamSubscription<YoutubePlayerValue>? _ytSub;
  Timer? _ytTimer;
  final ValueNotifier<_YtPos> _ytPos = ValueNotifier(const _YtPos(0, 0));
  bool _isYt = false;
  bool _ytPlaying = false;
  bool _loading = false;
  String? _error;
  String? _currentUrl;
  int _token = 0;
  double? _drag;
  double? _pendingTime;
  bool? _pendingPlay;

  // ── effects
  final List<_Float> _floats = [];
  int _floatId = 0;
  bool _fsApplied = false;

  // ── socket plumbing
  late final io.Socket? _s;
  final Map<String, void Function(dynamic)> _handlers = {};

  bool get _locked => hostOnly && !amHost;
  bool get _hasMedia => _isYt ? _yc != null : _vc != null;
  bool get _isPlaying => _isYt ? _ytPlaying : (_vc?.value.isPlaying ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final j = widget.join;
    room = j.room;
    myName = j.name;
    myColor = j.color;
    password = j.password;
    amHost = j.isHost;
    hostOnly = j.room.hostOnly;
    viewerCount = j.room.viewerCount;
    _s = Server.I.socket;

    msgs.add(ChatMsg(
      system: true,
      text: 'Welcome to "${room.name}"! ${amHost ? 'You are the host 👑' : 'Joined as $myName'}',
    ));
    _chatFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _registerHandlers();

    final vs = j.videoState;
    if (vs != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyVideoState(vs);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _offAll();
    if (!_left) {
      _left = true;
      Server.I.leaveRoom();
    }
    _typingTimer?.cancel();
    _ytTimer?.cancel();
    _ytSub?.cancel();
    _vc?.dispose();
    _yc?.close();
    _ytPos.dispose();
    _chatCtl.dispose();
    _urlCtl.dispose();
    _scroll.dispose();
    _chatFocus.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_left) {
      final s = _s;
      if (s != null && !s.connected) s.connect();
    }
  }

  // ═════════════════════ socket handlers ═════════════════════

  void _on(String ev, void Function(Map m) h) {
    void wrapper(dynamic d) {
      if (!mounted || _left) return;
      h(d is Map ? d : const {});
    }

    _handlers[ev] = wrapper;
    _s?.on(ev, wrapper);
  }

  void _offAll() {
    _handlers.forEach((ev, h) => _s?.off(ev, h));
    _handlers.clear();
  }

  void _registerHandlers() {
    _on('chat_message', (m) => _addMsg(ChatMsg(sender: '${m['name']}', color: m['color'], text: '${m['text']}')));
    _on('emoji_reaction', (m) {
      _addMsg(ChatMsg(sender: '${m['name']}', color: m['color'], text: '${m['emoji']}'));
      _spawnFloat('${m['emoji']}');
    });
    _on('user_joined', (m) {
      setState(() => viewerCount = (m['viewerCount'] as num?)?.toInt() ?? viewerCount);
      _addSys('${m['name']} joined 👋');
    });
    _on('user_left', (m) {
      setState(() => viewerCount = (m['viewerCount'] as num?)?.toInt() ?? viewerCount);
      _addSys('${m['name']} left');
    });
    _on('host_changed', (m) {
      setState(() => amHost = ('${m['hostName']}' == myName));
    });
    _on('host_only_changed', (m) {
      setState(() => hostOnly = m['hostOnly'] == true);
    });
    _on('system_message', (m) => _addSys('${m['text']}'));
    _on('typing_start', (m) => setState(() => typing.add('${m['name']}')));
    _on('typing_stop', (m) => setState(() => typing.remove('${m['name']}')));

    _on('video_load', (m) {
      final url = '${m['url'] ?? ''}';
      if (url.isEmpty) return;
      _urlCtl.text = url.startsWith('yt:') ? url.substring(3) : url;
      _loadMedia(url);
    });
    _on('video_play', (m) => _remote(toDouble(m['time']), play: true));
    _on('video_pause', (m) => _remote(toDouble(m['time']), play: false));
    _on('video_seek', (m) => _remote(toDouble(m['time'])));

    _on('disconnect', (_) {
      _wasDisconnected = true;
      setState(() => _offline = true);
    });
    _on('connect', (_) {
      if (_wasDisconnected) _rejoin();
    });
  }

  Future<void> _rejoin() async {
    try {
      final res = await Server.I.ask('join_room', {
        'roomId': room.id,
        'name': myName,
        'password': password,
      });
      if (!mounted || _left) return;
      if (res is Map && res['success'] == true) {
        _wasDisconnected = false;
        setState(() {
          _offline = false;
          final r = res['room'];
          if (r is Map) {
            hostOnly = r['hostOnly'] == true;
            if (r['hostName'] != null) amHost = '${r['hostName']}' == myName;
            viewerCount = (r['viewerCount'] as num?)?.toInt() ?? viewerCount;
          }
        });
        _addSys('🔄 Reconnected and re-synced');
        final vs = VideoState.fromJson(res['videoState']);
        if (vs != null) _applyVideoState(vs);
      } else {
        _roomEnded();
      }
    } catch (_) {
      // connection dropped again; the next 'connect' will retry
    }
  }

  Future<void> _roomEnded() async {
    if (!mounted || _left) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Room ended'),
        content: const Text('This room is no longer available.'),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
      ),
    );
    _leave();
  }

  // ═════════════════════ chat ═════════════════════

  void _addMsg(ChatMsg m) {
    setState(() {
      msgs.add(m);
      if (msgs.length > 300) msgs.removeRange(0, msgs.length - 300);
    });
    _scrollEnd();
  }

  void _addSys(String text) => _addMsg(ChatMsg(system: true, text: text));

  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendChat() {
    final text = _chatCtl.text.trim();
    if (text.isEmpty) return;
    Server.I.emit('chat_message', {'text': text});
    _chatCtl.clear();
    _stopTyping();
  }

  void _onChatChanged(String _) {
    if (!_isTyping) {
      _isTyping = true;
      Server.I.emit('typing_start');
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), _stopTyping);
  }

  void _stopTyping() {
    _typingTimer?.cancel();
    if (_isTyping) {
      _isTyping = false;
      Server.I.emit('typing_stop');
    }
  }

  void _spawnFloat(String emoji) {
    final f = _Float(++_floatId, emoji, Random().nextDouble() * 60);
    setState(() => _floats.add(f));
    Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _floats.removeWhere((x) => x.id == f.id));
    });
  }

  // ═════════════════════ media ═════════════════════

  Future<void> _detachMedia() async {
    _ytTimer?.cancel();
    _ytTimer = null;
    _ytSub?.cancel();
    _ytSub = null;
    final vc = _vc;
    final yc = _yc;
    if (mounted) {
      setState(() {
        _vc = null;
        _yc = null;
        _isYt = false;
        _ytPlaying = false;
      });
    }
    if (vc != null || yc != null) {
      await WidgetsBinding.instance.endOfFrame;
      await vc?.dispose();
      await yc?.close();
    }
    _ytPos.value = const _YtPos(0, 0);
  }

  Future<void> _loadMedia(String url, {double start = 0, bool play = false}) async {
    final token = ++_token;
    _currentUrl = url;
    _pendingTime = null;
    _pendingPlay = null;
    _drag = null;
    if (mounted) {
      setState(() {
        _error = null;
        _loading = true;
      });
    }
    await _detachMedia();
    if (!mounted || token != _token) return;

    if (url.startsWith('yt:')) {
      _openYoutube(url.substring(3), start, play);
      setState(() => _loading = false);
      await _applyPending();
      return;
    }

    VideoPlayerController? c;
    try {
      c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
    } catch (_) {
      await c?.dispose();
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this video. Use a direct MP4/WebM link (not a web page) or a YouTube link.';
      });
      return;
    }
    if (!mounted || token != _token) {
      await c?.dispose();
      return;
    }
    final ctl = c!;
    ctl.addListener(() {
      if (ctl.value.hasError && mounted && identical(_vc, ctl) && _error == null) {
        setState(() => _error = 'Playback error: ${ctl.value.errorDescription ?? 'unknown'}');
      }
    });
    if (start > 0) await ctl.seekTo(secs(start));
    if (play) await ctl.play();
    if (!mounted || token != _token) {
      await ctl.dispose();
      return;
    }
    setState(() {
      _vc = ctl;
      _loading = false;
    });
    await _applyPending();
  }

  void _openYoutube(String id, double start, bool play) {
    final yc = YoutubePlayerController.fromVideoId(
      videoId: id,
      autoPlay: play,
      startSeconds: start > 0 ? start : null,
      params: const YoutubePlayerParams(
        showControls: false,
        showFullscreenButton: false,
      ),
    );
    _ytSub = yc.listen((v) {
      final playing = v.playerState == PlayerState.playing;
      if (mounted && playing != _ytPlaying) setState(() => _ytPlaying = playing);
    });
    _ytTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!identical(_yc, yc)) return;
      try {
        final t = await yc.currentTime;
        final d = await yc.duration;
        if (identical(_yc, yc)) _ytPos.value = _YtPos(t, d);
      } catch (_) {}
    });
    setState(() {
      _yc = yc;
      _isYt = true;
      _ytPlaying = play;
    });
  }

  Future<void> _applyPending() async {
    final t = _pendingTime;
    final p = _pendingPlay;
    _pendingTime = null;
    _pendingPlay = null;
    if (t != null) await _seek(t);
    if (p == true) {
      await _play();
    } else if (p == false) {
      await _pause();
    }
  }

  Future<void> _applyVideoState(VideoState vs) async {
    _urlCtl.text = vs.url.startsWith('yt:') ? vs.url.substring(3) : vs.url;
    if (_currentUrl == vs.url && _hasMedia) {
      await _seek(vs.time);
      if (vs.isPlaying) {
        await _play();
      } else {
        await _pause();
      }
    } else {
      await _loadMedia(vs.url, start: vs.time, play: vs.isPlaying);
    }
    _addSys("Syncing to room's current position (${fmt(vs.time)})…");
  }

  // primitives: act on the local player only, never emit
  Future<void> _play() async {
    if (_isYt) {
      _yc?.playVideo();
      if (mounted) setState(() => _ytPlaying = true);
    } else {
      await _vc?.play();
    }
  }

  Future<void> _pause() async {
    if (_isYt) {
      _yc?.pauseVideo();
      if (mounted) setState(() => _ytPlaying = false);
    } else {
      await _vc?.pause();
    }
  }

  Future<void> _seek(double t) async {
    var target = max(0.0, t);
    if (_isYt) {
      await _yc?.seekTo(seconds: target, allowSeekAhead: true);
    } else {
      final vc = _vc;
      if (vc == null) return;
      final dur = vc.value.duration.inMilliseconds / 1000;
      if (dur > 0 && target > dur) target = dur;
      await vc.seekTo(secs(target));
    }
  }

  Future<double> _currentPos() async {
    if (_isYt) {
      try {
        return await _yc!.currentTime;
      } catch (_) {
        return _ytPos.value.t;
      }
    }
    return (_vc?.value.position.inMilliseconds ?? 0) / 1000;
  }

  // remote events
  Future<void> _remote(double t, {bool? play}) async {
    if (_currentUrl == null) return;
    if (_loading || !_hasMedia) {
      _pendingTime = t;
      if (play != null) _pendingPlay = play;
      return;
    }
    await _seek(t);
    if (play == true) {
      await _play();
    } else if (play == false) {
      await _pause();
    }
  }

  // local (user) actions: act, then broadcast
  Future<void> _userTogglePlay() async {
    if (_locked || !_hasMedia) return;
    if (_isPlaying) {
      await _pause();
      Server.I.emit('video_pause', {'time': await _currentPos()});
    } else {
      await _play();
      Server.I.emit('video_play', {'time': await _currentPos()});
    }
  }

  Future<void> _userSkip(int seconds) async {
    if (_locked || !_hasMedia) return;
    final t = max(0.0, (await _currentPos()) + seconds);
    await _seek(t);
    Server.I.emit('video_seek', {'time': t});
  }

  void _loadFromInput() {
    if (_locked) return;
    final raw = _urlCtl.text.trim();
    if (raw.isEmpty) return;
    FocusScope.of(context).unfocus();
    final yt = extractYtId(raw);
    final String url;
    if (yt != null) {
      url = 'yt:$yt';
    } else if (raw.startsWith('http://') || raw.startsWith('https://')) {
      url = raw;
    } else {
      setState(() => _error = 'Enter a full link starting with http:// or https://, or a YouTube link.');
      return;
    }
    _loadMedia(url);
    Server.I.emit('video_load', {'url': url});
  }

  // ═════════════════════ misc actions ═════════════════════

  void _copyLink() {
    final link = '${Server.I.url}/?room=${room.id}';
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Room link copied — send it to your friends')));
  }

  void _toggleFullscreen(bool landscape) {
    if (landscape) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } else {
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    }
  }

  void _syncSystemUi(bool landscape) {
    if (landscape == _fsApplied) return;
    _fsApplied = landscape;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(
          landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    });
  }

  Future<void> _confirmLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave room?'),
        content: Text(amHost
            ? 'You are the host. Hosting passes to someone else if others are watching.'
            : 'You can rejoin any time with the room link.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Stay')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave', style: TextStyle(color: C.red)),
          ),
        ],
      ),
    );
    if (ok == true) _leave();
  }

  void _leave() {
    if (_left) return;
    _left = true;
    _offAll();
    _stopTyping();
    Server.I.leaveRoom();
    if (mounted) Navigator.of(context).pop();
  }

  // ═════════════════════ UI ═════════════════════

  @override
  Widget build(BuildContext context) {
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    _syncSystemUi(landscape);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (landscape) {
          _toggleFullscreen(true);
        } else {
          _confirmLeave();
        }
      },
      child: Scaffold(
        backgroundColor: landscape ? Colors.black : C.bg,
        appBar: landscape ? null : _appBar(),
        body: landscape ? _fullBody() : SafeArea(top: false, child: _portraitBody()),
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      titleSpacing: 0,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(room.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        Row(children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _offline ? C.red : C.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text('$viewerCount watching',
              style: const TextStyle(fontSize: 11, color: C.dim, fontWeight: FontWeight.w400)),
        ]),
      ]),
      actions: [
        IconButton(tooltip: 'Copy room link', icon: const Icon(Icons.link), onPressed: _copyLink),
        IconButton(tooltip: 'Leave', icon: const Icon(Icons.logout), onPressed: _confirmLeave),
      ],
    );
  }

  Widget _portraitBody() {
    final kbChat = MediaQuery.viewInsetsOf(context).bottom > 0 && _chatFocus.hasFocus;
    return Column(children: [
      if (_offline)
        Container(
          width: double.infinity,
          color: const Color(0xFF3A2000),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: const Text('⚠️ Connection lost — reconnecting…',
              textAlign: TextAlign.center, style: TextStyle(color: C.amber, fontSize: 12)),
        ),
      AspectRatio(aspectRatio: 16 / 9, child: _videoArea()),
      if (!kbChat) _controls(false),
      if (!kbChat) _urlRow(),
      if (amHost && !kbChat) _hostBar(),
      Expanded(child: _chatPanel()),
    ]);
  }

  Widget _fullBody() {
    return Stack(children: [
      Positioned.fill(child: _videoArea()),
      Positioned(left: 0, right: 0, bottom: 0, child: _controls(true)),
      Positioned(
        top: 4,
        left: 4,
        child: SafeArea(
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => _toggleFullscreen(true),
          ),
        ),
      ),
    ]);
  }

  Widget _fit(double ratio, Widget child) {
    return LayoutBuilder(builder: (context, c) {
      var w = c.maxWidth;
      var h = w / ratio;
      if (h > c.maxHeight) {
        h = c.maxHeight;
        w = h * ratio;
      }
      return Center(child: SizedBox(width: w, height: h, child: child));
    });
  }

  Widget _videoArea() {
    Widget content;
    if (_error != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('⚠️', style: TextStyle(fontSize: 34)),
            const SizedBox(height: 8),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: C.red, fontSize: 13, height: 1.4)),
            TextButton(
              onPressed: () => setState(() => _error = null),
              child: const Text('Dismiss'),
            ),
          ]),
        ),
      );
    } else if (_loading) {
      content = const Center(child: CircularProgressIndicator(color: C.amber));
    } else if (_isYt && _yc != null) {
      content = _fit(
        16 / 9,
        IgnorePointer(child: YoutubePlayer(controller: _yc!, aspectRatio: 16 / 9)),
      );
    } else if (_vc != null) {
      final ar = _vc!.value.aspectRatio;
      content = _fit(ar > 0 ? ar : 16 / 9, VideoPlayer(_vc!));
    } else {
      content = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Opacity(opacity: .25, child: Text('🎬', style: TextStyle(fontSize: 48))),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _locked
                  ? 'Waiting for the host to pick a video'
                  : 'Paste a video link below to start watching',
              textAlign: TextAlign.center,
              style: const TextStyle(color: C.dim, fontSize: 13),
            ),
          ),
        ]),
      );
    }

    return ClipRect(
      child: Stack(children: [
        Positioned.fill(child: ColoredBox(color: Colors.black, child: content)),
        if (_locked)
          Positioned(
            top: 8,
            left: 8,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x99000000),
                  border: Border.all(color: C.border),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Text('🔒 Host controls playback',
                    style: TextStyle(color: C.dim, fontSize: 11)),
              ),
            ),
          ),
        for (final f in _floats)
          Positioned(
            right: 16 + f.dx,
            bottom: 16,
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                key: ValueKey(f.id),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 2500),
                builder: (context, t, child) => Opacity(
                  opacity: t < 0.8 ? 1.0 : ((1 - t) / 0.2).clamp(0.0, 1.0).toDouble(),
                  child: Transform.translate(
                    offset: Offset(0, -140 * t),
                    child: Transform.scale(scale: 1 - 0.5 * t, child: child),
                  ),
                ),
                child: Text(f.emoji, style: const TextStyle(fontSize: 30)),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _controls(bool landscape) {
    Widget bar(double pos, double dur, bool playing, bool buffering) {
      final can = _hasMedia && !_locked;
      final seekable = can && dur > 0;
      final maxV = dur > 0 ? dur : 1.0;
      final value = (_drag ?? pos).clamp(0.0, maxV).toDouble();
      const disabled = Color(0x40FFFFFF);
      return Container(
        decoration: landscape
            ? const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xDD000000)],
                ),
              )
            : const BoxDecoration(color: Colors.black),
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: C.amber,
              inactiveTrackColor: const Color(0xFF333333),
              thumbColor: C.amber,
              disabledThumbColor: const Color(0xFF555555),
              disabledActiveTrackColor: const Color(0xFF555555),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value,
              min: 0,
              max: maxV,
              onChanged: seekable ? (v) => setState(() => _drag = v) : null,
              onChangeEnd: seekable
                  ? (v) async {
                      setState(() => _drag = null);
                      await _seek(v);
                      Server.I.emit('video_seek', {'time': v});
                    }
                  : null,
            ),
          ),
          Row(children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              color: C.text,
              disabledColor: disabled,
              onPressed: can ? _userTogglePlay : null,
              icon: buffering
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: C.amber),
                    )
                  : Icon(playing ? Icons.pause : Icons.play_arrow),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              color: C.text,
              disabledColor: disabled,
              onPressed: can ? () => _userSkip(-10) : null,
              icon: const Icon(Icons.replay_10),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              color: C.text,
              disabledColor: disabled,
              onPressed: can ? () => _userSkip(10) : null,
              icon: const Icon(Icons.forward_10),
            ),
            const SizedBox(width: 6),
            Text('${fmt(pos)} / ${fmt(dur)}',
                style: const TextStyle(fontSize: 12, color: C.dim)),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              color: C.text,
              onPressed: () => _toggleFullscreen(landscape),
              icon: Icon(landscape ? Icons.fullscreen_exit : Icons.fullscreen),
            ),
          ]),
        ]),
      );
    }

    if (_isYt) {
      return ValueListenableBuilder<_YtPos>(
        valueListenable: _ytPos,
        builder: (context, p, _) => bar(p.t, p.d, _ytPlaying, false),
      );
    }
    final vc = _vc;
    if (vc == null) return bar(0, 0, false, false);
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: vc,
      builder: (context, v, _) => bar(
        v.position.inMilliseconds / 1000,
        v.duration.inMilliseconds / 1000,
        v.isPlaying,
        v.isBuffering,
      ),
    );
  }

  Widget _urlRow() {
    return Container(
      color: C.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _urlCtl,
            enabled: !_locked,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(hintText: 'MP4/WebM or YouTube link…'),
            onSubmitted: (_) => _loadFromInput(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
          onPressed: _locked ? null : _loadFromInput,
          child: const Text('Load'),
        ),
      ]),
    );
  }

  Widget _hostBar() {
    return Container(
      color: const Color(0xFF1A1400),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Row(children: [
        const Expanded(
          child: Text('👑 You are the host', style: TextStyle(color: C.amber, fontSize: 13)),
        ),
        TextButton(
          onPressed: () => Server.I.emit('set_host_only', {'hostOnly': !hostOnly}),
          child: Text(
            hostOnly ? '🔓 Allow everyone' : '🔒 Host-only controls',
            style: const TextStyle(color: C.amber, fontSize: 12),
          ),
        ),
      ]),
    );
  }

  Widget _chatPanel() {
    String typingText = '';
    if (typing.isNotEmpty) {
      final names = typing.toList();
      typingText = names.length == 1
          ? '${names.first} is typing…'
          : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last} are typing…';
    }
    return Container(
      color: C.chatBg,
      child: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            itemCount: msgs.length,
            itemBuilder: (context, i) {
              final m = msgs[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: m.system
                    ? Text(m.text,
                        style: const TextStyle(
                            color: C.dim, fontStyle: FontStyle.italic, fontSize: 12))
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.sender ?? '',
                            style: TextStyle(
                                color: parseColor(m.color),
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        Text(m.text, style: const TextStyle(fontSize: 14, height: 1.4)),
                      ]),
              );
            },
          ),
        ),
        SizedBox(
          height: 20,
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(typingText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: C.dim, fontSize: 11, fontStyle: FontStyle.italic)),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: C.border), bottom: BorderSide(color: C.border)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final e in const ['😂', '😮', '❤️', '🔥', '👏', '😭'])
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Server.I.emit('emoji_reaction', {'emoji': e}),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(e, style: const TextStyle(fontSize: 22)),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _chatCtl,
                focusNode: _chatFocus,
                maxLength: 300,
                textInputAction: TextInputAction.send,
                decoration: const InputDecoration(hintText: 'Say something…', counterText: ''),
                onChanged: _onChatChanged,
                onSubmitted: (_) {
                  _sendChat();
                  _chatFocus.requestFocus();
                },
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  minimumSize: const Size(48, 44)),
              onPressed: _sendChat,
              child: const Icon(Icons.send, size: 18),
            ),
          ]),
        ),
      ]),
    );
  }
}

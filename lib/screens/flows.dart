import 'package:flutter/material.dart';
import '../models/room.dart';
import '../services/server.dart';
import '../theme.dart';
import '../utils.dart';
import 'settings_screen.dart';
import 'watch_room_screen.dart';

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Makes sure a server is set and the socket is connected.
/// Shows a "waking up" dialog while connecting (free hosts sleep when idle).
Future<bool> ensureConnected(BuildContext context) async {
  if (!Server.I.hasUrl) {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    if (!Server.I.hasUrl || !context.mounted) return false;
  }
  if (Server.I.connected) return true;
  if (!context.mounted) return false;
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _WakingDialog(),
  );
  final ok = await Server.I.waitConnected();
  nav.pop();
  if (!ok && context.mounted) {
    toast(context, 'Could not reach the server. Check the address in settings.');
  }
  return ok;
}

class _WakingDialog extends StatelessWidget {
  const _WakingDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: const AlertDialog(
        content: Row(children: [
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 3, color: C.amber),
          ),
          SizedBox(width: 18),
          Expanded(
            child: Text(
              'Connecting to server…\nFree servers sleep when idle, this can take up to a minute.',
              style: TextStyle(height: 1.4),
            ),
          ),
        ]),
      ),
    );
  }
}

void openRoom(BuildContext context, JoinResult r) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => WatchRoomScreen(join: r)),
  );
}

const _sheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
);

Future<void> startHosting(BuildContext context) async {
  if (!await ensureConnected(context)) return;
  if (!context.mounted) return;
  final r = await showModalBottomSheet<JoinResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: _sheetShape,
    builder: (_) => const _HostSheet(),
  );
  if (r != null && context.mounted) openRoom(context, r);
}

Future<void> startJoining(BuildContext context, Room room) async {
  if (!await ensureConnected(context)) return;
  if (!context.mounted) return;
  final r = await showModalBottomSheet<JoinResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: _sheetShape,
    builder: (_) => _JoinSheet(room: room),
  );
  if (r != null && context.mounted) openRoom(context, r);
}

Future<void> joinFromLink(BuildContext context, String raw) async {
  final id = roomIdFromLink(raw);
  if (id == null) {
    toast(context, "That doesn't look like a room link.");
    return;
  }
  if (!await ensureConnected(context)) return;
  if (!context.mounted) return;
  try {
    final res = await Server.I.ask('get_room_by_id', id);
    if (!context.mounted) return;
    if (res is! Map) {
      toast(context, 'Room not found or has ended.');
      return;
    }
    await startJoining(context, Room.fromJson(res));
  } catch (e) {
    if (context.mounted) toast(context, Server.friendlyError(e));
  }
}

// ───────────────────────── Sheets ─────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 14),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 11, color: C.dim, letterSpacing: 1)),
      );
}

ButtonStyle _segStyle() => SegmentedButton.styleFrom(
      backgroundColor: C.surface2,
      foregroundColor: C.dim,
      selectedBackgroundColor: C.amber,
      selectedForegroundColor: Colors.black,
      side: const BorderSide(color: C.border),
    );

class _HostSheet extends StatefulWidget {
  const _HostSheet();
  @override
  State<_HostSheet> createState() => _HostSheetState();
}

class _HostSheetState extends State<_HostSheet> {
  final _name = TextEditingController(text: Server.I.displayName);
  final _room = TextEditingController();
  final _pass = TextEditingController();
  String _privacy = 'public';
  bool _hostOnly = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _room.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final roomName = _room.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Please enter your name.');
    if (roomName.isEmpty) return setState(() => _error = 'Please enter a room name.');
    final pass = _privacy == 'private' ? _pass.text.trim() : '';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await Server.I.ask('create_room', {
        'name': name,
        'roomName': roomName,
        'privacy': _privacy,
        'password': pass,
        'hostOnly': _hostOnly,
      });
      if (!mounted) return;
      if (res is Map && res['success'] == true && res['room'] is Map) {
        await Server.I.setDisplayName(name);
        if (!mounted) return;
        Navigator.of(context).pop(JoinResult(
          room: Room.fromJson(res['room'] as Map),
          color: '${res['color'] ?? ''}',
          name: name,
          password: pass,
          isHost: true,
        ));
      } else {
        setState(() {
          _busy = false;
          _error = res is Map && res['error'] != null
              ? '${res['error']}'
              : 'Could not create the room.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = Server.friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🎬 Host a Room', style: serif(22)),
            const _Label('Your name'),
            TextField(
              controller: _name,
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'e.g. Alex', counterText: ''),
            ),
            const _Label('Room name'),
            TextField(
              controller: _room,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
              decoration:
                  const InputDecoration(hintText: 'e.g. Friday Night Flicks', counterText: ''),
            ),
            const _Label('Privacy'),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                style: _segStyle(),
                segments: const [
                  ButtonSegment(value: 'public', label: Text('🌍 Public')),
                  ButtonSegment(value: 'private', label: Text('🔒 Private')),
                ],
                selected: {_privacy},
                onSelectionChanged: (s) => setState(() => _privacy = s.first),
              ),
            ),
            if (_privacy == 'private') ...[
              const _Label('Password'),
              TextField(
                controller: _pass,
                maxLength: 30,
                decoration: const InputDecoration(
                    hintText: 'Leave blank for none', counterText: ''),
              ),
            ],
            const _Label('Controls'),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: _segStyle(),
                segments: const [
                  ButtonSegment(value: false, label: Text('👥 Everyone')),
                  ButtonSegment(value: true, label: Text('👑 Host only')),
                ],
                selected: {_hostOnly},
                onSelectionChanged: (s) => setState(() => _hostOnly = s.first),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: C.red, fontSize: 13)),
              ),
            const SizedBox(height: 20),
            Row(children: [
              OutlinedButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Text('Create Room →'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _JoinSheet extends StatefulWidget {
  final Room room;
  const _JoinSheet({required this.room});
  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  final _name = TextEditingController(text: Server.I.displayName);
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Please enter your name.');
    final pass = _pass.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await Server.I.ask('join_room', {
        'roomId': widget.room.id,
        'name': name,
        'password': pass,
      });
      if (!mounted) return;
      if (res is Map && res['success'] == true && res['room'] is Map) {
        await Server.I.setDisplayName(name);
        if (!mounted) return;
        Navigator.of(context).pop(JoinResult(
          room: Room.fromJson(res['room'] as Map),
          color: '${res['color'] ?? ''}',
          name: name,
          password: pass,
          isHost: false,
          videoState: VideoState.fromJson(res['videoState']),
        ));
      } else {
        setState(() {
          _busy = false;
          _error = res is Map && res['error'] != null
              ? '${res['error']}'
              : 'Could not join the room.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = Server.friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('👋 Join ${widget.room.name}', style: serif(22)),
            const _Label('Your name'),
            TextField(
              controller: _name,
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'e.g. Jordan', counterText: ''),
            ),
            if (widget.room.hasPassword) ...[
              const _Label('Password'),
              TextField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(hintText: 'Enter password'),
                onSubmitted: (_) => _submit(),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: C.red, fontSize: 13)),
              ),
            const SizedBox(height: 20),
            Row(children: [
              OutlinedButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Text('Join Room →'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

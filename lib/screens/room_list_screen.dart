import 'package:flutter/material.dart';
import '../models/room.dart';
import '../services/server.dart';
import '../theme.dart';
import 'flows.dart';

class RoomListScreen extends StatefulWidget {
  const RoomListScreen({super.key});
  @override
  State<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends State<RoomListScreen> {
  List<Room> _rooms = [];
  bool _loading = true;
  String? _error;
  late final void Function(dynamic) _onUpdated;
  dynamic _socketRef;

  @override
  void initState() {
    super.initState();
    _onUpdated = (data) {
      if (!mounted) return;
      setState(() => _rooms = _parse(data));
    };
    _attach();
    _load();
  }

  void _attach() {
    final s = Server.I.socket;
    _socketRef = s;
    s?.on('rooms_updated', _onUpdated);
  }

  @override
  void dispose() {
    _socketRef?.off('rooms_updated', _onUpdated);
    super.dispose();
  }

  List<Room> _parse(dynamic data) {
    if (data is! List) return [];
    return data.whereType<Map>().map(Room.fromJson).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!Server.I.connected) {
        final ok = await ensureConnected(context);
        if (!ok) {
          if (mounted) setState(() => _loading = false);
          return;
        }
        // socket instance may have been replaced if settings changed
        if (!identical(_socketRef, Server.I.socket)) {
          _socketRef?.off('rooms_updated', _onUpdated);
          _attach();
        }
      }
      final res = await Server.I.ask('get_rooms');
      if (!mounted) return;
      setState(() {
        _rooms = _parse(res);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = Server.friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Public Rooms'),
        actions: [
          IconButton(
            tooltip: 'Host a room',
            icon: const Icon(Icons.add_circle_outline, color: C.amber),
            onPressed: () => startHosting(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: C.amber,
        backgroundColor: C.surface2,
        onRefresh: _load,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading && _rooms.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: C.amber));
    }
    if (_error != null && _rooms.isEmpty) {
      return _msg('⚠️', _error!);
    }
    if (_rooms.isEmpty) {
      return _msg('🎬', 'No public rooms yet. Be the first!');
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _rooms.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _RoomTile(
        room: _rooms[i],
        onTap: () async {
          await startJoining(context, _rooms[i]);
          if (mounted) _load();
        },
      ),
    );
  }

  Widget _msg(String icon, String text) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(child: Text(icon, style: const TextStyle(fontSize: 48))),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(text,
                textAlign: TextAlign.center, style: const TextStyle(color: C.dim)),
          ),
        ],
      );
}

class _RoomTile extends StatelessWidget {
  final Room room;
  final VoidCallback onTap;
  const _RoomTile({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: C.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: C.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(room.name, style: serif(17), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A3A1A),
                  border: Border.all(color: const Color(0xFF3A6A3A)),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Text('PUBLIC',
                    style: TextStyle(fontSize: 10, color: C.green, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 6),
            Text('by ${room.hostName}', style: const TextStyle(color: C.dim, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(spacing: 14, children: [
              Text('👁 ${room.viewerCount} watching',
                  style: const TextStyle(color: C.dim, fontSize: 12)),
              if (room.hasPassword)
                const Text('🔒 Password', style: TextStyle(color: C.dim, fontSize: 12)),
              if (room.hostOnly)
                const Text('👑 Host controls', style: TextStyle(color: C.dim, fontSize: 12)),
            ]),
          ]),
        ),
      ),
    );
  }
}

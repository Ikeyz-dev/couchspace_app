import '../utils.dart';

class Room {
  final String id;
  final String name;
  final String hostName;
  final int viewerCount;
  final bool hasPassword;
  final bool hostOnly;

  const Room({
    required this.id,
    required this.name,
    required this.hostName,
    required this.viewerCount,
    required this.hasPassword,
    required this.hostOnly,
  });

  factory Room.fromJson(Map m) => Room(
        id: '${m['id']}',
        name: '${m['name'] ?? 'Room'}',
        hostName: '${m['hostName'] ?? ''}',
        viewerCount: (m['viewerCount'] as num?)?.toInt() ?? 1,
        hasPassword: m['hasPassword'] == true,
        hostOnly: m['hostOnly'] == true,
      );
}

class VideoState {
  final String url;
  final double time;
  final bool isPlaying;
  const VideoState(this.url, this.time, this.isPlaying);

  static VideoState? fromJson(dynamic m) {
    if (m is! Map) return null;
    final url = m['url'];
    if (url == null || '$url'.isEmpty) return null;
    return VideoState('$url', toDouble(m['time']), m['isPlaying'] == true);
  }
}

class JoinResult {
  final Room room;
  final String color;
  final String name;
  final String password;
  final bool isHost;
  final VideoState? videoState;
  const JoinResult({
    required this.room,
    required this.color,
    required this.name,
    required this.password,
    required this.isHost,
    this.videoState,
  });
}

class ChatMsg {
  final String? sender;
  final dynamic color;
  final String text;
  final bool system;
  const ChatMsg({this.sender, this.color, required this.text, this.system = false});
}

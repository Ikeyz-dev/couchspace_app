import 'package:flutter/material.dart';
import 'theme.dart';

/// Server sends colors as CSS strings (hex, hsl() or rgb()). Parse them all.
Color parseColor(dynamic input) {
  final s = (input ?? '').toString().trim().toLowerCase();
  if (s.isEmpty) return C.amber;
  try {
    if (s.startsWith('#')) {
      var h = s.substring(1);
      if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
      if (h.length == 6) return Color(0xFF000000 | int.parse(h, radix: 16));
      if (h.length == 8) {
        final v = int.parse(h, radix: 16); // rrggbbaa
        return Color(((v & 0xFF) << 24) | (v >> 8));
      }
    }
    final hsl = RegExp(r'hsla?\(\s*([\d.]+)(?:deg)?[\s,]+([\d.]+)%[\s,]+([\d.]+)%')
        .firstMatch(s);
    if (hsl != null) {
      return HSLColor.fromAHSL(
        1,
        double.parse(hsl.group(1)!) % 360,
        (double.parse(hsl.group(2)!) / 100).clamp(0.0, 1.0),
        (double.parse(hsl.group(3)!) / 100).clamp(0.0, 1.0),
      ).toColor();
    }
    final rgb = RegExp(r'rgba?\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)').firstMatch(s);
    if (rgb != null) {
      return Color.fromARGB(255, int.parse(rgb.group(1)!),
          int.parse(rgb.group(2)!), int.parse(rgb.group(3)!));
    }
  } catch (_) {}
  return C.amber;
}

final _ytIdRe = RegExp(r'^[a-zA-Z0-9_-]{11}$');

/// Returns an 11-char YouTube id from a URL or a bare id, else null.
String? extractYtId(String input) {
  final s = input.trim();
  if (_ytIdRe.hasMatch(s)) return s;
  try {
    final u = Uri.parse(s);
    final host = u.host.toLowerCase();
    String? id;
    if (host.contains('youtu.be')) {
      if (u.pathSegments.isNotEmpty) id = u.pathSegments.first;
    } else if (host.contains('youtube.com') || host.contains('youtube-nocookie.com')) {
      id = u.queryParameters['v'];
      if (id == null && u.pathSegments.length >= 2) {
        const keys = ['embed', 'shorts', 'live', 'v'];
        if (keys.contains(u.pathSegments.first)) id = u.pathSegments[1];
      }
    }
    if (id != null && _ytIdRe.hasMatch(id)) return id;
  } catch (_) {}
  return null;
}

/// Accepts a full room link (…?room=ID) or a bare room id.
String? roomIdFromLink(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  try {
    final u = Uri.parse(s);
    final r = u.queryParameters['room'];
    if (r != null && r.isNotEmpty) return r;
  } catch (_) {}
  if (!s.contains('/') && !s.contains(' ') && !s.contains('?')) return s;
  return null;
}

String fmt(double seconds) {
  if (seconds.isNaN || seconds.isInfinite || seconds < 0) seconds = 0;
  final total = seconds.floor();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

double toDouble(dynamic v, [double fallback = 0]) =>
    v is num ? v.toDouble() : (double.tryParse('$v') ?? fallback);

Duration secs(double s) => Duration(milliseconds: (s * 1000).round());

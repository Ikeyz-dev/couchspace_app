import 'package:flutter/material.dart';
import '../services/server.dart';
import '../theme.dart';
import '../widgets/conn_chip.dart';
import 'flows.dart';
import 'room_list_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _link = TextEditingController();

  @override
  void initState() {
    super.initState();
    // First launch: ask for the server address.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !Server.I.hasUrl) _openSettings();
    });
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _openSettings() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1),
            radius: 1.1,
            colors: [Color(0xFF1A1400), C.bg],
            stops: [0, 0.7],
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: ConnChip(onTap: _openSettings),
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: RichText(
                            text: TextSpan(
                              style: serif(46),
                              children: const [
                                TextSpan(text: 'Couch'),
                                TextSpan(text: 'Space', style: TextStyle(color: C.amber)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Center(
                          child: Text('WATCH TOGETHER, MILES APART',
                              style: TextStyle(color: C.dim, fontSize: 12, letterSpacing: 2)),
                        ),
                        const SizedBox(height: 36),
                        _ActionCard(
                          icon: '🎬',
                          title: 'Host a Room',
                          body: 'Start a watch party and invite friends. Public or private.',
                          onTap: () => startHosting(context),
                        ),
                        const SizedBox(height: 14),
                        _ActionCard(
                          icon: '🌍',
                          title: 'Browse Rooms',
                          body: 'Join a public room and watch with others.',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const RoomListScreen()),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: C.surface,
                            border: Border.all(color: C.border),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('JOIN VIA LINK',
                                  style: TextStyle(fontSize: 11, color: C.dim, letterSpacing: 1)),
                              const SizedBox(height: 8),
                              Row(children: [
                                Expanded(
                                  child: TextField(
                                    controller: _link,
                                    keyboardType: TextInputType.url,
                                    autocorrect: false,
                                    decoration:
                                        const InputDecoration(hintText: 'Paste room link…'),
                                    onSubmitted: (v) => joinFromLink(context, v),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                FilledButton(
                                  onPressed: () => joinFromLink(context, _link.text),
                                  child: const Text('Join'),
                                ),
                              ]),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String icon;
  final String title;
  final String body;
  final VoidCallback onTap;
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: C.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(color: C.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Text(icon, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: serif(19)),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(color: C.dim, fontSize: 13, height: 1.4)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

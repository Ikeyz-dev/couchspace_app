import 'package:flutter/material.dart';
import '../services/server.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _ctl = TextEditingController(text: Server.I.url);
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final normalized = Server.normalize(_ctl.text);
    if (normalized.isEmpty) {
      setState(() => _error = 'Enter a valid address, e.g. https://couchspace.onrender.com');
      return;
    }
    setState(() => _error = null);
    _ctl.text = normalized;
    await Server.I.setUrl(normalized);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Server settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('SERVER ADDRESS',
              style: TextStyle(fontSize: 12, color: C.dim, letterSpacing: 1)),
          const SizedBox(height: 8),
          TextField(
            controller: _ctl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'https://your-server.onrender.com'),
            onSubmitted: (_) => _save(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: C.red, fontSize: 13)),
            ),
          const SizedBox(height: 14),
          FilledButton(onPressed: _save, child: const Text('Save & connect')),
          const SizedBox(height: 20),
          ListenableBuilder(
            listenable: Server.I,
            builder: (context, _) {
              final s = Server.I;
              String text;
              Color color;
              switch (s.state) {
                case ConnState.connected:
                  text = 'Connected ✓';
                  color = C.green;
                  break;
                case ConnState.connecting:
                  text = 'Connecting… free servers can take up to a minute to wake up.';
                  color = C.amber;
                  break;
                case ConnState.disconnected:
                  text = 'Disconnected. Retrying automatically…';
                  color = C.red;
                  break;
                case ConnState.idle:
                  text = 'No server set yet.';
                  color = C.dim;
                  break;
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(text, style: TextStyle(color: color)),
                if (s.lastError != null && s.state != ConnState.connected)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Last error: ${s.lastError}',
                        style: const TextStyle(color: C.dim, fontSize: 12)),
                  ),
              ]);
            },
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: C.surface,
              border: Border.all(color: C.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Use the address where your CouchSpace server (server.js) is running — '
              'your Render or Railway URL. A static host like Vercel or Netlify cannot '
              'run the live-sync server.\n\n'
              'Everyone in a room needs to use the same server.',
              style: TextStyle(color: C.dim, height: 1.5, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../services/server.dart';
import '../theme.dart';

class ConnChip extends StatelessWidget {
  final VoidCallback? onTap;
  const ConnChip({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Server.I,
      builder: (context, _) {
        late final Color color;
        late final String label;
        switch (Server.I.state) {
          case ConnState.connected:
            color = C.green;
            label = 'connected';
            break;
          case ConnState.connecting:
            color = C.amber;
            label = 'connecting…';
            break;
          case ConnState.disconnected:
            color = C.red;
            label = 'offline';
            break;
          case ConnState.idle:
            color = C.red;
            label = 'set server';
            break;
        }
        return InkWell(
          borderRadius: BorderRadius.circular(100),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              border: Border.all(color: C.border),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(label, style: const TextStyle(fontSize: 12, color: C.dim)),
            ]),
          ),
        );
      },
    );
  }
}

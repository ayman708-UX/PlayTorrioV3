import 'package:flutter/material.dart';

/// The PlayTorrio logo shown at the top of each hub's sidebar.
///
/// On desktop it shows the icon + "PlayTorrio" wordmark; on mobile it shows
/// just the icon to save horizontal space.
class SidebarLogo extends StatelessWidget {
  const SidebarLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    return Row(
      children: [
        Image.asset(
          'assets/icon.png',
          width: 32,
          height: 32,
          fit: BoxFit.contain,
        ),
        if (isDesktop) ...[
          const SizedBox(width: 10),
          const Text(
            'PlayTorrio',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ],
    );
  }
}
import 'package:flutter/material.dart';

/// Blocks all taps on van2 home while admin maintenance mode is enabled.
class HomeMaintenanceOverlay extends StatelessWidget {
  const HomeMaintenanceOverlay({
    super.key,
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: Material(
        color: Colors.black.withValues(alpha: 0.42),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.95),
                    width: 2,
                  ),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFFFE0B2),
                          ),
                        ),
                        child: const Icon(
                          Icons.construction_outlined,
                          color: Color(0xFFE65100),
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: const Color(0xFF7C2D12),
                              fontWeight: FontWeight.w700,
                              height: 1.45,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

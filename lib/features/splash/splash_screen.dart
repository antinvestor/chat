import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/startup/startup_service.dart';
import '../../core/theme/app_theme.dart';

/// Splash screen shown during app initialization
class SplashScreen extends ConsumerStatefulWidget {
  final Widget child;

  const SplashScreen({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _showChild = false;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    // Start initialization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(startupServiceProvider.notifier).initialize();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(startupServiceProvider);

    // Transition to main app when interactive
    if (progress.isInteractive && !_showChild) {
      _showChild = true;
      _fadeController.forward();
    }

    return Stack(
      children: [
        // Main app (hidden until interactive)
        if (_showChild)
          FadeTransition(
            opacity: _fadeAnimation,
            child: widget.child,
          ),

        // Splash screen (visible until interactive)
        if (!_showChild || _fadeController.value < 1.0)
          IgnorePointer(
            ignoring: _showChild,
            child: AnimatedOpacity(
              opacity: _showChild ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 300),
              child: _SplashContent(
                progress: progress,
              ),
            ),
          ),
      ],
    );
  }
}

class _SplashContent extends StatelessWidget {
  final StartupProgress progress;

  const _SplashContent({
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.darkTheme.scaffoldBackgroundColor
          : AppTheme.primaryGreen,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // App icon/logo
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.chat_bubble_rounded,
                    size: 64,
                    color: AppTheme.primaryGreen,
                  ),
                ),

                const SizedBox(height: 32),

                // App name
                Text(
                  'AntInvestor Chat',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),

                const SizedBox(height: 8),

                // Tagline
                Text(
                  'Automated and secure group credit & savings',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.7)
                        : Colors.white.withValues(alpha: 0.9),
                  ),
                ),

                const Spacer(flex: 2),

                // Progress indicator
                if (progress.hasError) ...[
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.red.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to start app',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.red.shade300,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    progress.errorMessage ?? 'Unknown error',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ] else ...[
                  // Progress bar
                  SizedBox(
                    width: 200,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress.progress,
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.white.withValues(alpha: 0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDark ? AppTheme.primaryGreen : Colors.white,
                        ),
                        minHeight: 4,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Current task
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      progress.currentTask ?? 'Starting...',
                      key: ValueKey(progress.currentTask),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.6)
                            : Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],

                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

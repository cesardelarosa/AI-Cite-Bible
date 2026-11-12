import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/engine/engine_models.dart';

enum BreathingPattern {
  box4444(
    label: '4·4·4·4',
    phaseSeconds: 4,
    hasRestPhase: true,
  ),
  triangular444(
    label: '4·4·4',
    phaseSeconds: 4,
    hasRestPhase: false,
  );

  const BreathingPattern({
    required this.label,
    required this.phaseSeconds,
    required this.hasRestPhase,
  });

  final String label;
  final int phaseSeconds;
  final bool hasRestPhase;

  int get phaseCount => hasRestPhase ? 4 : 3;
  int get totalSeconds => phaseSeconds * phaseCount;
}

enum _BreathPhase {
  inhale,
  hold,
  exhale,
  rest,
}

class _PhaseSnapshot {
  const _PhaseSnapshot({
    required this.phase,
    required this.label,
    required this.secondsRemaining,
    required this.expansion,
  });

  final _BreathPhase phase;
  final String label;
  final int secondsRemaining;
  final double expansion;
}

class MeditationScreen extends StatefulWidget {
  const MeditationScreen({
    super.key,
    required this.hit,
  });

  final SearchHit hit;

  @override
  State<MeditationScreen> createState() => _MeditationScreenState();
}

class _MeditationScreenState extends State<MeditationScreen>
    with SingleTickerProviderStateMixin {
  static const Color _bgColor = Color(0xFF121212);
  static const Color _textPrimary = Color(0xFFE0E0E0);
  static const Color _textMuted = Color(0xFF969188);
  static const Color _accentStone = Color(0xFFC8BFA8);

  late final AnimationController _controller;
  BreathingPattern _pattern = BreathingPattern.box4444;
  _BreathPhase? _lastNotifiedPhase;
  double _lastValue = 0.0;
  bool _isPlaying = true;
  int _completedCycles = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: _pattern.totalSeconds),
    )..addListener(_handleAnimationTick);

    _startBreathing();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleAnimationTick)
      ..dispose();
    super.dispose();
  }

  void _startBreathing() {
    _isPlaying = true;
    _lastValue = _controller.value;
    final initialPhase = _resolvePhase(_controller.value).phase;
    _triggerPhaseHaptic(initialPhase);
    _lastNotifiedPhase = initialPhase;
    unawaited(_controller.repeat());
  }

  void _handleAnimationTick() {
    if (!_isPlaying) {
      return;
    }

    final value = _controller.value;
    // Detecta el reinicio de ciclo en `repeat()` (de ~1.0 a ~0.0).
    if (value < _lastValue && mounted) {
      setState(() {
        _completedCycles++;
      });
    }
    _lastValue = value;

    final currentPhase = _resolvePhase(value).phase;
    if (currentPhase != _lastNotifiedPhase) {
      _lastNotifiedPhase = currentPhase;
      _triggerPhaseHaptic(currentPhase);
    }
  }

  void _triggerPhaseHaptic(_BreathPhase phase) {
    switch (phase) {
      case _BreathPhase.inhale:
      case _BreathPhase.exhale:
        unawaited(HapticFeedback.mediumImpact());
      case _BreathPhase.hold:
      case _BreathPhase.rest:
        unawaited(HapticFeedback.lightImpact());
    }
  }

  void _togglePlayPause() {
    setState(() {
      if (_isPlaying) {
        _isPlaying = false;
        _controller.stop(canceled: false);
      } else {
        _isPlaying = true;
        _lastValue = _controller.value;
        final phase = _resolvePhase(_controller.value).phase;
        _lastNotifiedPhase = phase;
        _triggerPhaseHaptic(phase);
        unawaited(_controller.repeat());
      }
    });
  }

  void _resetCycle() {
    setState(() {
      _completedCycles = 0;
      _lastValue = 0.0;
      _controller.reset();
      if (_isPlaying) {
        _lastNotifiedPhase = _BreathPhase.inhale;
        _triggerPhaseHaptic(_BreathPhase.inhale);
        unawaited(_controller.repeat());
      } else {
        _lastNotifiedPhase = null;
      }
    });
  }

  void _switchPattern(BreathingPattern nextPattern) {
    if (_pattern == nextPattern) {
      return;
    }
    setState(() {
      _pattern = nextPattern;
      _completedCycles = 0;
      _lastValue = 0.0;
      _controller
        ..stop()
        ..duration = Duration(seconds: _pattern.totalSeconds)
        ..reset();
      if (_isPlaying) {
        _lastNotifiedPhase = _BreathPhase.inhale;
        _triggerPhaseHaptic(_BreathPhase.inhale);
        unawaited(_controller.repeat());
      } else {
        _lastNotifiedPhase = null;
      }
    });
  }

  _PhaseSnapshot _resolvePhase(double t) {
    final normalized = t.clamp(0.0, 0.999999);
    final totalSec = _pattern.totalSeconds.toDouble();
    final elapsedSec = normalized * totalSec;
    final phaseDuration = _pattern.phaseSeconds.toDouble();
    final phaseIndex = (elapsedSec / phaseDuration).floor();
    final phaseProgress = ((elapsedSec % phaseDuration) / phaseDuration).clamp(0.0, 1.0);
    final remaining = math.max(
      1,
      (_pattern.phaseSeconds - (elapsedSec % phaseDuration)).ceil(),
    );

    if (_pattern.hasRestPhase) {
      switch (phaseIndex) {
        case 0:
          return _PhaseSnapshot(
            phase: _BreathPhase.inhale,
            label: 'Inhalar',
            secondsRemaining: remaining,
            expansion: Curves.easeInOutSine.transform(phaseProgress),
          );
        case 1:
          return _PhaseSnapshot(
            phase: _BreathPhase.hold,
            label: 'Retener',
            secondsRemaining: remaining,
            expansion: 1.0,
          );
        case 2:
          return _PhaseSnapshot(
            phase: _BreathPhase.exhale,
            label: 'Exhalar',
            secondsRemaining: remaining,
            expansion: 1.0 - Curves.easeInOutSine.transform(phaseProgress),
          );
        default:
          return _PhaseSnapshot(
            phase: _BreathPhase.rest,
            label: 'Pausa',
            secondsRemaining: remaining,
            expansion: 0.0,
          );
      }
    } else {
      switch (phaseIndex) {
        case 0:
          return _PhaseSnapshot(
            phase: _BreathPhase.inhale,
            label: 'Inhalar',
            secondsRemaining: remaining,
            expansion: Curves.easeInOutSine.transform(phaseProgress),
          );
        case 1:
          return _PhaseSnapshot(
            phase: _BreathPhase.hold,
            label: 'Retener',
            secondsRemaining: remaining,
            expansion: 1.0,
          );
        default:
          return _PhaseSnapshot(
            phase: _BreathPhase.exhale,
            label: 'Exhalar',
            secondsRemaining: remaining,
            expansion: 1.0 - Curves.easeInOutSine.transform(phaseProgress),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final verse = widget.hit.verse;

    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
              child: Column(
                children: <Widget>[
                  _buildTopBar(verse),
                  const Spacer(flex: 2),
                  Text(
                    verse.reference,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'serif',
                      color: _accentStone,
                      fontSize: 16,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '«${verse.text}»',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'serif',
                      color: _textPrimary,
                      fontSize: 21,
                      height: 1.65,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const Spacer(flex: 2),
                  GestureDetector(
                    onTap: _togglePlayPause,
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        final snapshot = _resolvePhase(_controller.value);
                        return _BreathingCircle(
                          snapshot: snapshot,
                          isPlaying: _isPlaying,
                        );
                      },
                    ),
                  ),
                  const Spacer(flex: 2),
                  _buildControls(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(VerseRecord verse) {
    return Row(
      children: <Widget>[
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Volver',
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: _textMuted,
            size: 21,
          ),
        ),
        const Spacer(),
        Text(
          verse.canonicalId,
          style: const TextStyle(
            color: Color(0xFF6B6760),
            fontSize: 11.5,
            letterSpacing: 1.6,
          ),
        ),
        const Spacer(),
        const SizedBox(width: 48),
      ],
    );
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton(
          onPressed: _resetCycle,
          tooltip: 'Reiniciar ciclo',
          icon: const Icon(Icons.refresh_rounded, color: _textMuted, size: 20),
        ),
        const SizedBox(width: 14),
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF2E2D2A)),
            color: const Color(0xFF1A1A1A),
          ),
          child: IconButton(
            onPressed: _togglePlayPause,
            tooltip: _isPlaying ? 'Pausar respiración' : 'Reanudar respiración',
            icon: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: _textPrimary,
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 14),
        PopupMenuButton<BreathingPattern>(
          tooltip: 'Ritmo respiratorio',
          color: const Color(0xFF1C1C1C),
          onSelected: _switchPattern,
          itemBuilder: (context) => BreathingPattern.values.map((pattern) {
            return PopupMenuItem<BreathingPattern>(
              value: pattern,
              child: Text(
                'Ritmo ${pattern.label} (${pattern.totalSeconds}s)',
                style: TextStyle(
                  color: pattern == _pattern ? _accentStone : _textPrimary,
                  fontSize: 13.5,
                ),
              ),
            );
          }).toList(growable: false),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              _completedCycles > 0
                  ? '${_pattern.label} · $_completedCycles'
                  : _pattern.label,
              style: const TextStyle(
                color: _textMuted,
                fontSize: 12.5,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BreathingCircle extends StatelessWidget {
  const _BreathingCircle({
    required this.snapshot,
    required this.isPlaying,
  });

  final _PhaseSnapshot snapshot;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CustomPaint(
            size: const Size(220, 220),
            painter: _BreathingRingPainter(
              expansion: snapshot.expansion,
              isHold: snapshot.phase == _BreathPhase.hold,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                isPlaying ? snapshot.label : 'En pausa',
                style: const TextStyle(
                  fontFamily: 'serif',
                  color: Color(0xFFE0E0E0),
                  fontSize: 17,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isPlaying ? '${snapshot.secondsRemaining}s' : '·',
                style: const TextStyle(
                  color: Color(0xFF969188),
                  fontSize: 13,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BreathingRingPainter extends CustomPainter {
  const _BreathingRingPainter({
    required this.expansion,
    required this.isHold,
  });

  final double expansion;
  final bool isHold;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width * 0.45;
    final minRadius = size.width * 0.23;
    final currentRadius = minRadius + (maxRadius - minRadius) * expansion;

    // Halo exterior muy tenue
    final outerFill = Paint()
      ..color = Color.fromRGBO(
        200,
        191,
        168,
        0.04 + (0.07 * expansion),
      )
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, currentRadius, outerFill);

    // Anillo geométrico principal
    final ringPaint = Paint()
      ..color = Color.fromRGBO(
        200,
        191,
        168,
        isHold ? 0.55 : 0.25 + (0.28 * expansion),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25;
    canvas.drawCircle(center, currentRadius, ringPaint);

    // Anillo guía exterior fijo (referencia visual suave)
    final guidePaint = Paint()
      ..color = const Color.fromRGBO(224, 224, 224, 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawCircle(center, maxRadius, guidePaint);
  }

  @override
  bool shouldRepaint(covariant _BreathingRingPainter oldDelegate) {
    return oldDelegate.expansion != expansion || oldDelegate.isHold != isHold;
  }
}

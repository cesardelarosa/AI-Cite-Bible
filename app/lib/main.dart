import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/engine/engine_models.dart';
import 'core/engine/engine_worker.dart';
import 'core/storage/asset_bootstrap.dart';
import 'presentation/search_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF121212),
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF121212),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const CiteMeditationApp());
}

class CiteMeditationApp extends StatelessWidget {
  const CiteMeditationApp({super.key});

  @override
  Widget build(BuildContext context) {
    const colorScheme = ColorScheme.dark(
      surface: Color(0xFF121212),
      onSurface: Color(0xFFE0E0E0),
      primary: Color(0xFFC8BFA8),
      onPrimary: Color(0xFF121212),
      secondary: Color(0xFF8C8575),
      onSecondary: Color(0xFF121212),
    );

    return MaterialApp(
      title: 'Quietud',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFF121212),
        fontFamily: 'serif',
      ),
      home: const _AppBootstrapGate(),
    );
  }
}

class _AppBootstrapGate extends StatefulWidget {
  const _AppBootstrapGate();

  @override
  State<_AppBootstrapGate> createState() => _AppBootstrapGateState();
}

class _AppBootstrapGateState extends State<_AppBootstrapGate> {
  final AssetBootstrap _bootstrap = AssetBootstrap();
  final EngineWorker _worker = EngineWorker();

  CorpusInfo? _corpusInfo;
  String? _error;
  String _statusMessage = 'Preparando entorno offline...';
  double? _progress;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeEngine());
  }

  @override
  void dispose() {
    unawaited(_worker.dispose());
    super.dispose();
  }

  Future<void> _initializeEngine() async {
    setState(() {
      _corpusInfo = null;
      _error = null;
      _progress = null;
      _statusMessage = 'Verificando artefactos locales...';
    });

    try {
      final paths = await _bootstrap.ensureReady(
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            _progress = progress.fraction;
            _statusMessage =
                'Preparando ${progress.currentAssetName} (${progress.currentIndex}/${progress.totalFiles})';
          });
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _progress = null;
        _statusMessage = 'Cargando modelo neuronal e índice vectorial...';
      });

      final info = await _worker.init(paths);

      if (!mounted) {
        return;
      }

      setState(() {
        _corpusInfo = info;
      });
    } catch (err) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = err.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _corpusInfo;
    if (info != null) {
      return SearchScreen(
        engineWorker: _worker,
        corpusInfo: info,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: _error != null ? _buildErrorView() : _buildLoadingView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(
          'QUIETUD',
          style: TextStyle(
            color: Color(0xFFC8BFA8),
            fontSize: 13,
            letterSpacing: 3.2,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: 180,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 2,
              backgroundColor: const Color(0xFF262626),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFC8BFA8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          _statusMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'serif',
            color: Color(0xFF969188),
            fontSize: 13.5,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(
          'No se pudo iniciar el motor offline',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'serif',
            color: Color(0xFFE0E0E0),
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _error ?? 'Error desconocido',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF969188),
            fontSize: 13,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: _initializeEngine,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFC8BFA8),
            side: const BorderSide(color: Color(0xFF2C2C2C)),
          ),
          child: const Text('Reintentar'),
        ),
      ],
    );
  }
}

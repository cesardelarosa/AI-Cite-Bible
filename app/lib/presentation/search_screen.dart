import 'dart:async';

import 'package:flutter/material.dart';

import '../core/engine/engine_models.dart';
import '../core/engine/engine_worker.dart';
import 'meditation_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.engineWorker,
  });

  final EngineWorker engineWorker;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const Color _bgColor = Color(0xFF121212);
  static const Color _surfaceColor = Color(0xFF191919);
  static const Color _borderColor = Color(0xFF282828);
  static const Color _textPrimary = Color(0xFFE0E0E0);
  static const Color _textMuted = Color(0xFF969188);
  static const Color _accentStone = Color(0xFFC8BFA8);

  static const List<String> _contemplativeSeeds = <String>[
    'ansiedad y temor por el futuro',
    'cansancio del alma y falta de paz',
    'gratitud en medio de la prueba',
    'necesito perdonar',
  ];

  final TextEditingController _queryController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  List<SearchHit> _hits = const <SearchHit>[];
  bool _isSearching = false;
  bool _hasSearched = false;
  String? _errorMessage;
  int _activeSearchToken = 0;

  @override
  void initState() {
    super.initState();
    _queryController.addListener(_onQueryTextChanged);
  }

  @override
  void dispose() {
    _queryController.removeListener(_onQueryTextChanged);
    _queryController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _onQueryTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _executeSearch([String? overrideQuery]) async {
    final query = (overrideQuery ?? _queryController.text).trim();
    if (overrideQuery != null) {
      _queryController.text = overrideQuery;
      _queryController.selection = TextSelection.collapsed(
        offset: overrideQuery.length,
      );
    }

    if (query.isEmpty) {
      setState(() {
        _hits = const <SearchHit>[];
        _errorMessage = null;
        _hasSearched = false;
      });
      return;
    }

    _inputFocusNode.unfocus();
    final requestToken = ++_activeSearchToken;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _hasSearched = true;
    });

    try {
      final results = await widget.engineWorker.search(query, topK: 3);
      if (!mounted || requestToken != _activeSearchToken) {
        return;
      }
      setState(() {
        _hits = results;
        _isSearching = false;
      });
    } on EngineException catch (err) {
      if (!mounted || requestToken != _activeSearchToken) {
        return;
      }
      setState(() {
        _hits = const <SearchHit>[];
        _isSearching = false;
        _errorMessage = err.message;
      });
    } catch (err) {
      if (!mounted || requestToken != _activeSearchToken) {
        return;
      }
      setState(() {
        _hits = const <SearchHit>[];
        _isSearching = false;
        _errorMessage = 'No se pudo completar la consulta: $err';
      });
    }
  }

  void _clearSearch() {
    _activeSearchToken++;
    _queryController.clear();
    setState(() {
      _hits = const <SearchHit>[];
      _isSearching = false;
      _hasSearched = false;
      _errorMessage = null;
    });
    _inputFocusNode.requestFocus();
  }

  void _openMeditation(SearchHit hit) {
    unawaited(
      Navigator.of(context).push(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, __, ___) => MeditationScreen(hit: hit),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              ),
              child: child,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: 12),
                  const Text(
                    'QUIETUD · RVR 1909',
                    style: TextStyle(
                      color: _textMuted,
                      fontSize: 11,
                      letterSpacing: 2.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '¿Qué habita en tu ánimo hoy?',
                    style: TextStyle(
                      fontFamily: 'serif',
                      color: _textPrimary,
                      fontSize: 24,
                      height: 1.3,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _buildSearchBar(),
                  const SizedBox(height: 24),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final hasText = _queryController.text.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _queryController,
              focusNode: _inputFocusNode,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.search,
              maxLines: 3,
              minLines: 1,
              style: const TextStyle(
                fontFamily: 'serif',
                color: _textPrimary,
                fontSize: 16,
                height: 1.45,
              ),
              cursorColor: _accentStone,
              decoration: const InputDecoration(
                hintText: 'Describe una emoción, carga o inquietud...',
                hintStyle: TextStyle(
                  fontFamily: 'serif',
                  color: Color(0xFF6B6760),
                  fontSize: 15,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
              onSubmitted: (_) => _executeSearch(),
            ),
          ),
          if (hasText)
            IconButton(
              onPressed: _clearSearch,
              tooltip: 'Limpiar',
              icon: const Icon(Icons.close, size: 18, color: _textMuted),
            ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: _isSearching ? null : () => _executeSearch(),
            tooltip: 'Buscar pasajes',
            icon: _isSearching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: _accentStone,
                    ),
                  )
                : const Icon(
                    Icons.arrow_forward_rounded,
                    size: 20,
                    color: _accentStone,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isSearching && _hits.isEmpty) {
      return const Center(
        child: Text(
          'Buscando en el canon...',
          style: TextStyle(
            fontFamily: 'serif',
            color: _textMuted,
            fontSize: 15,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textMuted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => _executeSearch(),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accentStone,
                side: const BorderSide(color: _borderColor),
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (!_hasSearched) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Algunas inquietudes frecuentes',
              style: TextStyle(
                color: _textMuted,
                fontSize: 12,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _contemplativeSeeds.map((seed) {
                return InkWell(
                  onTap: () => _executeSearch(seed),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: _surfaceColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _borderColor),
                    ),
                    child: Text(
                      seed,
                      style: const TextStyle(
                        fontFamily: 'serif',
                        color: _textPrimary,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 36),
            const Text(
              '100 % local y sin conexión. Tus consultas nunca abandonan este dispositivo.',
              style: TextStyle(
                color: Color(0xFF63605A),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    if (_hits.isEmpty) {
      return const Center(
        child: Text(
          'No se recuperaron pasajes para esta consulta.',
          style: TextStyle(
            fontFamily: 'serif',
            color: _textMuted,
            fontSize: 15,
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _hits.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final hit = _hits[index];
        return _VerseHitCard(
          hit: hit,
          onTap: () => _openMeditation(hit),
        );
      },
    );
  }
}

class _VerseHitCard extends StatelessWidget {
  const _VerseHitCard({
    required this.hit,
    required this.onTap,
  });

  final SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final relevance = hit.normalizedRelevance;
    final relevancePercent = (relevance * 100).round();

    return Material(
      color: const Color(0xFF181818),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: const Color(0x1AC8BFA8),
        highlightColor: const Color(0x0FC8BFA8),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF262626)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      hit.verse.reference,
                      style: const TextStyle(
                        fontFamily: 'serif',
                        color: Color(0xFFC8BFA8),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  Text(
                    'Afinidad $relevancePercent %',
                    style: const TextStyle(
                      color: Color(0xFF7B776F),
                      fontSize: 11.5,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                hit.verse.text,
                style: const TextStyle(
                  fontFamily: 'serif',
                  color: Color(0xFFE0E0E0),
                  fontSize: 16.5,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: relevance,
                        minHeight: 2,
                        backgroundColor: const Color(0xFF262626),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF8C8575),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Meditar',
                    style: TextStyle(
                      color: Color(0xFF969188),
                      fontSize: 12,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: Color(0xFF969188),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// lib/screens/teacher_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/session_model.dart';
import '../models/question_model.dart';
import '../services/firebase_service.dart';

class TeacherScreen extends StatefulWidget {
  const TeacherScreen({super.key});

  @override
  State<TeacherScreen> createState() => _TeacherScreenState();
}

class _TeacherScreenState extends State<TeacherScreen> {
  String? gameId;
  GameModel? _game;

  List<QueryDocumentSnapshot> quizzes = [];
  bool isLoading = false;
  bool _isTransitioning = false;

  // Evita reiniciar el timer si ya corre para la misma pregunta
  int _lastTimerQuestionIndex = -1;

  // Timer Trigger
  Timer? _questionTimer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _loadQuizzes();
  }

  @override
  void dispose() {
    _questionTimer?.cancel();
    super.dispose();
  }

  // ── Carga inicial ─────────────────────────────────────────────────────────

  Future<void> _loadQuizzes() async {
    setState(() => isLoading = true);
    try {
      final list = await FirebaseService.getQuizzes();
      setState(() {
        quizzes = list;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      _showError('Error al cargar cuestionarios: $e');
    }
  }

  Future<void> _createGame(String quizId) async {
    setState(() => isLoading = true);
    try {
      final id = await FirebaseService.createGame(quizId);
      final game = await FirebaseService.getGame(id);
      setState(() {
        gameId = id;
        _game = game;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      _showError('Error al crear juego: $e');
    }
  }

  void _resetGame() {
    _questionTimer?.cancel();
    setState(() {
      gameId = null;
      _game = null;
      _isTransitioning = false;
      _lastTimerQuestionIndex = -1;
      _remainingSeconds = 0;
    });
    _loadQuizzes();
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // TIMER TRIGGER
  // ════════════════════════════════════════════════════════════════════════════

  void _startQuestionTimer(int questionIndex, int timeLimit) {
    if (_lastTimerQuestionIndex == questionIndex) return;
    _lastTimerQuestionIndex = questionIndex;

    _questionTimer?.cancel();
    setState(() => _remainingSeconds = timeLimit);

    _questionTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _remainingSeconds--);

      if (_remainingSeconds <= 0) {
        t.cancel();
        if (!_isTransitioning) await _triggerShowScores(questionIndex);
      }
    });
  }

  // ════════════════════════════════════════════════════════════════════════════
  // TRANSICIONES
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _handleNextButton(GameModel game) async {
    if (_isTransitioning) return;
    setState(() => _isTransitioning = true);

    try {
      if (game.sessionState == SessionState.question) {
        _questionTimer?.cancel();
        await _triggerShowScores(game.currentQuestionIndex);
      } else if (game.sessionState == SessionState.showScores) {
        if (game.isLastQuestion) {
          await FirebaseService.endGame(gameId!);
        } else {
          await FirebaseService.goToNextQuestion(
              gameId!, game.currentQuestionIndex + 1);
        }
      }
    } catch (e) {
      _showError('Error en transición: $e');
    } finally {
      if (mounted) setState(() => _isTransitioning = false);
    }
  }

  Future<void> _triggerShowScores(int questionIndex) async {
    setState(() => _isTransitioning = true);
    try {
      await FirebaseService.goToShowScores(
          gameId!, questionIndex, _game!.questions);
    } catch (e) {
      _showError('Error al calcular puntos: $e');
    } finally {
      if (mounted) setState(() => _isTransitioning = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profesor - Mini Kahoot'),
        centerTitle: true,
        leading: gameId != null ? BackButton(onPressed: _resetGame) : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: gameId == null ? _buildQuizList() : _buildGameView(),
      ),
    );
  }

  // ── Lista de quizzes ──────────────────────────────────────────────────────

  Widget _buildQuizList() {
    if (isLoading && quizzes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (quizzes.isEmpty) {
      return const Center(
        child: Text('No hay cuestionarios disponibles.',
            style: TextStyle(fontSize: 18, color: Colors.grey)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Elige un cuestionario:',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            itemCount: quizzes.length,
            itemBuilder: (_, i) {
              final quiz = quizzes[i];
              final data = quiz.data() as Map<String, dynamic>;
              final title = data['title'] as String? ?? 'Sin título';
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  title: Text(title,
                      style:
                          const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('ID: ${quiz.id}'),
                  trailing: ElevatedButton(
                    onPressed:
                        isLoading ? null : () => _createGame(quiz.id),
                    child: const Text('Iniciar'),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Vista del juego ───────────────────────────────────────────────────────

  Widget _buildGameView() {
    return StreamBuilder<GameModel>(
      stream: FirebaseService.gameStream(gameId!),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final game = snapshot.data!;

        // Mantener referencia local actualizada
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _game = game);
        });

        // Completion Trigger
        if (game.sessionState == SessionState.question &&
            game.allAnswered &&
            !_isTransitioning) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_isTransitioning) {
              _questionTimer?.cancel();
              _triggerShowScores(game.currentQuestionIndex);
            }
          });
        }

        switch (game.sessionState) {
          case SessionState.start:
            return _buildLobby(game);

          case SessionState.question:
            final question = game.currentQuestion;
            if (question != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _startQuestionTimer(
                    game.currentQuestionIndex, question.timeLimit);
              });
            }
            return _buildQuestionView(game);

          case SessionState.showScores:
            _questionTimer?.cancel();
            return _buildShowScoresView(game);

          case SessionState.finished:
            return _buildFinalResultsView(game);

          default:
            return const Center(child: Text('Estado desconocido'));
        }
      },
    );
  }

  // ── START: Lobby ──────────────────────────────────────────────────────────

  Widget _buildLobby(GameModel game) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Código del Juego:',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        Text(
          '${game.code}',
          style: const TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
              letterSpacing: 8),
        ),
        const Text('Comparte este código con tus alumnos',
            style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 30),
        const Text('Alumnos conectados:',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.playersStream(gameId!),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final players = snap.data!.docs;
              return Column(
                children: [
                  Text('${players.length} alumno(s)',
                      style: const TextStyle(
                          fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: players.length,
                      itemBuilder: (_, i) => ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(
                            players[i]['name'] as String? ?? 'Alumno'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: players.isNotEmpty
                        ? () => FirebaseService.startGame(gameId!)
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Empezar Kahoot',
                        style: TextStyle(fontSize: 18)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 40, vertical: 14),
                      backgroundColor: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ── QUESTION ──────────────────────────────────────────────────────────────

  Widget _buildQuestionView(GameModel game) {
    final question = game.currentQuestion;
    if (question == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildProgressHeader(game),
        const SizedBox(height: 12),
        _buildTimerBar(question.timeLimit),
        const SizedBox(height: 16),
        _buildQuestionCard(question.text),
        const SizedBox(height: 12),
        ...question.options.map((opt) =>
            _buildOptionTile(opt, question.isCorrectOption(opt))),
        const SizedBox(height: 12),
        _buildAnswerCounter(game),
        const Spacer(),
        _buildContextualButton(game),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── SHOW_SCORES ───────────────────────────────────────────────────────────

  Widget _buildShowScoresView(GameModel game) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.purple.shade700,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              const Text('🏆 Puntuaciones',
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold)),
              Text(
                game.isLastQuestion
                    ? 'Última pregunta completada'
                    : 'Pregunta ${game.currentQuestionIndex + 1} / ${game.questions.length} completada',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: game.currentRanking.isEmpty
              ? const Center(
                  child: Text('Sin puntuaciones aún',
                      style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: game.currentRanking.length,
                  itemBuilder: (_, i) {
                    final entry = game.currentRanking[i];
                    final medals = ['🥇', '🥈', '🥉'];
                    final medal = i < 3 ? medals[i] : '${i + 1}.';
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: Text(medal,
                            style: const TextStyle(fontSize: 22)),
                        title: Text(entry.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        trailing: Text(
                          '${entry.score} pts',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber),
                        ),
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 12),
        _buildContextualButton(game),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── FINISHED ──────────────────────────────────────────────────────────────

  Widget _buildFinalResultsView(GameModel game) {
    final sorted = [...game.results]
      ..sort((a, b) => b.score.compareTo(a.score));

    return Column(
      children: [
        const Text('🎉 ¡Juego Terminado!',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            itemCount: sorted.length,
            itemBuilder: (_, i) {
              final medals = ['🥇', '🥈', '🥉'];
              final medal = i < 3 ? medals[i] : '${i + 1}.';
              return Card(
                child: ListTile(
                  leading:
                      Text(medal, style: const TextStyle(fontSize: 22)),
                  title: Text(sorted[i].name),
                  trailing: Text('${sorted[i].score} pts',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _resetGame,
          icon: const Icon(Icons.replay),
          label: const Text('Jugar de Nuevo'),
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  horizontal: 40, vertical: 14)),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Botón contextual ──────────────────────────────────────────────────────

  Widget _buildContextualButton(GameModel game) {
    String label;
    IconData icon;
    Color color;

    if (game.sessionState == SessionState.question) {
      label = 'Pasar a Puntuaciones';
      icon = Icons.bar_chart;
      color = Colors.orange.shade700;
    } else if (game.sessionState == SessionState.showScores) {
      if (game.isLastQuestion) {
        label = 'Ver Resultados Finales';
        icon = Icons.emoji_events;
        color = Colors.red.shade700;
      } else {
        label = 'Siguiente Pregunta →';
        icon = Icons.arrow_forward;
        color = Colors.blue;
      }
    } else {
      return const SizedBox.shrink();
    }

    return ElevatedButton.icon(
      onPressed:
          _isTransitioning ? null : () => _handleNextButton(game),
      icon: _isTransitioning
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : Icon(icon),
      label: Text(label, style: const TextStyle(fontSize: 18)),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        backgroundColor: color,
      ),
    );
  }

  // ── Widgets auxiliares ────────────────────────────────────────────────────

  Widget _buildProgressHeader(GameModel game) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade800,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Pregunta ${game.currentQuestionIndex + 1} / ${game.questions.length}',
        textAlign: TextAlign.center,
        style:
            const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTimerBar(int timeLimit) {
    final ratio = timeLimit > 0 ? _remainingSeconds / timeLimit : 0.0;
    final color = _remainingSeconds > 5 ? Colors.green : Colors.red;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer, color: color),
            const SizedBox(width: 6),
            Text(
              '$_remainingSeconds s',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 10,
            backgroundColor: Colors.grey[800],
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionCard(String text) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style:
            const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildOptionTile(String text, bool isCorrect) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isCorrect ? Colors.green.shade800 : Colors.grey[800],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color:
              isCorrect ? Colors.greenAccent : Colors.grey.shade700,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isCorrect ? Icons.check_circle : Icons.circle_outlined,
            color: isCorrect ? Colors.greenAccent : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 16,
                fontWeight:
                    isCorrect ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerCounter(GameModel game) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            game.allAnswered ? Icons.check_circle : Icons.hourglass_top,
            color: game.allAnswered ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          Text(
            'Han respondido: ${game.answeredCount} / ${game.totalPlayers}',
            style: const TextStyle(fontSize: 18),
          ),
        ],
      ),
    );
  }
}
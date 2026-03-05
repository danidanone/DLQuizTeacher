// lib/services/firebase_service.dart

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/session_model.dart';
import '../models/question_model.dart';

// ════════════════════════════════════════════════════════════════════════════
// ESTADOS GLOBALES DE LA SESIÓN
//   START        → Sala de espera / lobby
//   QUESTION     → Mostrando pregunta + cronómetro activo
//   SHOW_SCORES  → Ranking intermedio entre preguntas
//   FINISHED     → Juego terminado, resultados finales
// ════════════════════════════════════════════════════════════════════════════
class SessionState {
  static const String start = 'START';
  static const String question = 'QUESTION';
  static const String showScores = 'SHOW_SCORES';
  static const String finished = 'FINISHED';
}

class FirebaseService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Auth ──────────────────────────────────────────────────────────────────

  static Future<void> login() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
  }

  // ── Código único ──────────────────────────────────────────────────────────

  static Future<int> _generateUniqueCode() async {
    int code;
    bool exists;
    do {
      code = Random().nextInt(900000) + 100000;
      final q = await _db
          .collection('games')
          .where('code', isEqualTo: code)
          .where('sessionState', isEqualTo: SessionState.start)
          .get();
      exists = q.docs.isNotEmpty;
    } while (exists);
    return code;
  }

  // ── Quizzes ───────────────────────────────────────────────────────────────

  static Future<List<QueryDocumentSnapshot>> getQuizzes() async {
    await login();
    final snap = await _db.collection('quizzes').get();
    return snap.docs;
  }

  // ── Crear juego ───────────────────────────────────────────────────────────

  static Future<String> createGame(String quizId) async {
    await login();
    final code = await _generateUniqueCode();
    final user = _auth.currentUser;

    final qSnap = await _db
        .collection('quizzes')
        .doc(quizId)
        .collection('questions')
        .get();

    final questions = qSnap.docs
        .map((doc) => QuestionModel.fromMap(doc.id, doc.data()).toMap())
        .toList();

    final doc = await _db.collection('games').add({
      'code': code,
      'sessionState': SessionState.start,
      'status': 'waiting',
      'createdAt': FieldValue.serverTimestamp(),
      'creatorId': user?.uid,
      'quizId': quizId,
      'currentQuestionIndex': -1,
      'questions': questions,
      'scores': {},
      'totalPlayers': 0,
      'answeredCount': 0,
    });

    return doc.id;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // MÁQUINA DE ESTADOS
  //
  // Flujo:  START → QUESTION → SHOW_SCORES → QUESTION → ... → FINISHED
  //
  // Triggers QUESTION → SHOW_SCORES:
  //   1. Timer Trigger:      temporizador llega a 0
  //   2. Completion Trigger: answeredCount >= totalPlayers
  //   3. Manual Trigger:     profesor pulsa "Pasar a Puntuaciones"
  //
  // SHOW_SCORES → QUESTION/FINISHED:
  //   Solo el profesor puede avanzar (punto de bloqueo para alumnos).
  // ════════════════════════════════════════════════════════════════════════════

  /// START → QUESTION
  static Future<void> startGame(String gameId) async {
    final playersSnap = await _db
        .collection('games')
        .doc(gameId)
        .collection('players')
        .get();

    await _db.collection('games').doc(gameId).update({
      'sessionState': SessionState.question,
      'status': 'running',
      'currentQuestionIndex': 0,
      'totalPlayers': playersSnap.docs.length,
      'answeredCount': 0,
    });
  }

  /// QUESTION → SHOW_SCORES
  /// Guard: si ya no estamos en QUESTION no hace nada (evita doble transición).
  static Future<void> goToShowScores(
    String gameId,
    int questionIndex,
    List<QuestionModel> questions,
  ) async {
    final gameDoc = await _db.collection('games').doc(gameId).get();
    final game = GameModel.fromDoc(gameDoc);

    if (game.sessionState != SessionState.question) return;

    final answersSnap = await _db
        .collection('games')
        .doc(gameId)
        .collection('answers')
        .where('questionIndex', isEqualTo: questionIndex)
        .get();

    final updatedScores = Map<String, int>.from(game.scores);

    if (questionIndex < questions.length) {
      final question = questions[questionIndex];
      for (final ans in answersSnap.docs) {
        final data = ans.data();
        final playerId = data['playerId'] as String;
        final selectedIdx = data['selectedOptionIndex'] as int;
        final isCorrect = selectedIdx >= 0 &&
            selectedIdx < question.options.length &&
            question.isCorrectOption(question.options[selectedIdx]);

        updatedScores[playerId] =
            (updatedScores[playerId] ?? 0) + (isCorrect ? question.points : 0);
      }
    }

    final ranking = updatedScores.entries
        .map((e) => RankingEntry(name: e.key, score: e.value).toMap())
        .toList()
      ..sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    await _db.collection('games').doc(gameId).update({
      'sessionState': SessionState.showScores,
      'scores': updatedScores,
      'currentRanking': ranking,
    });
  }

  /// SHOW_SCORES → QUESTION (siguiente pregunta)
  static Future<void> goToNextQuestion(String gameId, int nextIndex) async {
    final answers = await _db
        .collection('games')
        .doc(gameId)
        .collection('answers')
        .get();
    for (final doc in answers.docs) {
      await doc.reference.delete();
    }

    await _db.collection('games').doc(gameId).update({
      'sessionState': SessionState.question,
      'currentQuestionIndex': nextIndex,
      'answeredCount': 0,
    });
  }

  /// SHOW_SCORES → FINISHED
  static Future<void> endGame(String gameId) async {
    final gameDoc = await _db.collection('games').doc(gameId).get();
    final game = GameModel.fromDoc(gameDoc);

    final finalRanking = game.scores.entries
        .map((e) => RankingEntry(name: e.key, score: e.value).toMap())
        .toList()
      ..sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    await _db.collection('games').doc(gameId).update({
      'sessionState': SessionState.finished,
      'status': 'finished',
      'results': finalRanking,
      'finishedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  static Stream<GameModel> gameStream(String gameId) {
    return _db
        .collection('games')
        .doc(gameId)
        .snapshots()
        .map((doc) => GameModel.fromDoc(doc));
  }

  static Stream<QuerySnapshot> playersStream(String gameId) {
    return _db
        .collection('games')
        .doc(gameId)
        .collection('players')
        .snapshots();
  }

  // ── Snapshots únicos ──────────────────────────────────────────────────────

  static Future<GameModel> getGame(String gameId) async {
    final doc = await _db.collection('games').doc(gameId).get();
    return GameModel.fromDoc(doc);
  }
}
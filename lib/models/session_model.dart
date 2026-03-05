// lib/models/session_model.dart
// Reemplaza el SessionModel original. Ahora contiene GameModel y RankingEntry
// que tipan el documento del juego leído desde Firestore.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'question_model.dart';

class RankingEntry {
  final String name;
  final int score;

  const RankingEntry({required this.name, required this.score});

  factory RankingEntry.fromMap(Map<String, dynamic> map) {
    return RankingEntry(
      name: map['name'] as String? ?? '',
      score: (map['score'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {'name': name, 'score': score};
}

class GameModel {
  final String id;
  final int code;
  final String sessionState;
  final String status;
  final int currentQuestionIndex;
  final List<QuestionModel> questions;
  final Map<String, int> scores;
  final int totalPlayers;
  final int answeredCount;
  final List<RankingEntry> currentRanking;
  final List<RankingEntry> results;
  final DateTime? createdAt;

  const GameModel({
    required this.id,
    required this.code,
    required this.sessionState,
    required this.status,
    required this.currentQuestionIndex,
    required this.questions,
    required this.scores,
    required this.totalPlayers,
    required this.answeredCount,
    required this.currentRanking,
    required this.results,
    this.createdAt,
  });

  factory GameModel.fromDoc(DocumentSnapshot doc) {
    final map = doc.data() as Map<String, dynamic>;

    final questions = (map['questions'] as List<dynamic>? ?? []).map((q) {
      final qMap = Map<String, dynamic>.from(q as Map);
      return QuestionModel.fromMap(qMap['id'] as String? ?? '', qMap);
    }).toList();

    final scores = (map['scores'] as Map<String, dynamic>? ?? {}).map(
      (k, v) => MapEntry(k, (v as num).toInt()),
    );

    final currentRanking =
        (map['currentRanking'] as List<dynamic>? ?? []).map((e) {
      return RankingEntry.fromMap(Map<String, dynamic>.from(e as Map));
    }).toList();

    final results = (map['results'] as List<dynamic>? ?? []).map((e) {
      return RankingEntry.fromMap(Map<String, dynamic>.from(e as Map));
    }).toList();

    return GameModel(
      id: doc.id,
      code: (map['code'] as num?)?.toInt() ?? 0,
      sessionState: map['sessionState'] as String? ?? 'START',
      status: map['status'] as String? ?? 'waiting',
      currentQuestionIndex:
          (map['currentQuestionIndex'] as num?)?.toInt() ?? -1,
      questions: questions,
      scores: scores,
      totalPlayers: (map['totalPlayers'] as num?)?.toInt() ?? 0,
      answeredCount: (map['answeredCount'] as num?)?.toInt() ?? 0,
      currentRanking: currentRanking,
      results: results,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'code': code,
        'sessionState': sessionState,
        'status': status,
        'currentQuestionIndex': currentQuestionIndex,
        'questions': questions.map((q) => q.toMap()).toList(),
        'scores': scores,
        'totalPlayers': totalPlayers,
        'answeredCount': answeredCount,
        'currentRanking': currentRanking.map((e) => e.toMap()).toList(),
        'results': results.map((e) => e.toMap()).toList(),
      };

  // ── Helpers ───────────────────────────────────────────────────────────────

  QuestionModel? get currentQuestion {
    if (currentQuestionIndex < 0 ||
        currentQuestionIndex >= questions.length) return null;
    return questions[currentQuestionIndex];
  }

  bool get isLastQuestion => currentQuestionIndex >= questions.length - 1;

  bool get allAnswered => totalPlayers > 0 && answeredCount >= totalPlayers;
}
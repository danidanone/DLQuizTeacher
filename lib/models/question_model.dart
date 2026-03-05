// lib/models/question_model.dart

class QuestionModel {
  final String id;
  final String text;
  final List<String> options;
  final List<String> correctAnswers;
  final int points;
  final String type;
  final int timeLimit;

  const QuestionModel({
    required this.id,
    required this.text,
    required this.options,
    required this.correctAnswers,
    required this.points,
    required this.type,
    required this.timeLimit,
  });

  factory QuestionModel.fromMap(String id, Map<String, dynamic> map) {
    return QuestionModel(
      id: id,
      text: map['text'] as String? ?? '',
      options: List<String>.from(map['options'] as List? ?? []),
      correctAnswers:
          List<String>.from(map['correctAnswers'] as List? ?? []),
      points: (map['points'] as num?)?.toInt() ?? 10,
      type: map['type'] as String? ?? 'multiple_choice',
      timeLimit: (map['timeLimit'] as num?)?.toInt() ?? 20,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'options': options,
        'correctAnswers': correctAnswers,
        'points': points,
        'type': type,
        'timeLimit': timeLimit,
      };

  bool isCorrectOption(String option) => correctAnswers.contains(option);
}
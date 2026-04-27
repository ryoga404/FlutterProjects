class QuestionSetModel {
  final String setId;
  final String setName;
  final DateTime createdAt;
  DateTime lastTrainedAt;

  Map<String, List<double>> questionVectors;
  Map<String, double> questionDifficulty;
  List<String> questionIds;
  List<List<double>> similarityMatrix;

  Map<String, double> topicProficiency;
  double overallProficiency;

  double modelAccuracy;
  int totalTrainingSamples;

  QuestionSetModel({
    required this.setId,
    required this.setName,
    required this.createdAt,
    required this.lastTrainedAt,
    this.questionVectors = const {},
    this.questionDifficulty = const {},
    this.questionIds = const [],
    this.similarityMatrix = const [],
    this.topicProficiency = const {},
    this.overallProficiency = 0.0,
    this.modelAccuracy = 0.0,
    this.totalTrainingSamples = 0,
  });

  Map<String, dynamic> toJson() => {
    'setId': setId,
    'setName': setName,
    'createdAt': createdAt.toIso8601String(),
    'lastTrainedAt': lastTrainedAt.toIso8601String(),
    'questionVectors': questionVectors,
    'questionDifficulty': questionDifficulty,
    'questionIds': questionIds,
    'similarityMatrix': similarityMatrix,
    'topicProficiency': topicProficiency,
    'overallProficiency': overallProficiency,
    'modelAccuracy': modelAccuracy,
    'totalTrainingSamples': totalTrainingSamples,
  };

  static QuestionSetModel fromJson(Map<String, dynamic> json) {
    return QuestionSetModel(
      setId: json['setId'] as String,
      setName: json['setName'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastTrainedAt: DateTime.parse(json['lastTrainedAt'] as String),
      questionVectors: Map<String, List<double>>.from(
        (json['questionVectors'] as Map? ?? {}).cast<String, dynamic>().map(
          (k, v) => MapEntry(k, List<double>.from(v as List)),
        ),
      ),
      questionDifficulty: Map<String, double>.from(json['questionDifficulty'] as Map? ?? {}),
      questionIds: List<String>.from(json['questionIds'] as List? ?? []),
      similarityMatrix: (json['similarityMatrix'] as List?)
          ?.map((row) => List<double>.from(row as List))
          .toList() ?? [],
      topicProficiency: Map<String, double>.from(json['topicProficiency'] as Map? ?? {}),
      overallProficiency: (json['overallProficiency'] as num?)?.toDouble() ?? 0.0,
      modelAccuracy: (json['modelAccuracy'] as num?)?.toDouble() ?? 0.0,
      totalTrainingSamples: json['totalTrainingSamples'] as int? ?? 0,
    );
  }
}

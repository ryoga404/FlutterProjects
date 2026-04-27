class QuestionSet {
  final String id;
  final String name;
  final String description;
  final DateTime createdAt;
  final DateTime? examDate;   // 試験日（未設定はnull）
  final int sortOrder;        // 表示順（小さいほど上）

  QuestionSet({
    required this.id,
    required this.name,
    required this.description,
    required this.createdAt,
    this.examDate,
    this.sortOrder = 0,
  });

  QuestionSet copyWith({
    String? name,
    String? description,
    DateTime? examDate,
    bool clearExamDate = false,
    int? sortOrder,
  }) {
    return QuestionSet(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt,
      examDate: clearExamDate ? null : (examDate ?? this.examDate),
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  factory QuestionSet.fromJson(Map<String, dynamic> json) {
    return QuestionSet(
      id: json['id'],
      name: json['name'],
      description: json['description'] ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      examDate: json['examDate'] != null
          ? DateTime.tryParse(json['examDate'] as String)
          : null,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'examDate': examDate?.toIso8601String(),
      'sortOrder': sortOrder,
    };
  }

  /// 試験日までの残り日数（過去の場合は負の値）
  int? get daysUntilExam {
    if (examDate == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exam = DateTime(examDate!.year, examDate!.month, examDate!.day);
    return exam.difference(today).inDays;
  }
}

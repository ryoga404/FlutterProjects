import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/question.dart';
import '../platform/image_widget.dart';

// ──────────────────────────────────────────────
// 問題カード（演習・模擬試験共通）
// ──────────────────────────────────────────────
class QuestionCard extends StatelessWidget {
  final Question question;
  final Color? backgroundColor;
  final Color? borderColor;

  const QuestionCard({
    super.key,
    required this.question,
    this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ??
        Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4);
    final border =
        borderColor ?? Theme.of(context).colorScheme.primary.withOpacity(0.2);

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: question.question));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('問題文をコピーしました'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Column(children: [
          if (question.imagePath != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AppImageWidget(
                  path: question.imagePath!, height: 150, fit: BoxFit.contain),
            ),
            const SizedBox(height: 12),
          ],
          // 長押しヒント
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Icon(Icons.copy, size: 11, color: Colors.grey.shade400),
            const SizedBox(width: 2),
            Text('長押しでコピー',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
          ]),
          const SizedBox(height: 4),
          Text(question.question,
              style: const TextStyle(fontSize: 17, height: 1.5),
              textAlign: TextAlign.center),
          if (question.type == QuestionType.multipleChoice) ...[
            const SizedBox(height: 8),
            Text(
              '（正解は${(List<dynamic>.from(question.answer)).length}つ）',
              style: TextStyle(
                  color: Colors.teal.shade700,
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ]),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// タイマーバー（演習画面用）
// ──────────────────────────────────────────────
class TimerBar extends StatelessWidget {
  final int remainingSeconds;
  final int totalSeconds;

  const TimerBar(
      {super.key,
      required this.remainingSeconds,
      required this.totalSeconds});

  double get _progress =>
      totalSeconds > 0 ? remainingSeconds / totalSeconds : 0;

  Color get _color {
    if (_progress > 0.5) return Colors.green;
    if (_progress > 0.25) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      LinearProgressIndicator(
        value: _progress,
        backgroundColor: Colors.grey.shade200,
        valueColor: AlwaysStoppedAnimation<Color>(_color),
        minHeight: 6,
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Icon(Icons.timer, size: 13, color: _color),
          const SizedBox(width: 4),
          Text('$remainingSeconds秒',
              style: TextStyle(
                  fontSize: 12,
                  color: _color,
                  fontWeight: FontWeight.bold)),
        ]),
      ),
    ]);
  }
}

// ──────────────────────────────────────────────
// 丸バツ回答UI
// ──────────────────────────────────────────────
class TrueFalseAnswerWidget extends StatelessWidget {
  final String? selectedValue; // 'true' / 'false' / null
  final ValueChanged<String> onSelected;

  const TrueFalseAnswerWidget({
    super.key,
    required this.selectedValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _btn(context, '○', 'true', Colors.green)),
      const SizedBox(width: 16),
      Expanded(child: _btn(context, '✕', 'false', Colors.red)),
    ]);
  }

  Widget _btn(
      BuildContext ctx, String label, String value, Color color) {
    final selected = selectedValue == value;
    return GestureDetector(
      onTap: () => onSelected(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: selected
              ? color.withOpacity(0.15)
              : color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: selected ? 3 : 1.5),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  fontSize: 40,
                  color: color,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 単一選択回答UI
// ──────────────────────────────────────────────
class SingleChoiceAnswerWidget extends StatelessWidget {
  final List<String> choices;
  final int? selectedIndex;
  final ValueChanged<int> onSelected;
  final Color? selectedColor;

  const SingleChoiceAnswerWidget({
    super.key,
    required this.choices,
    required this.selectedIndex,
    required this.onSelected,
    this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    final primary = selectedColor ?? Theme.of(context).colorScheme.primary;
    final primaryContainer =
        selectedColor?.withOpacity(0.12) ??
            Theme.of(context).colorScheme.primaryContainer;

    return Column(
      children: List.generate(choices.length, (i) {
        final selected = selectedIndex == i;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => onSelected(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: selected ? primaryContainer : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: selected ? primary : Colors.grey.shade300,
                    width: selected ? 2 : 1),
              ),
              child: Row(children: [
                Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected ? primary : Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                    child:
                        Text(choices[i], style: const TextStyle(fontSize: 15))),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

// ──────────────────────────────────────────────
// 複数選択回答UI
// ──────────────────────────────────────────────
class MultipleChoiceAnswerWidget extends StatelessWidget {
  final List<String> choices;
  final Set<int> selectedIndices;
  final ValueChanged<int> onToggle;

  const MultipleChoiceAnswerWidget({
    super.key,
    required this.choices,
    required this.selectedIndices,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(choices.length, (i) {
        final selected = selectedIndices.contains(i);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => onToggle(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: selected ? Colors.teal.shade50 : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: selected ? Colors.teal : Colors.grey.shade300,
                    width: selected ? 2 : 1),
              ),
              child: Row(children: [
                Icon(
                    selected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    color: selected ? Colors.teal : Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                    child:
                        Text(choices[i], style: const TextStyle(fontSize: 15))),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

// ──────────────────────────────────────────────
// 問題タイプバッジ
// ──────────────────────────────────────────────
class QuestionTypeBadge extends StatelessWidget {
  final QuestionType type;
  const QuestionTypeBadge({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final colors = {
      QuestionType.trueFalse: Colors.purple,
      QuestionType.singleChoice: Colors.blue,
      QuestionType.multipleChoice: Colors.teal,
      QuestionType.shortAnswer: Colors.orange,
    };
    final color = colors[type]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4))),
      child: Text(type.label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }
}

// ──────────────────────────────────────────────
// 正誤フラッシュオーバーレイ
// ──────────────────────────────────────────────
class ResultOverlay extends StatelessWidget {
  final bool correct;
  final Animation<double> fadeAnimation;
  final Animation<double> scaleAnimation;

  const ResultOverlay({
    super.key,
    required this.correct,
    required this.fadeAnimation,
    required this.scaleAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final color = correct ? Colors.green : Colors.red;
    final label = correct ? '正解！' : '不正解...';
    final icon =
        correct ? Icons.check_circle_rounded : Icons.cancel_rounded;
    return FadeTransition(
      opacity: fadeAnimation,
      child: ScaleTransition(
        scale: scaleAnimation,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          decoration: BoxDecoration(
            color: color.withOpacity(0.92),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 20,
                  spreadRadius: 2)
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white, size: 36),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2)),
          ]),
        ),
      ),
    );
  }
}

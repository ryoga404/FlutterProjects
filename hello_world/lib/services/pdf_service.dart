import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/answer_history.dart';
import '../models/question.dart';
import '../models/question_set.dart';
import '../platform/app_file_saver.dart';
import '../platform/pdf_image_loader_native.dart'
    if (dart.library.html) '../platform/pdf_image_loader_web.dart' as imgLoader;

class PdfService {
  final _saver = AppFileSaver.instance;

  // ──────────────────────────────────────────────
  // 模擬試験レポート
  // ──────────────────────────────────────────────
  Future<String> generateMockExamReport({
    required String setName,
    required List<Question> questions,
    required List<bool?> answers,
    required int passRatePercent,
    required bool passed,
    String? saveDir,
  }) async {
    final fontData = await rootBundle.load('assets/fonts/NotoSansJP-VF.ttf');
    final ttf = pw.Font.ttf(fontData);
    pw.TextStyle ts({double fontSize = 11, pw.FontWeight weight = pw.FontWeight.normal, PdfColor color = PdfColors.black}) =>
        pw.TextStyle(font: ttf, fontBold: ttf, fontSize: fontSize, fontWeight: weight, color: color);

    final now            = DateTime.now();
    final dateStamp      = '${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}';
    final safeName       = setName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final fileName       = '${safeName}_模擬試験_$dateStamp.pdf';
    final totalPoints    = questions.fold(0, (s, q) => s + q.points);
    final earnedPoints   = questions.asMap().entries.where((e) => answers[e.key] == true).fold(0, (s, e) => s + e.value.points);
    final rate           = totalPoints > 0 ? earnedPoints / totalPoints : 0.0;
    final answeredCount  = answers.where((a) => a != null).length;
    final correctCount   = answers.where((a) => a == true).length;
    final incorrectCount = answers.where((a) => a == false).length;
    final passColor      = passed ? PdfColor.fromHex('#2E7D32') : PdfColor.fromHex('#C62828');
    final headerColor    = passed ? PdfColor.fromHex('#1B5E20') : PdfColor.fromHex('#B71C1C');

    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 36),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Container(width: double.infinity, padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: pw.BoxDecoration(color: headerColor, borderRadius: pw.BorderRadius.circular(10)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('模擬試験レポート', style: ts(fontSize: 22, weight: pw.FontWeight.bold, color: PdfColors.white)),
              pw.SizedBox(height: 4),
              pw.Text(setName, style: ts(fontSize: 14, color: PdfColors.white)),
              pw.SizedBox(height: 2),
              pw.Text('出力日時: ${_fmtDt(now)}', style: ts(fontSize: 10, color: PdfColors.white.flatten())),
            ])),
        pw.SizedBox(height: 24),
        pw.Center(child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 20),
          decoration: pw.BoxDecoration(color: passColor, borderRadius: pw.BorderRadius.circular(12)),
          child: pw.Text(passed ? '合　　格' : '不  合  格',
              style: ts(fontSize: 32, weight: pw.FontWeight.bold, color: PdfColors.white)),
        )),
        pw.SizedBox(height: 24),
        pw.Row(children: [
          _summaryCard('問題数', '${questions.length}', PdfColor.fromHex('#1565C0'), ts), pw.SizedBox(width: 8),
          _summaryCard('回答済み', '$answeredCount', PdfColor.fromHex('#546E7A'), ts), pw.SizedBox(width: 8),
          _summaryCard('正解', '$correctCount', PdfColor.fromHex('#2E7D32'), ts), pw.SizedBox(width: 8),
          _summaryCard('不正解', '$incorrectCount', PdfColor.fromHex('#C62828'), ts),
        ]),
        pw.SizedBox(height: 16),
        pw.Text('得点率グラフ', style: ts(fontSize: 13, weight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        _buildBarChart(correctCount, incorrectCount, answeredCount, rate, ts),
        pw.SizedBox(height: 16),
        pw.Container(padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('合格基準', style: ts(fontSize: 12, color: PdfColors.grey700)),
              pw.Text('$passRatePercent%以上', style: ts(fontSize: 12, weight: pw.FontWeight.bold)),
              pw.SizedBox(width: 20),
              pw.Text('得点率', style: ts(fontSize: 12, color: PdfColors.grey700)),
              pw.Text('${(rate * 100).toStringAsFixed(1)}%', style: ts(fontSize: 12, weight: pw.FontWeight.bold, color: passColor)),
              pw.SizedBox(width: 20),
              pw.Text('判定', style: ts(fontSize: 12, color: PdfColors.grey700)),
              pw.Text(passed ? '合格' : '不合格', style: ts(fontSize: 14, weight: pw.FontWeight.bold, color: passColor)),
            ])),
        pw.SizedBox(height: 16),
        pw.Text('問題別正誤一覧', style: ts(fontSize: 13, weight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        ..._buildMockQuestionList(questions, answers, ts),
      ]),
    ));

    final pdfBytes = await pdf.save();
    return _saver.save(
      bytes: Uint8List.fromList(pdfBytes),
      fileName: fileName,
      directory: saveDir,
    );
  }

  List<pw.Widget> _buildMockQuestionList(
    List<Question> questions, List<bool?> answers,
    pw.TextStyle Function({double fontSize, pw.FontWeight weight, PdfColor color}) ts,
  ) {
    return questions.asMap().entries.map((e) {
      final i = e.key; final q = e.value; final ans = answers[i];
      final correct    = ans == true;
      final unanswered = ans == null;
      final borderColor = unanswered ? PdfColors.grey400 : correct ? PdfColor.fromHex('#43A047') : PdfColor.fromHex('#EF5350');
      final label = unanswered ? '未回答' : correct ? '正解' : '不正解';
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 6),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: borderColor, width: 1.5), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Row(children: [
          pw.SizedBox(width: 24, child: pw.Text('${i + 1}.', style: ts(fontSize: 10, weight: pw.FontWeight.bold, color: PdfColors.grey700))),
          pw.Expanded(child: pw.Text(q.question.length > 60 ? '${q.question.substring(0, 60)}...' : q.question, style: ts(fontSize: 10))),
          pw.SizedBox(width: 8),
          pw.Text('${q.points}点', style: ts(fontSize: 9, color: PdfColors.grey600)),
          pw.SizedBox(width: 8),
          pw.Container(width: 48, padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              decoration: pw.BoxDecoration(color: borderColor, borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Text(label, textAlign: pw.TextAlign.center, style: ts(fontSize: 9, weight: pw.FontWeight.bold, color: PdfColors.white))),
        ]),
      );
    }).toList();
  }

  // ──────────────────────────────────────────────
  // 成績レポート
  // ──────────────────────────────────────────────
  Future<String> generateScoreReport({
    required QuestionSet set,
    required List<AnswerHistory> history,
    required List<Question> questions,
    String? saveDir,
  }) async {
    final fontData = await rootBundle.load('assets/fonts/NotoSansJP-VF.ttf');
    final ttf = pw.Font.ttf(fontData);
    pw.TextStyle ts({double fontSize = 11, pw.FontWeight weight = pw.FontWeight.normal, PdfColor color = PdfColors.black}) =>
        pw.TextStyle(font: ttf, fontBold: ttf, fontSize: fontSize, fontWeight: weight, color: color);

    final now    = DateTime.now();
    final stamp  = '${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}'
        '${now.hour.toString().padLeft(2,'0')}${now.minute.toString().padLeft(2,'0')}';
    final safeName = set.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final fileName = '${safeName}_$stamp.pdf';

    final pdf            = pw.Document();
    final total          = history.length;
    final correctCount   = history.where((h) => h.correct).length;
    final incorrectCount = total - correctCount;
    final rate           = total > 0 ? correctCount / total : 0.0;
    final indigo         = PdfColor.fromHex('#3F51B5');

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 36),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Container(width: double.infinity, padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: pw.BoxDecoration(color: indigo, borderRadius: pw.BorderRadius.circular(10)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('成績レポート', style: ts(fontSize: 22, weight: pw.FontWeight.bold, color: PdfColors.white)),
              pw.SizedBox(height: 4),
              pw.Text(set.name, style: ts(fontSize: 14, color: PdfColors.white)),
              pw.SizedBox(height: 2),
              pw.Text('出力日時: ${_fmtDt(now)}', style: ts(fontSize: 10, color: PdfColor.fromHex('#C5CAE9'))),
            ])),
        pw.SizedBox(height: 20),
        pw.Row(children: [
          _summaryCard('総回答数', '$total', PdfColor.fromHex('#1565C0'), ts), pw.SizedBox(width: 8),
          _summaryCard('正解', '$correctCount', PdfColor.fromHex('#2E7D32'), ts), pw.SizedBox(width: 8),
          _summaryCard('不正解', '$incorrectCount', PdfColor.fromHex('#C62828'), ts), pw.SizedBox(width: 8),
          _summaryCard('正答率', '${(rate * 100).toStringAsFixed(1)}%', _rateColor(rate), ts),
        ]),
        pw.SizedBox(height: 24),
        pw.Text('正答率グラフ', style: ts(fontSize: 14, weight: pw.FontWeight.bold)),
        pw.SizedBox(height: 12),
        _buildBarChart(correctCount, incorrectCount, total, rate, ts),
        pw.SizedBox(height: 24),
        if (questions.isNotEmpty) ...[
          pw.Text('苦手問題 TOP 5（正答率低い順）', style: ts(fontSize: 13, weight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          ..._buildWeakQuestions(history, questions, ts),
        ],
      ]),
    ));

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 36),
      maxPages: 200,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      header: (ctx) => pw.Column(children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('解答履歴  （全 $total 件）', style: ts(fontSize: 13, weight: pw.FontWeight.bold, color: indigo)),
          pw.Text('${ctx.pageNumber} / ${ctx.pagesCount} ページ', style: ts(fontSize: 10, color: PdfColors.grey600)),
        ]),
        pw.SizedBox(height: 4),
        pw.Divider(color: indigo, thickness: 2),
        pw.SizedBox(height: 6),
      ]),
      build: (ctx) {
        final widgets = <pw.Widget>[];
        for (final h in history) {
          final q        = questions.where((q) => q.id == h.questionId).firstOrNull;
          final imgBytes = imgLoader.loadImageBytesSync(q?.imagePath);
          widgets.add(pw.Inseparable(child: _historyCard(h, q, ts, imageBytes: imgBytes)));
        }
        return widgets;
      },
    ));

    final pdfBytes = await pdf.save();
    return _saver.save(bytes: Uint8List.fromList(pdfBytes), fileName: fileName, directory: saveDir);
  }

  // ──────────────────────────────────────────────
  // 解答履歴カード
  // ──────────────────────────────────────────────
  pw.Widget _historyCard(
    AnswerHistory h, Question? q,
    pw.TextStyle Function({double fontSize, pw.FontWeight weight, PdfColor color}) ts, {
    Uint8List? imageBytes,
  }) {
    final correct     = h.correct;
    final borderColor = correct ? PdfColor.fromHex('#43A047') : PdfColor.fromHex('#E53935');
    final bgColor     = correct ? PdfColor.fromHex('#F1F8E9') : PdfColor.fromHex('#FFEBEE');
    final headerLabel = correct ? '[正解]' : '[不正解]';
    final typeLabel   = q?.type.label ?? '-';

    Set<String> userSet = {};
    if (h.userAnswer is List) {
      userSet = Set<String>.from(List<String>.from(h.userAnswer as List));
    } else if (h.userAnswer != null) {
      final s = h.userAnswer.toString();
      if (s.isNotEmpty) userSet = {s};
    }

    Set<String> correctSet = {};
    if (q != null) {
      if (q.answer is List) {
        correctSet = Set<String>.from(List<String>.from(q.answer as List));
      } else {
        final s = q.answer.toString();
        if (s.isNotEmpty) correctSet = {s};
      }
    }

    final hasChoices = q != null &&
        (q.type == QuestionType.singleChoice || q.type == QuestionType.multipleChoice) &&
        q.choices != null && q.choices!.isNotEmpty;

    final choiceWidgets = <pw.Widget>[];
    if (hasChoices) {
      for (final choice in q!.choices!) {
        final isCorrectChoice = correctSet.contains(choice);
        final isUserChoice    = userSet.contains(choice);
        PdfColor rowBg; PdfColor rowBorder; String? badge; PdfColor badgeColor;
        if (isCorrectChoice && isUserChoice) {
          rowBg = PdfColor.fromHex('#E8F5E9'); rowBorder = PdfColor.fromHex('#81C784');
          badge = 'あなたの選択 (正解)'; badgeColor = PdfColor.fromHex('#2E7D32');
        } else if (!isCorrectChoice && isUserChoice) {
          rowBg = PdfColor.fromHex('#FFEBEE'); rowBorder = PdfColor.fromHex('#EF9A9A');
          badge = 'あなたの選択 (不正解)'; badgeColor = PdfColor.fromHex('#C62828');
        } else if (isCorrectChoice && !isUserChoice) {
          rowBg = PdfColor.fromHex('#F1F8E9'); rowBorder = PdfColor.fromHex('#A5D6A7');
          badge = '正解 (未選択)'; badgeColor = PdfColor.fromHex('#388E3C');
        } else {
          rowBg = PdfColors.white; rowBorder = PdfColors.grey300;
          badge = null; badgeColor = PdfColors.grey500;
        }
        choiceWidgets.add(pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 3),
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: pw.BoxDecoration(color: rowBg, border: pw.Border.all(color: rowBorder), borderRadius: pw.BorderRadius.circular(3)),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(child: pw.Text(choice, style: ts(
              fontSize: 9,
              weight: isCorrectChoice ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: isCorrectChoice ? PdfColor.fromHex('#1B5E20') : PdfColors.grey800,
            ))),
            if (badge != null) ...[
              pw.SizedBox(width: 5),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: pw.BoxDecoration(color: badgeColor, borderRadius: pw.BorderRadius.circular(3)),
                child: pw.Text(badge, style: ts(fontSize: 7, weight: pw.FontWeight.bold, color: PdfColors.white)),
              ),
            ],
          ]),
        ));
      }
    }

    String userAnswerDisplay = '';
    String correctAnswerDisplay = '';
    if (!hasChoices) {
      if (h.userAnswer is List) {
        userAnswerDisplay = (h.userAnswer as List).join('、');
      } else {
        final s = h.userAnswer?.toString() ?? '';
        userAnswerDisplay = s == 'true' ? '○（正しい）' : s == 'false' ? '✕（誤り）' : s.isEmpty ? '（未回答）' : s;
      }
      if (q != null) {
        if (q.answer is List) {
          correctAnswerDisplay = (q.answer as List).join('、');
        } else {
          final s = q.answer.toString();
          correctAnswerDisplay = s == 'true' ? '○（正しい）' : s == 'false' ? '✕（誤り）' : s;
        }
      }
    }

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      decoration: pw.BoxDecoration(
          color: bgColor, borderRadius: pw.BorderRadius.circular(7),
          border: pw.Border.all(color: borderColor, width: 1.5)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: pw.BoxDecoration(color: borderColor,
              borderRadius: const pw.BorderRadius.only(
                  topLeft: pw.Radius.circular(5), topRight: pw.Radius.circular(5))),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Row(children: [
              pw.Text(headerLabel, style: ts(fontSize: 11, weight: pw.FontWeight.bold, color: PdfColors.white)),
              pw.SizedBox(width: 8),
              pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(3)),
                  child: pw.Text(typeLabel, style: ts(fontSize: 8, color: borderColor, weight: pw.FontWeight.bold))),
            ]),
            pw.Text(_fmtDt(h.answeredAt), style: ts(fontSize: 8, color: PdfColors.white)),
          ]),
        ),
        pw.Padding(padding: const pw.EdgeInsets.fromLTRB(11, 7, 11, 5),
            child: pw.Text('[問題] ${h.questionText}', style: ts(fontSize: 10, weight: pw.FontWeight.bold))),
        if (imageBytes != null)
          pw.Padding(padding: const pw.EdgeInsets.fromLTRB(11, 0, 11, 5),
              child: pw.ConstrainedBox(constraints: const pw.BoxConstraints(maxHeight: 90),
                  child: pw.Image(pw.MemoryImage(imageBytes), fit: pw.BoxFit.contain))),
        if (hasChoices) ...[
          pw.Padding(padding: const pw.EdgeInsets.fromLTRB(11, 0, 11, 3),
              child: pw.Text('選択肢:', style: ts(fontSize: 8, color: PdfColors.grey700, weight: pw.FontWeight.bold))),
          pw.Padding(padding: const pw.EdgeInsets.fromLTRB(11, 0, 11, 7),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: choiceWidgets)),
        ],
        if (!hasChoices)
          pw.Padding(padding: const pw.EdgeInsets.fromLTRB(11, 0, 11, 5),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('あなたの回答:', style: ts(fontSize: 8, color: PdfColors.grey700)),
                  pw.Text(userAnswerDisplay.isEmpty ? '（未回答）' : userAnswerDisplay,
                      style: ts(fontSize: 10, color: correct ? PdfColor.fromHex('#2E7D32') : PdfColor.fromHex('#C62828'))),
                ])),
                if (!correct && correctAnswerDisplay.isNotEmpty) ...[
                  pw.SizedBox(width: 10),
                  pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('正解:', style: ts(fontSize: 8, color: PdfColors.grey700)),
                    pw.Text(correctAnswerDisplay, style: ts(fontSize: 10, weight: pw.FontWeight.bold, color: PdfColor.fromHex('#2E7D32'))),
                  ])),
                ],
              ])),
        if (q?.explanation != null && q!.explanation!.isNotEmpty)
          pw.Padding(padding: const pw.EdgeInsets.fromLTRB(11, 0, 11, 8),
              child: pw.Container(padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E3F2FD'), borderRadius: pw.BorderRadius.circular(4)),
                  child: pw.Text('解説: ${q.explanation!}', style: ts(fontSize: 9, color: PdfColor.fromHex('#1565C0')))))
        else
          pw.SizedBox(height: 7),
      ]),
    );
  }

  // ──────────────────────────────────────────────
  // 横棒グラフ
  // ──────────────────────────────────────────────
  pw.Widget _buildBarChart(int correctCount, int incorrectCount, int total, double rate,
      pw.TextStyle Function({double fontSize, pw.FontWeight weight, PdfColor color}) ts) {
    const barH      = 36.0;
    final correctFlex   = total > 0 ? (rate * 1000).round() : 0;
    final incorrectFlex = 1000 - correctFlex;
    final correctPct    = total > 0 ? (rate * 100).toStringAsFixed(1) : '0.0';
    final incorrectPct  = total > 0 ? ((1 - rate) * 100).toStringAsFixed(1) : '0.0';
    final colorOk = PdfColor.fromHex('#43A047');
    final colorNg = PdfColor.fromHex('#EF5350');
    final barChildren = <pw.Widget>[];
    if (correctFlex > 0) {
      barChildren.add(pw.Expanded(flex: correctFlex, child: pw.Container(height: barH,
          decoration: pw.BoxDecoration(color: colorOk,
              borderRadius: incorrectFlex == 0 ? pw.BorderRadius.circular(6)
                  : const pw.BorderRadius.only(topLeft: pw.Radius.circular(6), bottomLeft: pw.Radius.circular(6))),
          child: pw.Center(child: pw.Text('$correctPct%',
              style: ts(fontSize: correctFlex > 100 ? 11 : 8, weight: pw.FontWeight.bold, color: PdfColors.white))))));
    }
    if (incorrectFlex > 0) {
      barChildren.add(pw.Expanded(flex: incorrectFlex, child: pw.Container(height: barH,
          decoration: pw.BoxDecoration(color: colorNg,
              borderRadius: correctFlex == 0 ? pw.BorderRadius.circular(6)
                  : const pw.BorderRadius.only(topRight: pw.Radius.circular(6), bottomRight: pw.Radius.circular(6))),
          child: pw.Center(child: pw.Text('$incorrectPct%',
              style: ts(fontSize: incorrectFlex > 100 ? 11 : 8, weight: pw.FontWeight.bold, color: PdfColors.white))))));
    }
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(children: barChildren),
      pw.SizedBox(height: 8),
      pw.Row(children: [
        _legendDot(colorOk), pw.SizedBox(width: 4),
        pw.Text('正解 $correctCount 問 ($correctPct%)', style: ts(fontSize: 11, color: PdfColors.grey800)),
        pw.SizedBox(width: 20),
        _legendDot(colorNg), pw.SizedBox(width: 4),
        pw.Text('不正解 $incorrectCount 問 ($incorrectPct%)', style: ts(fontSize: 11, color: PdfColors.grey800)),
        pw.SizedBox(width: 20),
        pw.Text('合計 $total 問', style: ts(fontSize: 11, color: PdfColors.grey600)),
      ]),
    ]);
  }

  pw.Widget _legendDot(PdfColor color) =>
      pw.Container(width: 12, height: 12,
          decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(3)));

  pw.Widget _summaryCard(String label, String value, PdfColor color,
      pw.TextStyle Function({double fontSize, pw.FontWeight weight, PdfColor color}) ts) {
    return pw.Expanded(child: pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: color, width: 2)),
      child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
        pw.Text(value, textAlign: pw.TextAlign.center, style: ts(fontSize: 24, weight: pw.FontWeight.bold, color: color)),
        pw.SizedBox(height: 4),
        pw.Text(label, textAlign: pw.TextAlign.center, style: ts(fontSize: 10, color: PdfColors.grey700)),
      ]),
    ));
  }

  List<pw.Widget> _buildWeakQuestions(List<AnswerHistory> history, List<Question> questions,
      pw.TextStyle Function({double fontSize, pw.FontWeight weight, PdfColor color}) ts) {
    final stats = <String, Map<String, int>>{};
    for (final q in questions) stats[q.id] = {'total': 0, 'correct': 0};
    for (final h in history) {
      if (stats.containsKey(h.questionId)) {
        stats[h.questionId]!['total'] = stats[h.questionId]!['total']! + 1;
        if (h.correct) stats[h.questionId]!['correct'] = stats[h.questionId]!['correct']! + 1;
      }
    }
    final entries = stats.entries.where((e) => e.value['total']! > 0).toList()
      ..sort((a, b) {
        final ra = a.value['correct']! / a.value['total']!;
        final rb = b.value['correct']! / b.value['total']!;
        return ra.compareTo(rb);
      });
    return entries.take(5).map((e) {
      final q = questions.firstWhere((q) => q.id == e.key,
          orElse: () => Question(id: e.key, setId: '', type: QuestionType.shortAnswer, question: '(削除済み)', answer: ''));
      final t  = e.value['total']!; final c = e.value['correct']!;
      final r  = t > 0 ? c / t : 0.0; final rc = _rateColor(r);
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 7),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: pw.BoxDecoration(color: PdfColors.white,
            border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(q.question.length > 50 ? '${q.question.substring(0, 50)}...' : q.question, style: ts(fontSize: 10))),
          pw.SizedBox(width: 8),
          pw.Text('$c / $t 正解', style: ts(fontSize: 10, color: PdfColors.grey600)),
          pw.SizedBox(width: 8),
          pw.Container(width: 46, padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              decoration: pw.BoxDecoration(color: rc, borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Text('${(r * 100).toStringAsFixed(0)}%', textAlign: pw.TextAlign.center,
                  style: ts(fontSize: 10, weight: pw.FontWeight.bold, color: PdfColors.white))),
        ]),
      );
    }).toList();
  }

  PdfColor _rateColor(double rate) {
    if (rate >= 0.8) return PdfColor.fromHex('#2E7D32');
    if (rate >= 0.5) return PdfColor.fromHex('#E65100');
    return PdfColor.fromHex('#C62828');
  }

  String _fmtDt(DateTime dt) =>
      '${dt.year}/${dt.month.toString().padLeft(2,'0')}/${dt.day.toString().padLeft(2,'0')}'
      ' ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';

  // ──────────────────────────────────────────────
  // 問題集 PDF
  // ──────────────────────────────────────────────
  Future<String> generateQuestionBook({
    required QuestionSet set,
    required List<Question> questions,
    String? saveDir,
    String mode = 'with_answers_and_explanation',
  }) async {
    final fontData = await rootBundle.load('assets/fonts/NotoSansJP-VF.ttf');
    final ttf = pw.Font.ttf(fontData);
    pw.TextStyle ts({double fontSize = 11, pw.FontWeight weight = pw.FontWeight.normal, PdfColor color = PdfColors.black}) =>
        pw.TextStyle(font: ttf, fontBold: ttf, fontSize: fontSize, fontWeight: weight, color: color);

    final now         = DateTime.now();
    final stamp       = '${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}';
    final safeName    = set.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final suffix      = mode == 'questions_only' ? '問題のみ' : mode == 'with_answers' ? '問題と解答' : '問題と解答と解説';
    final fileName    = '${safeName}_問題集_${suffix}_$stamp.pdf';
    final headerColor = PdfColor.fromHex('#1A237E');
    final pdf         = pw.Document();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 36),
      maxPages: 200,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      header: (ctx) => pw.Column(children: [
        pw.Container(width: double.infinity, padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: pw.BoxDecoration(color: headerColor, borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(set.name, style: ts(fontSize: 14, weight: pw.FontWeight.bold, color: PdfColors.white)),
                pw.Text('問題集（$suffix）', style: ts(fontSize: 9, color: PdfColor.fromHex('#9FA8DA'))),
              ]),
              pw.Text('${ctx.pageNumber} / ${ctx.pagesCount} ページ', style: ts(fontSize: 10, color: PdfColors.white)),
            ])),
        pw.SizedBox(height: 10),
      ]),
      build: (ctx) {
        final widgets = <pw.Widget>[];
        for (final entry in questions.asMap().entries) {
          final no = entry.key + 1;
          final q  = entry.value;
          final showAnswer      = mode != 'questions_only';
          final showExplanation = mode == 'with_answers_and_explanation';
          final answerStr = q.answer is List ? (q.answer as List).join('、') : q.answer.toString();
          final tfLabel   = q.answer == 'true' ? '○（正しい）' : '✕（誤り）';
          final card = pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Row(children: [
                pw.Container(width: 26, height: 26,
                    decoration: pw.BoxDecoration(color: headerColor, borderRadius: pw.BorderRadius.circular(4)),
                    child: pw.Center(child: pw.Text('$no', style: ts(fontSize: 11, weight: pw.FontWeight.bold, color: PdfColors.white)))),
                pw.SizedBox(width: 6),
                pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: pw.BoxDecoration(color: PdfColors.grey200, borderRadius: pw.BorderRadius.circular(4)),
                    child: pw.Text(q.type.label, style: ts(fontSize: 9, color: PdfColors.grey700))),
                pw.SizedBox(width: 6),
                pw.Text('${q.points}点', style: ts(fontSize: 9, color: PdfColors.grey600)),
              ]),
              pw.SizedBox(height: 6),
              pw.Text(q.question, style: ts(fontSize: 11)),
              if (q.choices != null && q.choices!.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                ...q.choices!.asMap().entries.map((e) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2, left: 12),
                    child: pw.Text('${String.fromCharCode(65 + e.key)}. ${e.value}', style: ts(fontSize: 10)))),
              ],
              if (showAnswer) ...[
                pw.SizedBox(height: 6),
                pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E8F5E9'),
                        borderRadius: pw.BorderRadius.circular(4),
                        border: pw.Border.all(color: PdfColor.fromHex('#A5D6A7'))),
                    child: pw.Row(children: [
                      pw.Text('解答: ', style: ts(fontSize: 9, weight: pw.FontWeight.bold, color: PdfColor.fromHex('#2E7D32'))),
                      pw.Expanded(child: pw.Text(q.type == QuestionType.trueFalse ? tfLabel : answerStr,
                          style: ts(fontSize: 9, color: PdfColor.fromHex('#1B5E20')))),
                    ])),
              ],
              if (showExplanation && q.explanation != null && q.explanation!.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Container(padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E3F2FD'), borderRadius: pw.BorderRadius.circular(4)),
                    child: pw.Text('解説: ${q.explanation!}', style: ts(fontSize: 9, color: PdfColor.fromHex('#1565C0')))),
              ],
              if (q.memo != null && q.memo!.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text('メモ: ${q.memo!}', style: ts(fontSize: 8, color: PdfColors.grey600)),
              ],
              if (q.tags.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Row(children: [
                  pw.Text('タグ: ', style: ts(fontSize: 8, color: PdfColors.grey600)),
                  pw.Text(q.tags.join('  '), style: ts(fontSize: 8, color: PdfColors.grey600)),
                ]),
              ],
            ]),
          );
          widgets.add(pw.Inseparable(child: card));
        }
        return widgets;
      },
    ));

    final pdfBytes = await pdf.save();
    return _saver.save(bytes: Uint8List.fromList(pdfBytes), fileName: fileName, directory: saveDir);
  }
}

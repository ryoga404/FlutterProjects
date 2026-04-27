import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/question_set.dart';
import '../services/question_service.dart';
import '../platform/app_file_picker.dart';

class ShareService {
  // ──────────────────────────────────────────────
  // JSON 共有（エクスポート）
  // ──────────────────────────────────────────────
  Future<void> shareSetAsJson(BuildContext context, QuestionSet set) async {
    final filePath = await QuestionService().exportSetToJson(set);
    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.share, color: Colors.indigo),
          SizedBox(width: 8),
          Text('問題セットをエクスポート'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kIsWeb
                  ? 'JSONファイルのダウンロードを開始しました。'
                  : 'JSONファイルを書き出しました。\n以下のパスのファイルを相手に送ってください。',
            ),
            if (!kIsWeb) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8)),
                child: SelectableText(
                  filePath,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '受け取った側は「インポート」→「JSONファイル」から読み込めます。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          if (!kIsWeb)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: filePath));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('パスをクリップボードにコピーしました')));
              },
              child: const Text('パスをコピー'),
            ),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // インポートダイアログ（JSON / CSV 選択）
  // ──────────────────────────────────────────────
  Future<void> showImportDialog(
      BuildContext context, VoidCallback onImported) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.file_download, color: Colors.indigo),
          SizedBox(width: 8),
          Text('問題セットをインポート'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('インポート形式を選択してください。'),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: _formatCard(
                  icon: Icons.code,
                  label: 'JSON',
                  description: 'アプリからエクスポートしたJSONファイル',
                  color: Colors.indigo,
                  onTap: () {
                    Navigator.pop(ctx);
                    _importWithPicker(context, onImported, isJson: true);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _formatCard(
                  icon: Icons.table_chart_outlined,
                  label: 'CSV',
                  description: 'スプレッドシートで作成したCSVファイル',
                  color: Colors.teal,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showCsvImportDialog(context, onImported);
                  },
                ),
              ),
            ]),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル')),
        ],
      ),
    );
  }

  Widget _formatCard({
    required IconData icon,
    required String label,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: color, fontSize: 16)),
          const SizedBox(height: 4),
          Text(description,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ]),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // JSON インポート（Web / Native 共通：ファイル選択）
  // ──────────────────────────────────────────────
  Future<void> _importWithPicker(
      BuildContext context, VoidCallback onImported,
      {required bool isJson}) async {
    final picker = AppFilePicker.instance;
    final file   = await picker.pickFile(
      label: isJson ? 'JSON' : 'CSV',
      extensions: isJson ? ['json'] : ['csv'],
    );

    if (!context.mounted) return;

    if (file == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ファイルが選択されませんでした')));
      return;
    }

    final service = QuestionService();
    final result  = isJson
        ? await service.importSetFromJsonBytes(file.bytes)
        : null; // CSV はセット名が必要なので別フロー

    if (!context.mounted) return;
    if (result != null) _showImportResult(context, result, onImported);
  }

  // ──────────────────────────────────────────────
  // CSV インポートダイアログ（セット名入力 → ファイル選択）
  // ──────────────────────────────────────────────
  Future<void> _showCsvImportDialog(
      BuildContext context, VoidCallback onImported) async {
    final nameCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.table_chart_outlined, color: Colors.teal),
          SizedBox(width: 8),
          Text('CSVインポート'),
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '問題セット名 *',
                  hintText: '例: 基本情報技術者 午前問題',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.folder),
                ),
              ),
              const SizedBox(height: 16),
              _csvFormatGuide(),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル')),
          ElevatedButton.icon(
            icon: const Icon(Icons.folder_open),
            label: const Text('ファイルを選択'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('問題セット名を入力してください')));
                return;
              }
              Navigator.pop(ctx);

              final file = await AppFilePicker.instance
                  .pickFile(label: 'CSV', extensions: ['csv']);
              if (!context.mounted) return;
              if (file == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ファイルが選択されませんでした')));
                return;
              }

              final result = await QuestionService()
                  .importSetFromCsvBytes(file.bytes, name);
              if (!context.mounted) return;
              _showImportResult(context, result, onImported);
            },
          ),
        ],
      ),
    );
  }

  Widget _csvFormatGuide() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.info_outline, size: 14, color: Colors.teal.shade700),
            const SizedBox(width: 6),
            Text('CSVフォーマット',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.teal.shade800)),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4)),
            child: const Text(
              'type, question, choice1〜8, answer, explanation, points',
              style: TextStyle(fontSize: 10, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 8),
          _guideRow('type',
              'true_false / single_choice / multiple_choice / short_answer'),
          _guideRow('choice1〜8', '選択肢（丸バツ・記述は空欄でOK）'),
          _guideRow('answer', '正解テキスト（複数選択は | 区切り）'),
          _guideRow('explanation', '解説（任意）'),
          _guideRow('points', '配点（省略時は1）'),
          const SizedBox(height: 6),
          Text(
            '丸バツのanswerは true/false または ○/✕ が使えます',
            style: TextStyle(fontSize: 10, color: Colors.teal.shade700),
          ),
        ],
      ),
    );
  }

  Widget _guideRow(String key, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 80,
          child: Text(key,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace')),
        ),
        Expanded(
            child: Text(desc,
                style:
                    TextStyle(fontSize: 10, color: Colors.grey.shade700))),
      ]),
    );
  }

  // ──────────────────────────────────────────────
  // インポート結果ダイアログ
  // ──────────────────────────────────────────────
  void _showImportResult(
      BuildContext context, ImportResult result, VoidCallback onImported) {
    if (result.success) {
      if (result.warnings != null && result.warnings!.isNotEmpty) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('インポート完了（一部エラー）'),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('「${result.setName}」を${result.questionCount}問インポートしました。'),
                const SizedBox(height: 12),
                Text('スキップされた行:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.orange.shade800)),
                const SizedBox(height: 4),
                ...result.warnings!.take(5).map((w) => Text('• $w',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade700))),
                if (result.warnings!.length > 5)
                  Text('... 他${result.warnings!.length - 5}件',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey)),
              ],
            ),
            actions: [
              ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onImported();
                  },
                  child: const Text('OK')),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '「${result.setName}」を${result.questionCount}問インポートしました'),
          backgroundColor: Colors.green,
        ));
        onImported();
      }
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('インポート失敗'),
          ]),
          content: Text(result.error ?? '不明なエラーが発生しました'),
          actions: [
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('閉じる')),
          ],
        ),
      );
    }
  }
}

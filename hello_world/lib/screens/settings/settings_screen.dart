import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../providers/app_settings_provider.dart';
import '../../services/backup_service.dart';
import '../../services/history_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _backupService  = BackupService();
  final _historyService = HistoryService();
  List<BackupInfo> _backups = [];
  bool _backupLoading = false;
  String _appVersion = '...';

  @override
  void initState() {
    super.initState();
    _loadBackups();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = '${info.version}+${info.buildNumber}');
    } catch (_) {
      if (mounted) setState(() => _appVersion = '—');
    }
  }

  Future<void> _loadBackups() async {
    final list = await _backupService.listBackups();
    if (mounted) setState(() => _backups = list);
  }

  // ──────────────────────────────────────────────
  // バックアップ作成
  // ──────────────────────────────────────────────
  Future<void> _createBackup() async {
    setState(() => _backupLoading = true);
    try {
      final path = await _backupService.createBackup();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(kIsWeb ? 'バックアップをダウンロードしました' : 'バックアップを作成しました\n$path'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ));
      _loadBackups();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('バックアップ失敗: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _backupLoading = false);
    }
  }

  // ──────────────────────────────────────────────
  // リストア（Native: 一覧から選択 / Web & Native: ファイルを選択）
  // ──────────────────────────────────────────────
  Future<void> _restore(BackupInfo info) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.restore, color: Colors.orange), SizedBox(width: 8), Text('リストア確認'),
        ]),
        content: Text('「${info.fileName}」からリストアします。\n現在のデータはすべて上書きされます。\n\nよろしいですか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('リストア'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await _backupService.restoreBackup(info.path);
    if (!mounted) return;
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('リストア完了: ${result.restoredFiles?.join(', ') ?? ''}\n\nアプリを再起動してください。'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
      ));
      _loadBackups();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('リストア失敗: ${result.error}'), backgroundColor: Colors.red));
    }
  }

  // ──────────────────────────────────────────────
  // ファイル選択からリストア（Web / Native 共通）
  // ──────────────────────────────────────────────
  Future<void> _restoreFromPicker() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.restore, color: Colors.orange), SizedBox(width: 8), Text('バックアップから復元'),
        ]),
        content: Text(
          kIsWeb
              ? 'ダウンロードした zip ファイルを選択してください。\n現在のデータはすべて上書きされます。'
              : 'バックアップ zip ファイルを選択してください。\n現在のデータはすべて上書きされます。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('ファイルを選択'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await _backupService.restoreBackupFromPicker();
    if (!mounted) return;
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('リストア完了: ${result.restoredFiles?.join(', ') ?? ''}\n\nアプリを再読み込みしてください。'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('リストア失敗: ${result.error}'), backgroundColor: Colors.red));
    }
  }

  // ──────────────────────────────────────────────
  // バックアップ削除
  // ──────────────────────────────────────────────
  Future<void> _deleteBackup(BackupInfo info) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('バックアップを削除'),
        content: Text('「${info.fileName}」を削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed == true) { await _backupService.deleteBackup(info.path); _loadBackups(); }
  }

  // ──────────────────────────────────────────────
  // 全履歴削除
  // ──────────────────────────────────────────────
  Future<void> _deleteAllHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('全履歴をリセット'),
        content: const Text('すべての解答履歴を削除しますか？\n問題は残ります。この操作は元に戻せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('全削除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _historyService.deleteAllHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('全解答履歴を削除しました')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        title: const Text('設定'),
      ),
      body: ListView(children: [
        // ─── 外観 ───
        _sectionHeader('外観'),
        ListTile(
          leading: Icon(settings.isDark ? Icons.dark_mode : Icons.light_mode),
          title: const Text('テーマ'),
          trailing: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 16), label: Text('ライト')),
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.auto_mode,  size: 16), label: Text('自動')),
              ButtonSegment(value: ThemeMode.dark,   icon: Icon(Icons.dark_mode,  size: 16), label: Text('ダーク')),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (s) => settings.setThemeMode(s.first),
            style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.text_fields),
          title: const Text('文字サイズ'),
          subtitle: Text(settings.fontScaleLabel),
          trailing: SegmentedButton<double>(
            segments: const [
              ButtonSegment(value: 0.85, label: Text('小')),
              ButtonSegment(value: 1.0,  label: Text('標準')),
              ButtonSegment(value: 1.15, label: Text('大')),
            ],
            selected: {settings.fontScale},
            onSelectionChanged: (s) => settings.setFontScale(s.first),
            style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ),
        ),
        const Divider(),

        // ─── データ管理 ───
        _sectionHeader('データ管理'),
        ListTile(
          leading: const Icon(Icons.backup, color: Colors.indigo),
          title: const Text('バックアップを作成'),
          subtitle: Text(kIsWeb ? '全データを zip でダウンロード' : '全データを zip ファイルに保存'),
          trailing: _backupLoading
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.chevron_right),
          onTap: _backupLoading ? null : _createBackup,
        ),

        // ファイルを選択してリストア（Web / Native 共通）
        ListTile(
          leading: const Icon(Icons.restore, color: Colors.orange),
          title: const Text('バックアップから復元'),
          subtitle: Text(kIsWeb ? 'ダウンロードした zip を選択して復元' : 'zip ファイルを選択して復元'),
          onTap: _restoreFromPicker,
        ),

        // Native のみ：バックアップ一覧
        if (!kIsWeb && _backups.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('バックアップ履歴（${_backups.length}件）',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
          ),
          ..._backups.map((info) => _backupTile(info)),
        ],
        const Divider(),

        ListTile(
          leading: const Icon(Icons.delete_sweep, color: Colors.red),
          title: const Text('全解答履歴をリセット', style: TextStyle(color: Colors.red)),
          subtitle: const Text('問題データは残ります'),
          onTap: _deleteAllHistory,
        ),
        const Divider(),

        // ─── アプリ情報 ───
        _sectionHeader('アプリ情報'),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('バージョン'),
          trailing: Text(_appVersion, style: const TextStyle(color: Colors.grey)),
        ),
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary, letterSpacing: 0.5)),
    );
  }

  Widget _backupTile(BackupInfo info) {
    final dt    = info.createdAt;
    final label = '${dt.year}/${dt.month.toString().padLeft(2,'0')}/${dt.day.toString().padLeft(2,'0')} '
        '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 0),
      leading: const Icon(Icons.folder_zip_outlined, color: Colors.indigo, size: 20),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      subtitle: Text(info.sizeLabel, style: const TextStyle(fontSize: 11)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        TextButton(onPressed: () => _restore(info), child: const Text('リストア', style: TextStyle(fontSize: 12))),
        IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            onPressed: () => _deleteBackup(info), tooltip: '削除'),
      ]),
    );
  }
}

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/session.dart';
import '../services/session_service.dart';
import '../services/scanner_service.dart';
import '../services/pdf_service.dart';
import '../services/export_service.dart';
import '../utils/dialogs.dart';
import 'pdf_preview_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Session _session = Session();
  bool _loading = true;
  bool _busy = false;
  late TextEditingController _caseCtrl;
  Timer? _caseDebounce;

  // 🔐 Mật khẩu cho phiên làm việc — chỉ ở RAM, tắt app là mất
  String? _sessionPassword;

  @override
  void initState() {
    super.initState();
    _caseCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _caseDebounce?.cancel();
    _caseCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await SessionService.load();
    setState(() {
      _session = s;
      _caseCtrl.text = s.caseName;
      _loading = false;
    });
  }

  Future<void> _save() => SessionService.save(_session);

  // ---------- TÊN HỒ SƠ (AUTO-SAVE 800ms) ----------
  void _onCaseNameChanged(String v) {
    _caseDebounce?.cancel();
    _caseDebounce = Timer(const Duration(milliseconds: 800), () async {
      final old = _session.caseName;
      final newName = v.trim();
      if (old == newName) return;

      try {
        if (old.isNotEmpty && newName.isNotEmpty) {
          await SessionService.renameFolder(old, newName);
        }
      } catch (e) {
        if (mounted) toast(context, 'Không đổi được tên: $e');
      }
      _session.caseName = newName;
      await _save();
      if (mounted) setState(() {});
    });
  }

  // ---------- MẬT KHẨU PHIÊN ----------
  Future<void> _openPasswordDialog() async {
    final result = await askPassword(context, current: _sessionPassword);
    if (result == null) return; // Huỷ
    setState(() {
      _sessionPassword = result.isEmpty ? null : result;
    });
    if (!mounted) return;
    toast(
      context,
      _sessionPassword == null
          ? 'Đã bỏ mật khẩu'
          : 'Đã đặt mật khẩu cho phiên làm việc',
    );
  }

  // ---------- CLEAR ----------
  Future<void> _clearAll() async {
    final ok = await confirm(context,
        title: 'Xoá toàn bộ?',
        message: 'Tất cả người, thủ tục, file sẽ bị xoá. Không thể hoàn tác.');
    if (!ok) return;
    await SessionService.clearAll();
    _caseDebounce?.cancel();
    setState(() {
      _session = Session();
      _caseCtrl.clear();
    });
  }

  // ---------- NGƯỜI ----------
  Future<void> _addPerson() async {
    if (_session.caseName.isEmpty) {
      toast(context, 'Nhập tên hồ sơ trước (ô trên cùng)');
      return;
    }
    final name = await askText(context,
        title: 'Thêm người', hint: 'vd: NguyenVanA, TranThiB');
    if (name == null || name.trim().isEmpty) return;
    final n = name.trim();
    if (_session.persons.any((p) => p.name == n)) {
      toast(context, 'Đã có "$n"');
      return;
    }
    setState(() => _session.persons.add(PersonEntry(name: n)));
    await _save();
  }

  Future<void> _renamePerson(PersonEntry p) async {
    final old = p.name;
    final name = await askText(context,
        title: 'Đổi tên người', hint: 'Tên mới', initial: old);
    if (name == null || name.trim().isEmpty || name.trim() == old) return;
    final n = name.trim();
    if (_session.persons.any((x) => x.name == n)) {
      toast(context, 'Đã có "$n"');
      return;
    }
    try {
      await SessionService.renameFolder(
        '${_session.caseName}/$old',
        '${_session.caseName}/$n',
      );
    } catch (e) {
      if (mounted) toast(context, 'Lỗi đổi tên: $e');
    }
    setState(() => p.name = n);
    await _save();
  }

  Future<void> _deletePerson(PersonEntry p) async {
    final ok = await confirm(context,
        title: 'Xoá "${p.name}"?',
        message: 'Toàn bộ thủ tục và file của người này sẽ bị xoá.');
    if (!ok) return;
    await SessionService.deletePersonDir(_session.caseName, p.name);
    setState(() => _session.persons.remove(p));
    await _save();
  }

  // ---------- THỦ TỤC ----------
  Future<void> _addProcedure(PersonEntry p) async {
    final name = await askText(context,
        title: 'Thêm thủ tục cho ${p.name}',
        hint: 'vd: KhaiSinh, CMND, HoKhau, GiayKetHon');
    if (name == null || name.trim().isEmpty) return;
    final n = name.trim();
    if (p.procedures.any((x) => x.name == n)) {
      toast(context, 'Đã có "$n"');
      return;
    }
    setState(() => p.procedures.add(ProcedureEntry(name: n)));
    await _save();
  }

  Future<void> _renameProcedure(PersonEntry p, ProcedureEntry pr) async {
    final old = pr.name;
    final name = await askText(context,
        title: 'Đổi tên thủ tục', hint: 'Tên mới', initial: old);
    if (name == null || name.trim().isEmpty || name.trim() == old) return;
    final n = name.trim();
    if (p.procedures.any((x) => x.name == n)) {
      toast(context, 'Đã có "$n"');
      return;
    }
    try {
      await SessionService.renameFolder(
        '${_session.caseName}/${p.name}/$old',
        '${_session.caseName}/${p.name}/$n',
      );
    } catch (e) {
      if (mounted) toast(context, 'Lỗi đổi tên: $e');
    }
    setState(() => pr.name = n);
    await _save();
  }

  Future<void> _deleteProcedure(PersonEntry p, ProcedureEntry pr) async {
    final ok = await confirm(context,
        title: 'Xoá "${pr.name}"?',
        message: 'Toàn bộ file trong đây sẽ bị xoá.');
    if (!ok) return;
    await SessionService.deleteProcedureDir(
        _session.caseName, p.name, pr.name);
    setState(() => p.procedures.remove(pr));
    await _save();
  }

  // ---------- QUÉT ----------
  Future<void> _scan(PersonEntry p, ProcedureEntry pr) async {
    if (_busy) return;
    if (_session.caseName.isEmpty) {
      toast(context, 'Nhập tên hồ sơ trước');
      return;
    }

    List<String>? images;
    try {
      images = await ScannerService.scan();
      if (images == null || images.isEmpty) return;

      final defaultName = '${pr.name}_${pr.pdfs.length + 1}';
      final opts = await askScanOptions(context, defaultName: defaultName);
      if (opts == null) {
        _cleanup(images);
        return;
      }
      final finalName =
          opts.name.trim().isEmpty ? defaultName : opts.name.trim();

      setState(() => _busy = true);

      final dir = await SessionService.ensureProcedureDir(
          _session.caseName, p.name, pr.name);

      final safe = _sanitize(finalName);
      var finalPath = '${dir.path}/$safe.pdf';
      int i = 2;
      while (await File(finalPath).exists()) {
        finalPath = '${dir.path}/${safe}_$i.pdf';
        i++;
      }

      await PdfService.createPdf(
        imagePaths: images,
        outputPath: finalPath,
        mode: opts.mode,
      );
      _cleanup(images);

      final fileName = finalPath.split('/').last;
      setState(() => pr.pdfs.add(fileName));
      await _save();

      if (!mounted) return;
      toast(context, 'Đã lưu: $fileName');

      // Mở xem trước ngay
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PdfPreviewScreen(file: File(finalPath), title: fileName),
        ),
      );
    } catch (e) {
      if (images != null) _cleanup(images);
      if (mounted) toast(context, 'Lỗi quét: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cleanup(List<String> paths) {
    for (final p in paths) {
      try {
        File(p).deleteSync();
      } catch (_) {}
    }
  }

  String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  Future<void> _deleteFile(
      PersonEntry p, ProcedureEntry pr, String fileName) async {
    final ok =
        await confirm(context, title: 'Xoá file này?', message: fileName);
    if (!ok) return;
    await SessionService.deleteFile(
        _session.caseName, p.name, pr.name, fileName);
    setState(() => pr.pdfs.remove(fileName));
    await _save();
  }

  Future<void> _openFile(
      PersonEntry p, ProcedureEntry pr, String fileName) async {
    final f = await SessionService.resolvePdf(
        _session.caseName, p.name, pr.name, fileName);
    if (!await f.exists()) {
      toast(context, 'File không tồn tại');
      return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(file: f, title: fileName),
      ),
    );
  }

  // ---------- SHARE ----------
  Future<void> _share() async {
    if (_session.totalFiles == 0) return;
    if (_session.caseName.isEmpty) {
      toast(context, 'Nhập tên hồ sơ trước');
      return;
    }

    setState(() => _busy = true);
    try {
      await ExportService.shareCase(
        _session.caseName,
        password: _sessionPassword,
      );
      if (!mounted) return;

      // Không check ShareResultStatus — tránh lỗi version share_plus
      final clear = await confirm(
        context,
        title: 'Đã gửi xong!',
        message: 'Xoá hồ sơ hiện tại để làm hồ sơ mới?\n'
            '(Nếu muốn gửi lại, chọn "Huỷ".)',
        yesLabel: 'Xoá & làm mới',
      );
      if (clear) {
        await SessionService.clearAll();
        _caseDebounce?.cancel();
        setState(() {
          _session = Session();
          _caseCtrl.clear();
        });
      }
    } catch (e) {
      if (mounted) toast(context, 'Lỗi gửi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- BUILD ----------
  @override
  Widget build(BuildContext context) {
    final canShare =
        _session.totalFiles > 0 && _session.caseName.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quét & Gửi hồ sơ'),
        actions: [
          IconButton(
            icon: Icon(
              _sessionPassword == null ? Icons.lock_open : Icons.lock,
              color:
                  _sessionPassword == null ? null : Colors.amber.shade700,
            ),
            tooltip: _sessionPassword == null
                ? 'Đặt mật khẩu cho file ZIP'
                : 'Đã bật mật khẩu — nhấn để đổi/bỏ',
            onPressed: _openPasswordDialog,
          ),
          if (_session.totalFiles > 0 || _session.persons.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Xoá tất cả',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: TextField(
                        controller: _caseCtrl,
                        onChanged: _onCaseNameChanged,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: '1. Tên hồ sơ',
                          hintText: 'vd: VuAn_2026, MuaBanDat_001',
                          helperText: 'Tự động lưu — không cần Enter',
                          prefixIcon: const Icon(Icons.folder_special),
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),

                    Expanded(
                      child: _session.persons.isEmpty
                          ? _emptyState()
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 8, 12, 12),
                              itemCount: _session.persons.length,
                              itemBuilder: (_, i) => _personCard(
                                _session.persons[i],
                                index: i + 2,
                              ),
                            ),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _addPerson,
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Thêm người vào hồ sơ'),
                          style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),

                    _bottomBar(canShare),
                  ],
                ),
                if (_busy)
                  const ColoredBox(
                    color: Color(0x88000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _session.caseName.isEmpty
                  ? 'Nhập tên hồ sơ ở ô trên,\nrồi thêm người vào hồ sơ.'
                  : 'Hồ sơ "${_session.caseName}" chưa có ai.\nNhấn nút bên dưới để thêm người đầu tiên.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(bool canShare) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${_session.persons.length} người · '
                  '${_session.totalProcedures} thủ tục · '
                  '${_session.totalFiles} file PDF',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
              if (_sessionPassword != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock,
                          size: 12, color: Colors.amber.shade900),
                      const SizedBox(width: 3),
                      Text('Có mật khẩu',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canShare && !_busy ? _share : null,
              icon: const Icon(Icons.ios_share),
              label: const Text('Gửi qua Zalo / Gmail / Drive'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _personCard(PersonEntry p, {required int index}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      elevation: 1.5,
      child: Column(
        children: [
          Container(
            color: Theme.of(context).colorScheme.primaryContainer,
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text('$index',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    p.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Đổi tên',
                  onPressed: () => _renamePerson(p),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Xoá',
                  onPressed: () => _deletePerson(p),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                ...p.procedures
                    .map((pr) => _procedureBlock(p, pr))
                    .toList(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _addProcedure(p),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Thêm thủ tục'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _procedureBlock(PersonEntry p, ProcedureEntry pr) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            child: Row(
              children: [
                const Icon(Icons.folder, size: 20, color: Colors.amber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    pr.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Đổi tên',
                  onPressed: () => _renameProcedure(p, pr),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Xoá',
                  onPressed: () => _deleteProcedure(p, pr),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _scan(p, pr),
                icon: const Icon(Icons.document_scanner, size: 20),
                label: const Text('📷 Quét thủ tục này'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  backgroundColor: Colors.blue.withValues(alpha: 0.12),
                  foregroundColor: Colors.blue.shade800,
                ),
              ),
            ),
          ),
          if (pr.pdfs.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Chưa có file — nhấn "Quét" ở trên',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            )
          else
            ...pr.pdfs.map((fileName) => ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.picture_as_pdf,
                      color: Colors.red, size: 22),
                  title: Text(fileName,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: const Text('Chạm để xem',
                      style: TextStyle(fontSize: 11)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Xoá file',
                    onPressed: () => _deleteFile(p, pr, fileName),
                  ),
                  onTap: () => _openFile(p, pr, fileName),
                )),
        ],
      ),
    );
  }
}
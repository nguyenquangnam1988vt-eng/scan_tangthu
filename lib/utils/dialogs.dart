import 'package:flutter/material.dart';
import '../models/session.dart';
import 'suggestions.dart';

/// Hỏi nhập text. Trả về null nếu huỷ.
Future<String?> askText(
  BuildContext ctx, {
  required String title,
  required String hint,
  String? initial,
  String okLabel = 'Lưu',
}) async {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: ctx,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(okLabel)),
      ],
    ),
  );
}

/// Xác nhận Yes/No.
Future<bool> confirm(
  BuildContext ctx, {
  required String title,
  required String message,
  String yesLabel = 'OK',
}) async {
  final r = await showDialog<bool>(
    context: ctx,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Huỷ')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: Text(yesLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Dialog chọn tên thủ tục: gõ vào ô tìm kiếm → gợi ý hiện ra → chạm để chọn.
Future<String?> askProcedureName(BuildContext ctx) async {
  final nameCtrl = TextEditingController();
  final searchCtrl = TextEditingController();
  List<String> filtered = ProcedureSuggestions.all;

  return showDialog<String>(
    context: ctx,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (_, setLocal) => AlertDialog(
        title: const Text('Chọn tên thủ tục'),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        content: SizedBox(
          width: double.maxFinite,
          height: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Ô tên cuối cùng
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Tên thủ tục',
                  hintText: 'Gõ tên hoặc chọn bên dưới',
                  prefixIcon: Icon(Icons.drive_file_rename_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),

              // Ô tìm kiếm
              TextField(
                controller: searchCtrl,
                autofocus: true,
                onChanged: (v) => setLocal(() {
                  filtered = ProcedureSuggestions.search(v);
                }),
                decoration: InputDecoration(
                  hintText: 'Tìm gợi ý (gõ không dấu cũng được)',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            searchCtrl.clear();
                            setLocal(() {
                              filtered = ProcedureSuggestions.all;
                            });
                          },
                        ),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),

              // Danh sách gợi ý
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text('Không có gợi ý — hãy gõ tay ở ô trên'),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final s = filtered[i];
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: const Icon(Icons.description_outlined,
                                size: 18),
                            title: Text(s,
                                style: const TextStyle(fontSize: 13)),
                            onTap: () {
                              nameCtrl.text = s;
                              nameCtrl.selection =
                                  TextSelection.fromPosition(
                                TextPosition(offset: s.length),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(dialogCtx, name);
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    ),
  );
}

/// Dialog chọn chế độ quét + đặt tên file.
Future<({String name, ScanMode mode})?> askScanOptions(
  BuildContext ctx, {
  required String defaultName,
}) async {
  final ctrl = TextEditingController(text: defaultName);
  ScanMode mode = ScanMode.grayscale;

  return showDialog<({String name, ScanMode mode})>(
    context: ctx,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (_, setLocal) => AlertDialog(
        title: const Text('Lưu file PDF'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Tên file',
                  hintText: 'vd: CMND_mat_truoc',
                ),
              ),
              const SizedBox(height: 18),
              const Text('Chế độ quét:',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              _modeRadio(
                label: 'Màu gốc',
                sub: 'Giữ màu — sổ đỏ, hóa đơn',
                icon: Icons.palette_outlined,
                value: ScanMode.color,
                groupValue: mode,
                onChanged: (v) => setLocal(() => mode = v),
              ),
              _modeRadio(
                label: 'Xám (khuyên dùng)',
                sub: 'Nhẹ hơn 40%, chữ rõ',
                icon: Icons.gradient_outlined,
                value: ScanMode.grayscale,
                groupValue: mode,
                onChanged: (v) => setLocal(() => mode = v),
              ),
              _modeRadio(
                label: 'Đen trắng',
                sub: 'Nhẹ nhất, tài liệu in',
                icon: Icons.contrast,
                value: ScanMode.bw,
                groupValue: mode,
                onChanged: (v) => setLocal(() => mode = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Huỷ')),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogCtx,
              (name: ctrl.text.trim(), mode: mode),
            ),
            child: const Text('Tạo PDF'),
          ),
        ],
      ),
    ),
  );
}

Widget _modeRadio({
  required String label,
  required String sub,
  required IconData icon,
  required ScanMode value,
  required ScanMode groupValue,
  required ValueChanged<ScanMode> onChanged,
}) {
  final selected = value == groupValue;
  return InkWell(
    onTap: () => onChanged(value),
    borderRadius: BorderRadius.circular(8),
    child: Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: selected
            ? Colors.blue.withValues(alpha: 0.10)
            : Colors.transparent,
        border: Border.all(
          color: selected ? Colors.blue : Colors.grey.shade300,
          width: selected ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 20,
              color: selected ? Colors.blue : Colors.grey.shade600),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                Text(sub,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Radio<ScanMode>(
            value: value,
            groupValue: groupValue,
            onChanged: (v) => onChanged(v ?? value),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    ),
  );
}

/// Dialog đặt/đổi/bỏ mật khẩu phiên làm việc.
Future<String?> askPassword(
  BuildContext ctx, {
  String? current,
}) async {
  final has = current != null && current.isNotEmpty;
  final pwdCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  String? error;

  return showDialog<String>(
    context: ctx,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (_, setLocal) => AlertDialog(
        title: Text(has ? 'Đổi / Bỏ mật khẩu' : 'Đặt mật khẩu cho file ZIP'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                has
                    ? 'File ZIP gửi đi sẽ được bảo vệ bằng mật khẩu mới. Để trống rồi bấm "Bỏ mật khẩu" để tắt.'
                    : 'Từ giờ, mọi file ZIP gửi đi sẽ được mã hóa AES-256 bằng mật khẩu này. Mật khẩu chỉ lưu trong phiên làm việc — tắt app là mất.',
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: pwdCtrl,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Mật khẩu',
                  hintText: 'Tối thiểu 4 ký tự',
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
                onChanged: (_) {
                  if (error != null) setLocal(() => error = null);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nhập lại mật khẩu',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 18, color: Colors.orange.shade800),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Người nhận cần dùng WinRAR / 7-Zip / ZArchiver để mở file có mật khẩu.',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (has)
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, ''),
              child: const Text('Bỏ mật khẩu',
                  style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () {
              final pwd = pwdCtrl.text;
              if (pwd.isEmpty) {
                Navigator.pop(dialogCtx, '');
                return;
              }
              if (pwd.length < 4) {
                setLocal(() => error = 'Cần ít nhất 4 ký tự');
                return;
              }
              if (pwd != confirmCtrl.text) {
                setLocal(() => error = 'Mật khẩu nhập lại không khớp');
                return;
              }
              Navigator.pop(dialogCtx, pwd);
            },
            child: Text(has ? 'Cập nhật' : 'Đặt mật khẩu'),
          ),
        ],
      ),
    ),
  );
}

void toast(BuildContext ctx, String msg) {
  ScaffoldMessenger.of(ctx)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
}

String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

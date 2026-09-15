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

/// Dialog chọn tên thủ tục (thư mục) — giữ đơn giản, chỉ gõ tay.
Future<String?> askProcedureName(BuildContext ctx) async {
  return askText(
    ctx,
    title: 'Tên thủ tục (thư mục)',
    hint: 'vd: KhaiSinh, CMND, HoKhau, ToKhaiCT01',
    okLabel: 'Tạo thủ tục',
  );
}

/// ⭐ Dialog đặt tên file PDF sau khi scan.
/// Có gợi ý: gõ từ khoá → hiện danh sách tài liệu → chọn.
/// Vẫn có thể gõ tay tự do.
Future<({String name, ScanMode mode})?> askScanOptions(
  BuildContext ctx, {
  required String defaultName,
}) async {
  final nameCtrl = TextEditingController(text: defaultName);
  final searchCtrl = TextEditingController();
  List<String> filtered = ProcedureSuggestions.all;
  ScanMode mode = ScanMode.grayscale;

  return showDialog<({String name, ScanMode mode})>(
    context: ctx,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (_, setLocal) => AlertDialog(
        title: const Text('Lưu file PDF'),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        content: SizedBox(
          width: double.maxFinite,
          height: 620,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- Ô tên file ----
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Tên file',
                  hintText: 'Gõ hoặc chọn gợi ý bên dưới',
                  prefixIcon: Icon(Icons.picture_as_pdf),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),

              // ---- Ô tìm kiếm gợi ý ----
              TextField(
                controller: searchCtrl,
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

              // ---- Danh sách gợi ý ----
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'Không có gợi ý — hãy gõ tay ở ô trên',
                          style: TextStyle(fontSize: 12),
                        ),
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

              const Divider(height: 1),
              const SizedBox(height: 8),

              // ---- Chọn chế độ quét ----
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Chế độ quét:',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _modeChip(
                      label: 'Màu',
                      icon: Icons.palette_outlined,
                      value: ScanMode.color,
                      groupValue: mode,
                      onChanged: (v) => setLocal(() => mode = v),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _modeChip(
                      label: 'Xám',
                      icon: Icons.gradient_outlined,
                      value: ScanMode.grayscale,
                      groupValue: mode,
                      onChanged: (v) => setLocal(() => mode = v),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _modeChip(
                      label: 'Đen trắng',
                      icon: Icons.contrast,
                      value: ScanMode.bw,
                      groupValue: mode,
                      onChanged: (v) => setLocal(() => mode = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Huỷ')),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(
                dialogCtx,
                (name: name, mode: mode),
              );
            },
            child: const Text('Tạo PDF'),
          ),
        ],
      ),
    ),
  );
}

/// Chip chọn chế độ quét — gọn hơn Radio.
Widget _modeChip({
  required String label,
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
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: selected
            ? Colors.blue.withValues(alpha: 0.15)
            : Colors.grey.shade100,
        border: Border.all(
          color: selected ? Colors.blue : Colors.grey.shade300,
          width: selected ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 20,
              color: selected ? Colors.blue.shade800 : Colors.grey.shade600),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.blue.shade800 : Colors.grey.shade700,
            ),
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

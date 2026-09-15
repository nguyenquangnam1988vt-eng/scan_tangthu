/// Dialog chọn tên thủ tục: vừa chọn từ gợi ý, vừa gõ tay được.
/// Trả về tên đã chọn hoặc null nếu huỷ.
Future<String?> askProcedureName(
  BuildContext ctx, {
  required Map<String, List<String>> groups,
}) async {
  final ctrl = TextEditingController();
  final searchCtrl = TextEditingController();
  String? selectedGroup = groups.keys.first;
  String filter = '';

  return showDialog<String>(
    context: ctx,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (_, setLocal) {
        // Lọc theo search
        final filtered = filter.isEmpty
            ? groups
            : {
                for (final e in groups.entries)
                  e.key: e.value
                      .where((s) =>
                          s.toLowerCase().contains(filter.toLowerCase()))
                      .toList()
              };

        // Bỏ nhóm rỗng sau khi lọc
        filtered.removeWhere((_, v) => v.isEmpty);

        // Nếu nhóm đang chọn bị xoá sau khi lọc → chọn nhóm đầu
        if (filtered.isNotEmpty &&
            !filtered.containsKey(selectedGroup)) {
          selectedGroup = filtered.keys.first;
        }

        return AlertDialog(
          title: const Text('Chọn tên thủ tục'),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          content: SizedBox(
            width: double.maxFinite,
            height: 480,
            child: Column(
              children: [
                // Ô gõ tự do
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Tên thủ tục',
                    hintText: 'Gõ hoặc chọn bên dưới',
                    prefixIcon: Icon(Icons.drive_file_rename_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),

                // Ô tìm kiếm
                TextField(
                  controller: searchCtrl,
                  onChanged: (v) => setLocal(() => filter = v),
                  decoration: const InputDecoration(
                    hintText: 'Tìm gợi ý...',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),

                // 2 cột: nhóm | gợi ý
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text('Không tìm thấy — hãy gõ tay ở ô trên'),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Cột nhóm
                            SizedBox(
                              width: 130,
                              child: ListView(
                                children: filtered.keys
                                    .map((g) => InkWell(
                                          onTap: () => setLocal(
                                              () => selectedGroup = g),
                                          child: Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 10),
                                            decoration: BoxDecoration(
                                              color: selectedGroup == g
                                                  ? Colors.blue
                                                      .withValues(alpha: 0.15)
                                                  : null,
                                              border: Border(
                                                left: BorderSide(
                                                  color: selectedGroup == g
                                                      ? Colors.blue
                                                      : Colors.transparent,
                                                  width: 3,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              g,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight:
                                                    selectedGroup == g
                                                        ? FontWeight.w700
                                                        : FontWeight.w500,
                                                color: selectedGroup == g
                                                    ? Colors.blue.shade800
                                                    : null,
                                              ),
                                            ),
                                          ),
                                        ))
                                    .toList(),
                              ),
                            ),
                            const VerticalDivider(width: 1),

                            // Cột gợi ý
                            Expanded(
                              child: ListView(
                                children: (filtered[selectedGroup] ?? [])
                                    .map((s) => ListTile(
                                          dense: true,
                                          visualDensity:
                                              VisualDensity.compact,
                                          title: Text(s,
                                              style: const TextStyle(
                                                  fontSize: 13)),
                                          onTap: () {
                                            ctrl.text = s;
                                            ctrl.selection =
                                                TextSelection.fromPosition(
                                              TextPosition(
                                                  offset: s.length),
                                            );
                                          },
                                        ))
                                    .toList(),
                              ),
                            ),
                          ],
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
                final name = ctrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(dialogCtx, name);
              },
              child: const Text('Thêm'),
            ),
          ],
        );
      },
    ),
  );
}

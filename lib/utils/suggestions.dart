/// Danh sách gợi ý tên thủ tục, chia theo nhóm.
class ProcedureSuggestions {
  static const Map<String, List<String>> groups = {
    '👤 Nhân thân': [
      'Giấy khai sinh',
      'Giấy khai tử',
      'CMND',
      'CMND mặt trước',
      'CMND mặt sau',
      'Căn cước công dân',
      'CCCD mặt trước',
      'CCCD mặt sau',
      'Hộ chiếu',
      'Sổ hộ khẩu',
      'Sổ tạm trú',
      'Giấy xác nhận thông tin cư trú',
      'Giấy xác nhận cư trú',
      'Giấy đăng ký tạm trú',
      'Giấy đăng ký tạm vắng',
      'Giấy xác nhận độc thân',
      'Giấy xác nhận tình trạng hôn nhân',
      'Lý lịch tư pháp',
      'Giấy khám sức khoẻ',
    ],
    '💑 Hôn nhân - Gia đình': [
      'Giấy đăng ký kết hôn',
      'Quyết định ly hôn',
      'Bản án ly hôn',
      'Giấy khai sinh con',
      'Giấy xác nhận quan hệ gia đình',
    ],
    '🏛️ Hành chính - Hồ sơ': [
      'Tờ khai CT01',
      'Tờ khai CT02',
      'Tờ khai đăng ký thường trú',
      'Tờ khai đăng ký tạm trú',
      'Tờ khai đăng ký',
      'Báo cáo đề xuất',
      'Báo cáo đề xuất giải quyết',
      'Báo cáo thẩm tra',
      'Biên bản xác minh',
      'Biên bản làm việc',
      'Biên bản kiểm tra',
      'Biên bản ghi lời khai',
      'Biên bản họp',
      'Thống kê tài liệu trong hồ sơ',
      'Danh mục tài liệu',
      'Mục lục hồ sơ',
      'Bìa hồ sơ',
      'Đơn đề nghị',
      'Đơn xin',
      'Giấy xác nhận của Công an',
      'Giấy xác nhận của UBND',
    ],
    '✍️ Uỷ quyền - Thừa kế': [
      'Giấy uỷ quyền',
      'Hợp đồng uỷ quyền',
      'Văn bản uỷ quyền',
      'Di chúc',
      'Biên bản họp gia đình',
      'Văn bản thoả thuận phân chia di sản',
      'Văn bản khai nhận di sản',
    ],
  };

  /// Danh sách phẳng tất cả tên — dùng cho tìm kiếm.
  static List<String> get all =>
      groups.values.expand((e) => e).toList();
}

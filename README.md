# ViKey
[![GitHub release](https://img.shields.io/github/v/release/hkvn/ViKey.svg)](https://github.com/hkvn/ViKey/releases/latest)

### [Tải bản mới nhất](https://github.com/hkvn/ViKey/releases/latest)

### Bộ gõ Tiếng Việt nguồn mở cho macOS, phát triển tiếp từ [OpenKey](https://github.com/tuyenvm/OpenKey) của Mai Vũ Tuyên.
ViKey dùng kỹ thuật `Backspace`, không bị lỗi gạch chân như bộ gõ mặc định của macOS. Hoàn toàn miễn phí và là nguồn mở theo giấy phép GPL-3.0.

Yêu cầu: **macOS 13 trở lên**.

### Lưu ý: khi dùng ViKey, hãy tắt hẳn bộ gõ khác (kể cả OpenKey), vì hai bộ gõ chạy cùng lúc sẽ gõ sai.

## Điểm mới so với OpenKey
- Cửa sổ cài đặt mới theo phong cách System Settings của macOS (SwiftUI), hỗ trợ giao diện sáng / tối.
- Báo cho bạn biết khi một ứng dụng bật Secure Input làm bộ gõ không gõ được, và cách khắc phục.
- Kiểm tra bản mới qua GitHub Releases của ViKey.
- Khởi động cùng macOS bằng SMAppService, không cần ứng dụng phụ.
- Tự chép cài đặt (gõ tắt, phím tắt, tuỳ chọn) từ OpenKey ở lần chạy đầu.
- Sửa nhiều lỗi: chuyển mã ký tự cuối, chữ hoa khi chuyển mã, chính tả "uych", gõ trong Spotlight, bộ gõ bị tắt sau khi chuyển mã nhanh,...

## Hỗ trợ kiểu gõ
- Telex
- VNI
- Simple Telex

## Bảng mã thông dụng:
- Unicode (Unicode dựng sẵn).
- TCVN3 (ABC).
- VNI Windows.
- Unicode Compound (Unicode tổ hợp).
- Vietnamese Locale CP 1258.
- ...

## Tính năng:
- **Modern orthography** (On/Off) - Đặt dấu oà, uý thay vì òa, úy.
- **Quick Telex** (On/Off) - Gõ nhanh (cc=ch, gg=gi, kk=kh, nn=ng, qq=qu, pp=ph, tt=th).
- **Grammar check** (On/Off) - Kiểm tra ngữ pháp.
- **Spelling check** (On/Off) - Kiểm tra chính tả.
- **Restore key if invalid word** (on/off) - Phục hồi phím với từ sai.
- **Run on startup** (On/Off) - Chạy cùng macOS.
- **Gray menu bar icon** (On/Off) - Biểu tượng xám trên thanh menu phù hợp với chế độ Dark mode.
- **Switch input mode by shortcut key** - Đổi chế độ gõ bằng phím tắt tùy chọn.
- **Autocorrect fixed** (On/Off) - Sửa lỗi autocorrect trên trình duyệt như Chrome, Safari, Firefox, Microsoft Excel.
- **Underline issue fixed on macOS** (On/Off) - Sửa lỗi gạch chân trên macOS.
- **Tạm tắt kiểm tra chính tả bằng phím Ctrl** (On/Off) (Bản 1.5 về sau).
- **Tạm tắt ViKey bằng phím Cmd** (On/Off) (Bản 2.0.1 về sau).
- **Cho phép dùng f z w j làm phụ âm đầu** (On/Off) (Bản 1.5 về sau).
- **Gõ tắt phụ âm đầu: f->ph, j->gi, w->qu** (On/Off) (Bản 1.6 về sau).
- **Gõ tắt phụ âm cuối: g->ng, h->nh, k->ch** (On/Off) (Bản 1.6 về sau).
- **Hiện biểu tượng trên thanh Dock** (On/Off) (Bản 2.0.1 về sau). Bấm vào icon trên thanh Dock sẽ mở nhanh cửa sổ Cài đặt.
- **Macro** - Tính năng gõ tắt vô cùng tiện lợi. Gõ tắt của macOS chỉ hỗ trợ 20 ký tự, còn ViKey không giới hạn ký tự.
- **Chuyển chế độ thông minh:** (On/Off) (Bản 1.2 về sau) - Bạn đang dùng chế độ gõ Tiếng Việt trên ứng dụng A, bạn chuyển qua ứng dụng B trước đó bạn dùng chế độ gõ Tiếng Anh, ViKey sẽ tự động chuyển qua chế độ gõ Tiếng Anh cho bạn, khi bạn quay lại ứng dụng A, ViKey tất nhiên sẽ chuyển lại chế độ gõ tiếng Việt, rất cơ động.
- **Viết Hoa chữ cái đầu câu** (On/Off) (Bản 1.2 về sau) - Khi gõ văn bản dài, đôi khi bạn quên ghi hoa chữ cái đầu câu khi kết thúc một câu hoặc khi xuống hàng, tính năng này sẽ tự ghi hoa chữ cái đầu câu cho bạn, thật tuyệt vời.
- **Chế độ “Gửi từng phím”:** (On/Off) (Bản 1.1 về sau) mặc định dùng kỹ thuật mới gửi dữ liệu 1 lần thay vì gửi nhiều lần cho chuỗi ký tự, nên nếu có ứng dụng nào không tương thích, hãy bật tính năng này lên, mặc định thì nên tắt vì kỹ thuật mới sẽ chạy nhanh hơn.
- **Kiểm tra bản mới:** khi mở ViKey hoặc trong mục Giới thiệu, ViKey kiểm tra bản phát hành mới nhất trên GitHub.
- **Công cụ chuyển mã:** (Bản 1.4 về sau) hỗ trợ chuyển mã qua lại văn bản, thích hợp cho việc chuyển đổi văn bản cũ viết bằng VNI, TCVN3 qua Unicode,... Hỗ trợ cấu hình phím tắt chuyển mã nhanh, bảng cấu hình tùy chọn chuyển mã.
- **Tự ghi nhớ bảng mã theo ứng dụng:** (Bản 2.0.1 về sau) Phù hợp cho các bạn dùng Photoshop, CAD,... với các bảng mã VNI, TCVN3. ViKey tự ghi nhớ ứng dụng nào dùng bảng mã nào để lần sau sử dụng Photoshop, CAD,... ViKey có thể tự chuyển sang bảng mã đó.
- ...

[Các phiên bản](https://github.com/hkvn/ViKey/releases) · [Changelog của OpenKey](https://github.com/tuyenvm/OpenKey/blob/master/CHANGELOG.md)

## Cài đặt
1. Tải file `ViKey-x.y.z.dmg` mới nhất từ [trang phát hành](https://github.com/hkvn/ViKey/releases/latest), mở ra và kéo `ViKey.app` vào thư mục Applications.
2. Lần đầu mở, nếu macOS chặn ứng dụng: vào *System Settings → Privacy & Security*, bấm **Open Anyway**.
3. ViKey cần quyền Accessibility: vào *System Settings → Privacy & Security → Accessibility* và bật `ViKey`. **Không tắt quyền này khi đang dùng ViKey.**

Nếu bạn chuyển từ OpenKey sang: ViKey tự chép cài đặt của OpenKey ở lần chạy đầu và đề nghị thoát OpenKey nếu nó đang chạy.

## Phát triển
- Build từ mã nguồn và tạo bản phát hành: xem [macOS_Build.md](macOS_Build.md).
- Mã nguồn bản Windows và Linux của OpenKey vẫn nằm trong thư mục `Sources/OpenKey`, nhưng ViKey hiện chỉ phát triển bản macOS.

## Giấy phép
ViKey là phần mềm nguồn mở theo giấy phép [GPL-3.0](LICENSE), phát triển tiếp từ OpenKey © Mai Vũ Tuyên. Nếu bạn phân phối lại bản sửa đổi, bản đó cũng phải là nguồn mở và ghi rõ nguồn gốc.

## Tác giả OpenKey
- Mai Vũ Tuyên - maivutuyen.91@gmail.com
- Fanpage: [https://www.facebook.com/OpenKeyVN](https://www.facebook.com/OpenKeyVN)
- Ủng hộ tác giả OpenKey: [Buy me a coffee](https://tuyenvm.github.io/donate.html) · [PayPal](https://paypal.me/tuyenmai)

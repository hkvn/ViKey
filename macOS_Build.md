## Build ViKey cho macOS

Yêu cầu:
- macOS 13 trở lên.
- Xcode 15 trở lên (đã thử với Xcode 26).
- Một chứng chỉ ký mã trong Keychain: "Apple Development" (tạo miễn phí trong Xcode → Settings → Accounts) hoặc "Developer ID Application".

Dự án Xcode: `Sources/OpenKey/macOS/OpenKey.xcodeproj`, scheme `OpenKey`, sản phẩm là `ViKey.app`.

### Build bằng dòng lệnh

```sh
cd Sources/OpenKey/macOS
xcodebuild -project OpenKey.xcodeproj -scheme OpenKey -configuration Release \
  CODE_SIGN_IDENTITY="Apple Development: you@example.com (XXXXXXXXXX)" \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=<TEAM_ID> PROVISIONING_PROFILE_SPECIFIER="" \
  build
```

`TEAM_ID` là giá trị `OU` của chứng chỉ:

```sh
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
```

Nếu build trong Xcode, hãy chọn team của bạn trong *Signing & Capabilities*.

### Chạy kiểm thử

```sh
scripts/run-tests.sh
```

- `Tests/engine`: bộ gõ (Telex, VNI, chính tả, cách đặt dấu), công cụ chuyển mã, gõ tắt (cả giá trị tự động như `{date}`), bộ nhớ theo ứng dụng, chuyển đổi UTF-8. Viết bằng C++, không cần Xcode project.
- `Tests/settings`: logic của cửa sổ Cài đặt (phím tắt, các tuỳ chọn), đọc file gõ tắt của UniKey / EVKey / macOS, đồng bộ gõ tắt qua thư mục. Dùng bản giả của AppDelegate nên không đụng tới cài đặt thật.

### Luồng bắt phím và nhật ký

- ViKey nhận phím trên một luồng riêng (`OpenKeyManager`), để cửa sổ hay hộp thoại trên luồng chính không làm chậm việc gõ. Bộ gõ và dữ liệu dùng chung (gõ tắt, bộ nhớ theo ứng dụng, phiên gõ) được bảo vệ bằng `ENGINE_LOCK` (xem `Engine.h`). Luồng bắt phím không bao giờ chờ luồng chính, chỉ gửi việc bằng `dispatch_async`.
- Nhật ký dùng `VKLog` (`Logging.h`): hiện trong cửa sổ *Chẩn đoán…* và trong Console.app với subsystem `com.hkvn.vikey`. Không bao giờ ghi nội dung người dùng gõ.

  ```sh
  log show --last 1h --predicate 'subsystem == "com.hkvn.vikey"' --style compact
  ```

GitHub Actions (`.github/workflows/macos.yml`) chạy kiểm thử và build ViKey khi một bản phát hành được publish trên GitHub, để kiểm tra bản đó build được trên máy sạch. Có thể chạy tay bằng nút **Run workflow** trong tab Actions. Script phát hành cũng chạy kiểm thử trên máy của bạn trước khi build.

### Vì sao nên ký bằng chứng chỉ thật

macOS ghi nhớ quyền Accessibility theo chữ ký của ứng dụng. Nếu ký ad-hoc (`CODE_SIGN_IDENTITY="-"`), mỗi bản build có chữ ký khác nhau, nên phải cấp quyền lại sau mỗi lần build. Ký bằng cùng một chứng chỉ thì quyền được giữ khi build lại hoặc cập nhật.

## Bộ gõ InputMethodKit (thử nghiệm, nhánh `imk`)

Ngoài ViKey.app (bắt phím bằng event tap, cần quyền Accessibility), nhánh này có thêm một bộ gõ dạng InputMethodKit: một nguồn nhập (input source) như bộ gõ tiếng Việt của macOS. Nó dùng chung bộ gõ C++ và đọc cài đặt của ViKey.app (kiểu gõ, bảng mã, chính tả, gõ tắt, phím chuyển, ứng dụng luôn dùng English).

```sh
scripts/build-input-method.sh             # build vào build/input-method/ViKeyInput.app
scripts/build-input-method.sh --install   # cài vào ~/Library/Input Methods và bật
scripts/build-input-method.sh --uninstall # tắt và gỡ
```

Sau khi cài, chọn **ViKey** trong menu nguồn nhập trên thanh menu. Khi nguồn nhập ViKey được chọn, ViKey.app tự đứng ngoài (không xử lý phím), nên có thể để cả hai cùng chạy.

- Không cần quyền Accessibility, và vẫn gõ được khi một ứng dụng chạy nền bật Secure Input (ô mật khẩu vẫn chỉ gõ được tiếng Anh, do macOS).
- Chế độ Tiếng Việt / English dùng chung với ViKey.app: chuyển ở đâu (phím tắt, menu) thì cả hai cùng đổi, biểu tượng trên thanh menu luôn đúng.
- Hai cách hiện từ đang gõ: **viết thẳng** vào ứng dụng (mặc định, không gạch chân, giống ViKey.app) hoặc **gạch chân** (marked text). Các ứng dụng dòng lệnh (Ghostty, Terminal, iTerm2,...) luôn dùng gạch chân, vì chúng không cho biết vị trí con trỏ. ViKey cũng tự chuyển sang gạch chân với ứng dụng khác không cho biết vị trí con trỏ; có thể chọn cho từng ứng dụng trong menu nguồn nhập.
- Mã nguồn: `Sources/OpenKey/macOS/InputMethod` (`Composer` dựng từ đang gõ từ kết quả của bộ gõ, `InputController` đưa từ vào ứng dụng). Kiểm thử: `Tests/inputmethod`.
- Chưa có: chuyển chế độ thông minh theo ứng dụng, gõ tắt khi tắt tiếng Việt, tương thích layout khác, chuyển mã nhanh.

## Tạo bản phát hành trên GitHub

Script `scripts/release-macos.sh` làm toàn bộ việc phát hành trên máy Mac của bạn, chứng chỉ không rời khỏi máy:

```sh
scripts/release-macos.sh 2.1.0 --dry-run   # chỉ build và đóng gói, để kiểm tra
scripts/release-macos.sh 2.1.0             # phát hành thật
```

Tuỳ chọn:
- `--draft`: tạo bản nháp trên GitHub. Người dùng và chức năng kiểm tra bản mới chưa thấy bản này cho đến khi bạn bấm Publish.
- `--notes FILE`: dùng nội dung FILE làm ghi chú phát hành (mặc định: danh sách commit từ bản phát hành trước).
- `--yes`: không hỏi lại trước khi phát hành.
- Biến môi trường `VIKEY_SIGN_IDENTITY`: chọn chứng chỉ khác (mặc định: "Developer ID Application" nếu có, nếu không thì "Apple Development").

Script sẽ:
1. Kiểm tra: `gh` đã đăng nhập, không có thay đổi chưa commit, tag `v<version>` chưa tồn tại.
2. Build `ViKey.app` với phiên bản mới và số build tăng thêm 1, ký bằng chứng chỉ của bạn.
3. Đóng gói `ViKey-<version>.dmg`, `ViKey-<version>.zip` và `SHA256SUMS.txt` vào `build/release/<version>/`.
4. Hỏi lại, rồi commit phiên bản mới ("Release ViKey <version>"), tạo tag `v<version>`, push nhánh hiện tại và tag lên `origin`.
5. Tạo GitHub release với các file trên và ghi chú cài đặt.

Chức năng kiểm tra bản mới trong ViKey đọc bản phát hành mới nhất của `hkvn/ViKey` (bỏ qua bản nháp), so sánh với phiên bản đang chạy, rồi mở trang tải về nếu có bản mới.

Quy trình gợi ý: làm việc trên nhánh `dev`, merge vào `master`, rồi chạy script trên `master`.

### Lưu ý về Gatekeeper

Bản phát hành được ký bằng chứng chỉ "Apple Development" nhưng chưa được Apple notarize, nên lần đầu mở, người dùng phải vào *System Settings → Privacy & Security* và bấm **Open Anyway**. Muốn bỏ bước này, cần chứng chỉ "Developer ID Application" (Apple Developer Program) và notarize bản build.

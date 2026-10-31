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

### Vì sao nên ký bằng chứng chỉ thật

macOS ghi nhớ quyền Accessibility theo chữ ký của ứng dụng. Nếu ký ad-hoc (`CODE_SIGN_IDENTITY="-"`), mỗi bản build có chữ ký khác nhau, nên phải cấp quyền lại sau mỗi lần build. Ký bằng cùng một chứng chỉ thì quyền được giữ khi build lại hoặc cập nhật.

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

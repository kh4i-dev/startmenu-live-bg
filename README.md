# startmenu-live-bg

Clip 15 giây làm **nền động cho Start menu Windows 11**, chạy bằng mod
[Windhawk](https://windhawk.net) `XAML-Video-Injector`.

![preview](docs/preview.png)

| | |
| --- | --- |
| Nguồn | [`J0shA9J-4Nc`](https://www.youtube.com/watch?v=J0shA9J-4Nc) — *Rest... Let the storm pass*, kênh **Quest & Rest** |
| Doạn cắt | `00:01:00` → `00:01:15` (15,00 s) |
| Xuất ra | H.264, 1280×720, 24 fps, không tiếng, `+faststart`, ~2 MB |
| File | [`media/start-bg.mp4`](media/start-bg.mp4) |

## Repo này có gì

```
media/start-bg.mp4        clip 15 giay de dua vao Windhawk
mod/settings.yaml         cau hinh dan thang vao tab Settings cua mod
scripts/make-clip.ps1     script tai + cat (tu lo yt-dlp / ffmpeg)
docs/preview.png          anh xem truoc
```

## Yêu cầu

- Windows 11 (Start menu dùng XAML/WinUI — mod **không** chạy trên Windows 10)
- [Windhawk](https://windhawk.net) đã cài
- Mod **XAML-Video-Injector** — nguồn:
  [bbmaster123/FWFU](https://github.com/bbmaster123/FWFU), thư mục
  `Personal Windhawk Mods/XAML-Video-Injector.cpp`

## Cài đặt

1. Clone về một đường dẫn **cố định, không dấu**:

   ```powershell
   git clone https://github.com/kh4i-dev/startmenu-live-bg.git D:\startmenu-live-bg
   ```

2. Windhawk → **Mods** → cài `XAML-Video-Injector`.
   Nếu store không có mod: **Create New Mod** → dán toàn bộ nội dung
   `XAML-Video-Injector.cpp` từ repo FWFU → **Compile mod**.

3. Mở mod → tab **Settings** → chuyển sang chế độ **Textual** → dán
   [`mod/settings.yaml`](mod/settings.yaml) → sửa đường dẫn cho khớp máy bạn:

   ```yaml
   - startMenuVideoUrl: "D:\\startmenu-live-bg\\media\\start-bg.mp4"
   ```

   Trong YAML phải dùng `\\` cho dấu `\`.

4. **Save settings** → **Exit mod** → **Enable mod** để nó nạp lại vào
   `StartMenuExperienceHost.exe`.

5. Bấm phím Windows. Clip sẽ lặp phía sau các icon.

> Không muốn dùng clip này? Dán URL của bạn vào `startMenuVideoUrl` — mod
> nhận cả URL trực tiếp. Hoặc chạy script bên dưới để làm clip mới.

## Tự làm lại clip

```powershell
cd D:\startmenu-live-bg
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\make-clip.ps1 `
    -Url "https://www.youtube.com/watch?v=J0shA9J-4Nc" `
    -Start "00:01:00" -Duration 15
```

Script tự tải `yt-dlp` + `ffmpeg` nếu máy chưa có, tải **đúng đoạn cần**
(`--download-sections`) nên không phải kéo cả video 5 tiếng, rồi xuất H.264 CRF 18
kèm `unsharp` nhẹ.

### Nếu YouTube chặn (bot-check / 429)

YouTube đang bật thử nghiệm **SABR-only** cho một số IP: client `web` không trả về
link tải, chỉ còn `android` với bản 360p. Cách xử lý:

```powershell
# 1. doi client hoac them cookie trinh duyet da dang nhap YouTube
.\scripts\make-clip.ps1 -Url "<url>" -Browser firefox     # net nhat
.\scripts\make-clip.ps1 -Url "<url>" -Client default      # de yt-dlp tu chon
```

`--cookies-from-browser chrome` / `edge` **không chạy được** trên Chrome/Edge 127+
vì App-Bound Encryption — yt-dlp báo `Failed to decrypt with DPAPI`. Dùng Firefox,
hoặc export `cookies.txt` rồi thêm `--cookies`.

Bản 360p vẫn dùng tốt cho Start menu: bề ngang Start menu chỉ ~640 px, và video
được crop theo chiều dọc nên phần thừa hai bên đằng nào cũng bị cắt.

## Ghi chú kỹ thuật

- **`startMenuZIndex: -1`** — đẩy video xuống dưới lớp XAML của Start menu. Để `0`
  trở lên là video che mất icon và ô tìm kiếm.
- **`startMenuOpacity: 100`** — theme Start menu có acrylic mờ thì hạ xuống 70–85
  cho dễ đọc chữ.
- **Không tiếng** (`-an`): mod cũng mute mặc định, và âm thanh Start menu gần như
  luôn là ý tồi.
- Mod chạy trong `StartMenuExperienceHost.exe`; sau khi **Windows Update** đôi khi
  phải tắt/bật lại mod.
- Máy yếu: đặt `startMenuRate: 50` (phát 0.5×) hoặc dùng `-Width 640`.

## Bản quyền

- Clip trong `media/` cắt từ video gốc trên YouTube — **bản quyền thuộc tác giả
  video gốc**. Repo chỉ lưu cho mục đích cá nhân, không phân phối lại.
- Mod `XAML-Video-Injector` thuộc về bbmaster123 — xem repo gốc để biết giấy phép.
- Script trong repo này: MIT.

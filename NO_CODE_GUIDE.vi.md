# Huong Dan Cho Team No-Code

Tai lieu nay danh cho nguoi dung macOS chi muon mo app va dung, khong can biet build hay config.

## Cai Lan Dau

Nguoi quan ly team gui link GitHub Release hoac file:

```text
Codex-Model-Switcher-<version>.dmg
```

Nguoi dung mo file `.dmg`, keo `Codex Model Switcher.app` vao `Applications`, roi mo app.

## Cach Dung Hang Ngay

1. Mo `Codex Model Switcher`.
2. Nhin len thanh menu tren cung cua macOS.
3. Bam icon `Codex Switch`.
4. Neu app hoi API key, dan 9Router API key vao va bam `Save`.
5. Chon `9Router` hoac `Authentic`.

## Dung Router Khac

App khong bi khoa vao `9router.bigroll.vn`:

1. Mo `Settings` trong app.
2. Dien dia chi moi vao `Router URL`, vi du `https://router.example.com`.
3. Bam dau check de luu.
4. Dien API key cua router do, sau do chon `9Router`.

App se nho URL nay cho cac lan mo sau. Router can co API tuong thich OpenAI, toi thieu gom `/v1/models` va endpoint nhan request nhu `/v1/responses`. Muon hien quota thi router co the cung cap them endpoint read-only `/v1/quota`. Co the dan URL goc, URL ket thuc bang `/v1`, hoac `/v1/models`; app se tu chuan hoa. Router tren Internet bat buoc dung HTTPS de API key duoc ma hoa khi truyen; HTTP chi duoc chap nhan cho localhost khi phat trien.

App se tu:

- Luu API key local tren may nguoi dung tai `~/.codex/.env`.
- Tu dong sync model tu 9Router khi mo app va khi chuyen sang 9Router.
- Tu dong kiem tra model moi moi 15 phut.
- Hien quota Codex ngay trong menu bar va tu cap nhat moi 2 phut neu router co ho tro.
- Tao model catalog de Codex thay model moi.
- Lay ten, thu tu, Effort va Speed tu catalog chinh hang cua Codex.
- Giu cac muc Effort chinh hang hoat dong duoc nhu `Max`, va tu loai `Ultra` khoi catalog 9Router de tranh chon nham che do khong duoc ho tro.
- Cap nhat mapping model ma khong can restart proxy hoac Codex.
- Dinh tuyen dung chinh xac model da chon; neu `5.6 Sol` loi thi app bao loi, khong doi sang Combo hay model khac.
- Start proxy chi tren may local tai `127.0.0.1:9783`.
- Cap nhat config Codex.
- Mo mot thread Codex moi.

## Xem Quota

Nguoi dung khong can dang nhap dashboard 9Router. Sau khi da luu API key, quota cua cac tai khoan Codex se tu hien trong app, tai khoan gan het quota duoc dua len truoc.

App hien email day du de team de nhan biet tung tai khoan, khong luu quota xuong may va khong can password quan tri 9Router. Neu dang dung mot router khac chua co endpoint quota, muc nay se tu an; chuc nang switch van hoat dong binh thuong.

## Them Model Moi

Neu model da ton tai trong 9Router hoac Combo cua team:

1. Them model/Combo tren 9Router.
2. Khong can sua config hoac them model trong Codex Switch.
3. App se tu dong nhan model trong lan dong bo tiep theo, toi da khoang 15 phut.

Neu model cung co trong catalog chinh hang cua Codex, app dung ten, thu tu va control chinh hang. Neu model chi co tren 9Router, app van them model nhung chi hien control an toan. App khong tu tao Combo tren 9Router neu 9Router khong cung cap admin API cho viec do.

## Update App

Lan cai dau tien can gui file `.dmg` cho moi nguoi.

Sau do, moi nguoi se thay thong bao khi co version moi. Thong bao co nut `Update Now` de cap nhat ngay va `Remind Me Later` de macOS nhac lai sau 4 gio. App tu tai DMG, kiem tra checksum/signature, cai dat va mo lai app.

De update hoat dong, nguoi quan ly team can upload:

- File `.dmg` moi.
- File `update.json` moi len dung URL da cau hinh trong app.

## Khi Co Su Co

Bam `Authentic` de quay ve provider goc va dung proxy.

App tao backup lan dau tai:

```text
~/.codex/config.toml.before-model-switcher
```

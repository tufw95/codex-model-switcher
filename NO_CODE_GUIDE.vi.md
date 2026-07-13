# Huong Dan Cho Team No-Code

Tai lieu nay danh cho nguoi dung macOS chi muon mo app va dung, khong can biet build hay config.

## Cai Lan Dau

Nguoi quan ly team gui link GitHub Release hoac file:

```text
Codex-Model-Switcher-1.0.0.dmg
```

Nguoi dung mo file `.dmg`, keo `Codex Model Switcher.app` vao `Applications`, roi mo app.

## Cach Dung Hang Ngay

1. Mo `Codex Model Switcher`.
2. Nhin len thanh menu tren cung cua macOS.
3. Bam icon `Codex Switch`.
4. Neu app hoi API key, dan 9Router API key vao va bam `Save`.
5. Chon `9Router` hoac `Authentic`.

App se tu:

- Luu API key local tren may nguoi dung tai `~/.codex/.env`.
- Tu dong sync model tu 9Router khi mo app va khi chuyen sang 9Router.
- Tu dong kiem tra model moi moi 15 phut.
- Tao model catalog de Codex thay model moi.
- Lay ten, thu tu, Effort va Speed tu catalog chinh hang cua Codex.
- Giu cac muc Effort chinh hang hoat dong duoc nhu `Max`, va tu loai `Ultra` khoi catalog 9Router de tranh chon nham che do khong duoc ho tro.
- Cap nhat mapping model ma khong can restart proxy hoac Codex.
- Start local proxy.
- Cap nhat config Codex.
- Mo mot thread Codex moi.

## Them Model Moi

Neu model da ton tai trong 9Router hoac Combo cua team:

1. Them model/Combo tren 9Router.
2. Khong can sua config hoac them model trong Codex Switch.
3. App se tu dong nhan model trong lan dong bo tiep theo, toi da khoang 15 phut.

Neu model cung co trong catalog chinh hang cua Codex, app dung ten, thu tu va control chinh hang. Neu model chi co tren 9Router, app van them model nhung chi hien control an toan. App khong tu tao Combo tren 9Router neu 9Router khong cung cap admin API cho viec do.

## Update App

Lan cai dau tien can gui file `.dmg` cho moi nguoi.

Sau do, neu app duoc build voi `UPDATE_MANIFEST_URL`, moi nguoi se thay thong bao khi co version moi. Nguoi dung bam `Download` de tai ban moi.

De update hoat dong, nguoi quan ly team can upload:

- File `.dmg` moi.
- File `update.json` moi len dung URL da cau hinh trong app.

## Khi Co Su Co

Bam `Authentic` de quay ve provider goc va dung proxy.

App tao backup lan dau tai:

```text
~/.codex/config.toml.before-model-switcher
```

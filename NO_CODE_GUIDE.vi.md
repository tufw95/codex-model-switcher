# Huong Dan Cho Team No-Code

Tai lieu nay danh cho nguoi dung macOS chi muon mo app va dung, khong can biet build hay config.

## Cai Lan Dau

Nguoi quan ly team gui file:

```text
Codex-Model-Switcher-1.0.0.dmg
```

Nguoi dung mo file `.dmg`, keo `Codex Model Switcher.app` vao `Applications`, roi mo app.

Neu ban build ban noi bo co nhung san API key, dong nghiep khong can nhap key. App se tu luu key vao `~/.codex/.env` trong lan mo dau tien.

## Cach Dung Hang Ngay

1. Mo `Codex Model Switcher`.
2. Nhin len thanh menu tren cung cua macOS.
3. Bam icon `Codex Switch`.
4. Chon `9Router` hoac `Authentic`.

App se tu:

- Tu dong lay API key da nhung trong app neu may chua co key.
- Tu dong sync model tu 9Router khi mo app va khi chuyen sang 9Router.
- Tao model catalog de Codex thay model moi.
- Start local proxy.
- Cap nhat config Codex.
- Mo mot thread Codex moi.

## Them Model Moi

Neu model da ton tai trong 9Router hoac Combo cua team:

1. Them model/Combo tren 9Router.
2. Bam icon `Codex Switch` tren thanh menu macOS.
3. Bam `9Router`.

App se tu sync danh sach model tu 9Router va tao catalog local cho Codex. App khong tu tao Combo tren 9Router neu 9Router khong cung cap admin API cho viec do.

## Update App

Lan cai dau tien can gui file `.dmg` cho moi nguoi.

Sau do, neu app duoc build voi `UPDATE_MANIFEST_URL`, moi nguoi se thay thong bao khi co version moi. Nguoi dung bam `Download` de tai ban moi.

De update hoat dong, nguoi quan ly team can upload:

- File `.dmg` moi.
- File `update.json` moi len dung URL da cau hinh trong app.

## Tao Ban Team Co San API Key

Nguoi build app chay lenh:

```bash
BUNDLED_NINEROUTER_API_KEY="sk-..." \
ROUTER_TARGET_URL="https://9router.bigroll.vn" \
UPDATE_MANIFEST_URL="https://your-domain.example/update.json" \
VERSION=1.0.0 \
BUILD_NUMBER=1 \
./scripts/package_dmg.sh
```

Can hieu ro: API key nhung trong app co the bi trich xuat neu ai do co y dinh dao nguoc binary. Cach nay phu hop cho team noi bo tin cay. Neu can bao mat hon, nen dung proxy/team gateway rieng de khong phat tan key that.

## Khi Co Su Co

Bam `Use Authentic Codex` de quay ve provider goc va dung proxy.

App tao backup lan dau tai:

```text
~/.codex/config.toml.before-model-switcher
```

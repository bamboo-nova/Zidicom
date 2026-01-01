# 概要

ZigでコンパイルしたWebAssemblyモジュールを使用したDICOMビューアです。

## 機能

- JPEG Lossless および LEE (Little Endian Explicit) 形式など複数のDICOMファイルをサポート
- WebAssemblyによる高速なメタデータ抽出
- Web UIのデモ環境
- ドラッグ&ドロップでDICOMファイルをアップロード可能

## サンプルデータ

下記にDICOM形式のデータセットが公開されているので、適宜ダウンロードして試すことが可能です。

- [ZioCube ユーザーサポート](https://www.zio.co.jp/ziocube/support/#sec11)
- [JIRA(一般社団法人 日本画像医療システム工業会 DICOM画像ファイル)](https://www.zio.co.jp/ziocube/support/#sec11)

## 使い方(Zig)

```bash
zig build

./zig-out/bin/dicom_viewer ******.dcm
```

## セットアップ(デモ環境)

### 1. 依存関係のインストール

```bash
npm install
```

### 2. WASMモジュールのビルド

```bash
npm run build:wasm
```

### 3. TypeScriptのビルド

```bash
npm run build
```

## 使い方(デモ環境)

### コマンドラインテスト

```bash
npm test
```

プロジェクトルートの `.dcm` ファイルを自動的に検出して、メタデータと画像サイズを抽出します。

### Webサーバーの起動

```bash
npm start
```

ブラウザで http://localhost:3000 にアクセスします。

- サンプルファイル（プロジェクトルートの .dcm ファイル）をボタンで選択
- または、ファイルをドラッグ&ドロップしてアップロード

## 開発

TypeScriptの変更を反映する場合：

```bash
npm run dev
```

## プロジェクト構成

```
Zidicom/
├── src/                 # Zig ソースコード
│   ├── dicom/           # DICOM パーサー
│   ├── image/           # 画像処理 (JPEG Lossless, LEE)
│   └── wasm/            # WASM エクスポート
├── public/              # 静的ファイル
│   └── index.html       # Web UI
├── dicom-wasm.ts        # WASM ラッパー (TypeScript)
├── server.ts            # Express サーバー
├── test.ts              # テストスクリプト
├── build.zig            # Zig ビルド設定
└── zig-out/wasm/        # コンパイル済み WASM モジュール
```

## API エンドポイント

- `GET /api/test` - WASM動作確認
- `POST /api/dicom/metadata` - メタデータ抽出
- `POST /api/dicom/dimensions` - 画像サイズ取得
- `POST /api/dicom/info` - メタデータ + 画像サイズ
- `GET /api/samples` - サンプルファイル一覧
- `GET /api/sample/:filename` - サンプルファイル取得

## 対応フォーマット

1. Implicit VR Little Endian (UID: 1.2.840.10008.1.2)
    - 非圧縮、VR暗黙的
2. Explicit VR Little Endian (UID: 1.2.840.10008.1.2.1)
    - 非圧縮、VR明示的
3. Explicit VR Big Endian (UID: 1.2.840.10008.1.2.2)
    - 非圧縮、ビッグエンディアン
4. JPEG Baseline (Process 1) (UID: 1.2.840.10008.1.2.4.50)
    - STB Image経由でデコード（pixel_data.zig）
5. JPEG Lossless (UID: 1.2.840.10008.1.2.4.70)
    - 独自で実装（jpeg_lossless.zig）

## 非対応フォーマット
- JPEG 2000 Lossless / JPEG 2000
- RLE Lossless

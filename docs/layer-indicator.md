# 現在のレイヤーをMacに表示する

右手側(セントラル)のファームウェアは、レイヤーが切り替わるたびに
Raw HID で現在のレイヤーをホストへ送ります。
Mac 側では `host/` の補助プログラムと Hammerspoon モジュールで表示します。

- メニューバー: 常に現在のレイヤー名
- 画面右下: レイヤー0以外のときだけ表示(HUD)。位置と画面は `M.hudPosition` / `M.hudScreen` で変更可

## 構成

| 場所 | 役割 |
| --- | --- |
| `src/layer_report.c` | レイヤー変更を Raw HID で送信 |
| `config/west.yml` の `zmk-raw-hid` | Raw HID の送受信 (zzeneg/zmk-raw-hid) |
| `snippets/split-central/split-central.conf` | `CONFIG_RAW_HID=y` などを有効化 |
| `host/zen-layer-hid/main.swift` | Raw HID を読み、JSON 行で出力 |
| `host/hammerspoon/zen_layer.lua` | 上の出力をメニューバーと HUD に表示 |

## セットアップ

1. 右手側のファームウェアを書き込む
2. Bluetooth で使う場合は、Mac とキーボードのペアリングをやり直す
   (HID サービスが増えるため、古いペアリング情報のままでは Raw HID が届かない)
3. `host/install.sh` を実行する(Hammerspoon の設定ディレクトリに入る。通常は `~/.hammerspoon`、`MJConfigFile` を設定していればその場所)
4. 設定ディレクトリの `init.lua` に `require("zen_layer").start()` を追加し、Hammerspoon を再読み込みする

表示名は `zen_layer.lua` の `M.labels` で変更できます。
未定義のレイヤーは、キーマップの `display-name`(ZMK Studio で付けた名前を含む)、
それも無ければ `L<番号>` を表示します。

## 通信内容

Raw HID のレポート(32バイト, Usage Page `0xFF60`, Usage `0x61`):

| バイト | 内容 |
| --- | --- |
| 0 | `0x4C` ('L') |
| 1 | バージョン (1) |
| 2 | 最上位の有効レイヤーの番号(キーマップ上の位置) |
| 3 | 同レイヤーの ID |
| 4-7 | レイヤー状態のビットマスク(ID 単位、リトルエンディアン) |
| 8- | レイヤー名(NUL 終端) |

ホストが先頭 `0x4C` のレポートを書き込むと、現在の状態を送り返します。
`zen-layer-hid` は接続時にこれを送るため、起動直後から表示されます。

## 確認方法

設定ディレクトリの `bin/zen-layer-hid` をターミナルで直接実行すると、
受信内容が JSON 行で表示されます(Ctrl-D で終了)。

# olm 設計書

## 概要

olm はシェルコマンドの実行・解析・履歴管理を行う CLI ツール。
AI（ollama 等）はオプション依存とし、なくても RAG ベースで動作する。

---

## ディレクトリ構成

```
olm/
├── README.md
├── DESIGN.md                   ← 本ファイル
├── setup.sh                    ← インストール・初期化スクリプト
├── bin/
│   └── olm                     ← エントリポイント（サブコマンドの振り分けのみ）
├── lib/
│   ├── common.sh               ← 共通関数（die, esc, config 読み込み等）
│   ├── cmd_analyze.sh          ← --analyze（stdin テキスト解析）
│   ├── cmd_exec.sh             ← コマンド実行・結果表示
│   ├── cmd_history.sh          ← history サブコマンド
│   └── cmd_config.sh           ← config get/set/list サブコマンド
├── config/
│   ├── config.env              ← デフォルト値（リポジトリ管理・上書き禁止）
│   └── config.schema.txt       ← キー一覧・型・説明
├── lang/
│   ├── en/
│   │   ├── help.txt            ← ヘルプテキスト（英語）
│   │   └── prompt.txt          ← LLM プロンプトテンプレート（英語）
│   └── jp/
│       ├── help.txt            ← ヘルプテキスト（日本語）
│       └── prompt.txt          ← LLM プロンプトテンプレート（日本語）
├── ai/
│   ├── ollama.sh               ← ollama アダプター
│   ├── openai.sh               ← OpenAI アダプター（将来）
│   └── none.sh                 ← AI なしフォールバック（echo のみ）
├── rag/
│   ├── run.sh                  ← コマンドラッパー（実行・記録・RAG検索）
│   ├── store.sh                ← DB 操作（init/add/search/save-ok/save-failed）
│   ├── hint.sh                 ← 実行前コマンドヒント・予測変換の土台
│   └── rag.db                  ← SQLite DB（.gitignore 推奨）
└── completion/
    └── engine.sh               ← リアルタイム予測変換エンジン（スタブ）
```

---

## モジュール設計

### bin/olm

サブコマンドの振り分けのみ行う。処理は `lib/` に委譲。

```
olm <cmd>         → lib/cmd_exec.sh
olm --analyze     → lib/cmd_analyze.sh
olm history       → lib/cmd_history.sh
olm config        → lib/cmd_config.sh
olm --help        → lang/$OLM_LANG/help.txt を表示
```

### lib/common.sh

全モジュールが `source` する共通関数。

- `die()` : エラー終了
- `esc()` : SQL エスケープ
- `load_config()` : config.env → ~/.config/olm/config.env の順に読み込み
- `ask_ai()` : ai/ アダプターへの統一インターフェース
- `get_prompt()` : lang/$OLM_LANG/prompt.txt を読み込んでテンプレート展開

### config/

| ファイル | 役割 |
|---|---|
| `config.env` | リポジトリ管理のデフォルト値。直接編集しない |
| `config.schema.txt` | 全キーの説明・型・デフォルト値一覧 |

ユーザー設定は `~/.config/olm/config.env` に書く。`setup.sh` が初回作成する。
読み込み順：`config/config.env` → `~/.config/olm/config.env`（後者が優先）。

主要キー：

| キー | 説明 | デフォルト |
|---|---|---|
| `OLM_LANG` | 言語（en / jp） | `jp` |
| `OLM_MODEL_STD` | 標準モデル | `phi3:3.8b-mini-4k-instruct-q4_k_m` |
| `OLM_MODEL_LGT` | 軽量モデル | `phi3:3.8b-mini-4k-instruct-q4_k_m` |
| `OLM_MODEL_HVY` | 重量モデル | `llama3:8b` |
| `OLM_USE_RAG` | RAG 有効フラグ | `1` |
| `OLM_AI_ADAPTER` | 使用アダプター（ollama/openai/none） | `ollama` |

### ai/

AI バックエンドをアダプターパターンで切り替え可能にする。

```bash
# 共通インターフェース（各アダプターが実装する）
ask "$prompt"  →  標準出力にレスポンスを返す
```

`OLM_AI_ADAPTER=none` のとき `none.sh` が使われ、AI なしで動作する。
ollama が起動していなくても RAG 機能は独立して動く。

### rag/run.sh

コマンドを wrap して実行するラッパー。

```
run.sh -- <command>
  1. hint.sh でコマンドを事前チェック（ヒント表示）
  2. コマンド実行・stdout/stderr 取得
  3. 成功 → store.sh save-ok
  4. 失敗 → store.sh save-failed + store.sh search でRAG検索
  5. RAG ヒットなし + LLM_ENABLE=1 → ai/ アダプター呼び出し
```

### rag/store.sh

SQLite（rag.db）の CRUD を担うサブコマンド形式のスクリプト。

```
store.sh init
store.sh add [--stdin] <title> <tags> [body]
store.sh search <query>
store.sh save-ok  --cmd .. --dur .. --cwd .. --stdout <file>
store.sh save-failed --cmd .. --rc .. --dur .. --cwd .. --stderr <file> --stdout <file>
store.sh suggest-ok <cmd>
store.sh rule-suggest <cmd>  < stderr.txt
```

### rag/hint.sh

コマンド実行前にルールベースでヒントを出す。
将来の `completion/engine.sh` の入力候補生成とも連携する。

出力形式（TAB 区切り）：
```
SUGGEST_KIND    ssh-keygen-ed25519-default
SUGGEST_QUERY   ssh-keygen ed25519
REASON          ssh は接続コマンド。鍵生成は ssh-keygen（別コマンド）
TAGS            ssh,keygen,auth
```

---

## completion/ — リアルタイム予測変換設計

### 目的

ユーザーがコマンドを入力中に、リアルタイムで候補を表示する。
ターミナルの readline 補完や fzf との統合を想定。

### アーキテクチャ

```
入力文字列（部分一致）
    │
    ├── hint.sh（ルールベース候補）
    ├── store.sh search（RAG 履歴候補）
    └── ai/ ask（LLM 候補・オプション）
    │
    ↓
候補リスト（スコア付き）
    │
    ↓
engine.sh（候補をマージ・ランキング・出力）
    │
    ↓
fzf / readline / カスタム UI へ渡す
```

### engine.sh インターフェース（設計）

```bash
# 入力：部分文字列
# 出力：候補を1行1件で標準出力
echo "git stat" | completion/engine.sh

# 出力例
git status
git stash
git stash pop
```

### 候補ソース優先順位

1. ルールベース（hint.sh） — 最速・確実
2. RAG 履歴（store.sh search） — 過去の成功コマンドから
3. LLM（ai/ アダプター） — オプション・低速

### 統合方法（将来）

```bash
# bash の場合：~/.bashrc に追記
bind -x '"\t": _olm_complete'
_olm_complete() {
  local cur="${COMP_LINE}"
  COMPREPLY=( $(echo "$cur" | olm/completion/engine.sh) )
}

# fzf と組み合わせる場合
echo "$partial" | completion/engine.sh | fzf --height 10
```

### 実装ステップ

1. `engine.sh` スタブ作成（入力を受け取って hint.sh + store.sh を呼ぶだけ）
2. RAG 履歴からの候補生成を実装
3. スコアリング・重複排除ロジック追加
4. bash/zsh バインディング実装
5. fzf UI 統合
6. LLM 候補（オプション）追加

---

## データフロー

```
olm "git status"
    │
    └── lib/cmd_exec.sh
            │
            ├── rag/run.sh -- git status
            │       │
            │       ├── hint.sh "git status"       # 事前チェック
            │       ├── git status 実行
            │       ├── 成功 → store.sh save-ok
            │       └── 失敗 → store.sh save-failed
            │               └── store.sh search    # RAG検索
            │                       └── ai/ask     # ヒットなし時
            │
            └── 結果表示 → LLM解析（OLM_USE_RAG=1 時）
                    └── ai/$OLM_AI_ADAPTER.sh
                            └── lang/$OLM_LANG/prompt.txt
```

---

## 拡張ポイント

| 拡張 | 場所 | 方法 |
|---|---|---|
| AI バックエンド追加 | `ai/` | 新しいアダプター `.sh` を追加 |
| 言語追加 | `lang/` | 新しい言語ディレクトリを追加 |
| ヒントルール追加 | `rag/hint.sh` | `case` 文にパターンを追記 |
| 予測変換強化 | `completion/engine.sh` | ソースを追加・スコアリング調整 |
| コマンド追加 | `lib/cmd_*.sh` + `bin/olm` | 新しい `cmd_*.sh` を作って振り分け追加 |

---

## 安全設計方針

- LLM の提案は表示のみ。自動実行しない
- root 操作・パッケージインストールは提案しない
- `store.sh search` は読み取り専用（`-readonly` フラグ）
- `eval` 禁止。ヒント出力は TAB 区切りで安全にパース

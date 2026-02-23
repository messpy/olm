# olm

シェルコマンドの実行・解析・履歴管理を行う CLI ツール。
AI（ollama 等）はオプション。なくても RAG ベースで動作する。

---

## インストール

```bash
./setup.sh
source ~/.profile
olm --help
```

---

## 使い方

```bash
# コマンドを実行して結果を解析
olm "ls -la"

# RAG ラッパーで実行（失敗時に過去の類似エラーを検索）
olm -e "git status"

# stdin のテキストを解析
echo "some log text" | olm --analyze

# 複数コマンドを順に実行
printf "%s\n" "pwd" "ls -la" | olm --exec-stdin --yes

# 履歴
olm history --last 50

# 設定
olm config list
olm config set OLM_LANG jp
```

---

## ディレクトリ構成

```
olm/
├── README.md
├── DESIGN.md                   ← 設計書
├── setup.sh
├── bin/
│   └── olm                     ← エントリポイント
├── lib/
│   ├── common.sh               ← 共通関数
│   ├── cmd_analyze.sh          ← --analyze
│   ├── cmd_exec.sh             ← コマンド実行
│   ├── cmd_history.sh          ← history
│   └── cmd_config.sh           ← config
├── config/
│   ├── config.env              ← デフォルト値
│   └── config.schema.txt       ← キー一覧・説明
├── lang/
│   ├── en/
│   │   ├── help.txt
│   │   └── prompt.txt
│   └── jp/
│       ├── help.txt
│       └── prompt.txt
├── ai/
│   ├── ollama.sh               ← ollama アダプター
│   ├── openai.sh               ← 将来用
│   └── none.sh                 ← AI なしフォールバック
├── rag/
│   ├── run.sh                  ← コマンドラッパー
│   ├── store.sh                ← DB 操作
│   ├── hint.sh                 ← コマンドヒント
│   └── rag.db                  ← SQLite DB
└── completion/
    └── engine.sh               ← リアルタイム予測変換（実装中）
```

---

## 設定

ユーザー設定は `~/.config/olm/config.env` に書く。`setup.sh` が初回作成する。

| キー | 説明 | デフォルト |
|---|---|---|
| `OLM_LANG` | 言語（en / jp） | `jp` |
| `OLM_MODEL_STD` | 標準モデル | `phi3:3.8b-mini-4k-instruct-q4_k_m` |
| `OLM_MODEL_LGT` | 軽量モデル | `phi3:3.8b-mini-4k-instruct-q4_k_m` |
| `OLM_MODEL_HVY` | 重量モデル | `llama3:8b` |
| `OLM_USE_RAG` | RAG 有効フラグ | `1` |
| `OLM_AI_ADAPTER` | AI アダプター（ollama/openai/none） | `ollama` |
| `OLM_ALWAYS_PROMPT` | 毎回追加するプロンプト | （空） |

全キーの説明は `config/config.schema.txt` を参照。

---

## RAG

失敗したコマンドと成功したコマンドを SQLite に蓄積し、類似エラーを検索する。

```bash
# DB 初期化（初回のみ）
rag/store.sh init

# 手動でメモを登録
rag/store.sh add "venv忘れ" "python,venv" "source .venv/bin/activate してから実行"

# 検索
rag/store.sh search "permission denied"

# RAG ラッパーで実行（失敗時に自動で検索・記録）
rag/run.sh -- python train.py
```

### 環境変数（rag/run.sh）

| 変数 | 説明 | デフォルト |
|---|---|---|
| `AUTO_SAVE_FAILED` | 失敗を自動保存 | `1` |
| `DO_RAG_SEARCH` | 失敗時に RAG 検索 | `1` |
| `HINT_ENABLE` | 実行前ヒント表示 | `1` |
| `HINT_INTERACTIVE` | ヒント選択 UI | `auto` |
| `LLM_ENABLE` | RAG ヒットなし時に LLM 提案 | `0` |

---

## AI アダプター

`OLM_AI_ADAPTER` で切り替え。ollama が起動していなくても `none` で動作する。

```bash
# ollama を使う（デフォルト）
olm config set OLM_AI_ADAPTER ollama

# AI を使わない
olm config set OLM_AI_ADAPTER none
```

---

## リアルタイム予測変換（実装中）

入力中のコマンドに対してリアルタイムで候補を表示する。
詳細は `DESIGN.md` の `completion/` セクションを参照。

---

## トラブルシュート

**Permission denied**
```bash
chmod +x bin/olm rag/run.sh rag/store.sh rag/hint.sh
```

**rag.db not found**
```bash
rag/store.sh init
```

**ollama に繋がらない**
```bash
olm config set OLM_AI_ADAPTER none
```

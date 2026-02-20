# olm 設計書
- 対象
- bash の単一スクリプト
- WSL Linux を想定
- 実行入口は ~/bin/olm の symlink
- 実体は repo の bin/olm

# 目的
- コマンド実行と結果の補助
- LLMで短い解説を出す
- 失敗時は原因と確認コマンドを優先する
- 危険コマンドや秘密情報の可能性があるものはデフォルトで履歴に残さない

# 重要な制約
- 実行は bash -lc で行う
- --analyze は実行しない stdin を要約するだけ
- --exec-stdin は危険なので --yes 必須
- 確認コマンドは非破壊のみを想定する

# ディレクトリ構成
- bin
- bin/olm 本体
- config
- config/config.env.example ユーザー設定のテンプレ
- jp
- jp/help.txt ヘルプ日本語
- en
- en/help.txt ヘルプ英語

# 設定
- 読み込み順
- 環境変数
- ~/.config/olm/config.env
- 主なキー
- OLM_MODEL_STD 標準モデル
- OLM_MODEL_LGT 軽量モデル
- OLM_MODEL_HVY 重量モデル
- OLM_MODEL_FA 軽量フォールバック
- OLM_MODEL_FB 重量フォールバック
- OLM_LANG help の言語
- OLM_ALWAYS_PROMPT 常時付与するLLM指示
- 出力サイズ制限
- OLM_CMD_MAX_CHARS
- OLM_LLM_MAX_CHARS
- OLM_MAX_LINE_CHARS
- OLM_MAX_EXPLAIN_CHARS
- OLM_MAX_SUGGEST_CMDS
- OLM_MAX_CONFIRM_CMDS

# データ保存
- LOG_DIR
- 既定
- ~/.local/share/olm
- ログ
- olm.log
- 履歴
- olm_history.tsv
- 履歴の列
- 時刻
- exit status
- コマンド
- 要約

# 実行フロー
- 引数判定
- --help
- --logs
- config サブコマンド
- history サブコマンド
- オプション解析
- モード選択
- normal
- analyze
- exec-stdin
- コマンド実行
- 出力のミュート
- 出力のトリム
- 追加診断情報の収集
- LLMの必要判定
- --no-llm
- -e 成功時スキップ
- LLM実行
- モデル候補を順に試す
- ログと履歴
- 危険または秘密の可能性があるコマンドは記録しない
- 返り値
- 元コマンドの exit status を返す

# セキュリティ設計
- デフォルトで履歴に残さない対象
- rm dd mkfs fdisk wipefs など破壊系
- Authorization Bearer token password api_key など秘密情報の可能性
- ログ出力時は簡易マスクを行う
- 完全な秘匿は保証しない

# 今後の拡張候補
- history を jsonl にも保存
- コマンド分類と危険判定ルールを設定化
- 成功時の要約のみモード
- 常時監視の仕組みは olm の責務外

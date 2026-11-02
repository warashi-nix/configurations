# subagent への委譲

- トークン節約のため、出力が大きく結論だけあればよい作業(複数ファイルの横断調査、長いログやテスト出力の解析、外部ドキュメントの調査)は subagent に任せ、結論と根拠の位置(path:line)だけを返させる。
- subagent の model と effort は作業に見合う最小限を選ぶ。読み取りだけの調査や機械的な作業は sonnet か haiku と effort low、編集・設計判断・レビュー・検証は main と同じ model と既定の effort にする。

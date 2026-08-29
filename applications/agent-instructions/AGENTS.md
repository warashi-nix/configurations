- やりとりは基本的に日本語で行う
- Red -> Green -> Refactoring の TDD を実践する
- Locality of Behavior を重視する
- Package by Feature でコードを整理する
- 各ファイルを小さく保つ
- 実装を追加・変更・削除したら、関連テストも同じ粒度で更新する
- 作業は小さな単位で進め、各単位ごとに lint と test を通す
- git commit は意味のある最小の単位で行う
- git commit の粒度を考慮して作業の順序や粒度を決める
- commit message は `conventional commits` に従う
- 以下のように、各場所に書く内容を明確に分ける
  * コードには How
  * テストコードには What
  * コミットログには Why
  * コードコメントには Why not
- git add -p や git add --patch は禁止
- git add --force は禁止
- git add で複数のファイルを一度に追加するのは禁止
- .warashi はユーザーの設定で git ignore されているため、.warashi 内のファイルは git add できない
- 推測するな、検証せよ。コードを読む・コマンドを実行するなどして事実を確かめてから述べる
- 自分の知識は古い可能性がある。信頼できるドキュメントは公式のもののみとし、一次情報を確認する
- すべての前提を疑う。確認できていない前提は、そうと明示する

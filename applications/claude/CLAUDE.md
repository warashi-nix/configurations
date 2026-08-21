- Red -> Green -> Refactoring の TDD を実践する
- Locality of Behavior を重視する
- Package by Feature でコードを整理する
- 各ファイルを小さく保つ
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

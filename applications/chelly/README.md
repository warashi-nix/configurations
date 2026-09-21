# chelly

## 起動時の開発環境

`flake.nix` がある場合は、Nix 2.34.8 の `nix develop` と同じ順序で
`devShells.<system>.default`、`devShell.<system>`、
`packages.<system>.default`、`defaultPackage.<system>` を探す。
純粋評価を維持し、最初に見つかった候補を使う。

候補が無ければ無音で `shell.nix`、通常のコマンド／bash の順に進む。
評価失敗や候補の型不正は Nix のエラーと `chelly:` の診断を stderr に出し、
修復作業ができるよう同じフォールバックで起動を続ける。
判定の出力は stdout に流さず、ACP の通信を妨げない。
選択後の環境ビルドに失敗した場合は `nix develop` のエラーで終了し、
環境に入れたように見せて通常コマンドを実行し直すことはしない。

### 会話の再開とコンテナの再作成

コンテナ内の共通説明を `/etc/chelly/AGENTS.md` に置き、Claude Code は
`/etc/claude-code/CLAUDE.md` のリンクから、Copilot CLI は
`COPILOT_CUSTOM_INSTRUCTIONS_DIRS` から読む。entrypoint は既存の追加
instruction directory を残したまま `/etc/chelly` を加える。
ホストの instruction ファイルにはコンテナ固有の説明を書き込まない。

会話を再開しても、前回のコンテナ内にだけ入れたツールや実行中のプロセスは
復元されない。永続化されたファイルと実行環境の継続を区別し、使用前の状態確認と
既存の devShell／セットアップ手順での再現を両 agent に伝える。
新たな永続領域や全環境の自動復元は追加しない。
この説明は agent の判断を助けるもので、隔離や操作禁止を強制する境界ではない。

## workbench: ホストの Nix store の共用

workbench は native rootless Podman と `nix-store = "host"` を使い、
ホストの `/nix` を読み取り専用でコンテナに渡す。取得・ビルドはホストの
Nix daemon が行い、コンテナ用に store を複製しない。

`host-store.nix` と `modules/nixos/chelly-nix-proxy.nix` が対になる。
本物の daemon socket はコンテナ側で覆い隠し、wheel に属さない専用ユーザー
`chelly-nix-proxy` の接続だけを見せる。`--userns=keep-id` の本人の UID で
ホストの trusted user へ直接接続する構成にはしない。
コンテナ内の Nix も `CHELLY_NIX_BIN` でホストと同じ版を使う。

これは VM による隔離ではなく、ホストとカーネルを共有する構成。
ホストのディスク・ビルド資源も使う。VM 化はまだ有効にしていない。
既存の Unix socket を VM にそのまま共有できるとも扱わない。

VM 化する場合は、store の読み取り共有だけでなく、ホストへの処理の委譲と
ホストから見える GC root の維持が必要になる。Nix 2.34.8 の
`mounted-ssh-ng` で既存 daemon 越しのビルドと GC root 登録を実測したが、
Nix が SSH を省略する特別な `localhost` 経路であり、VM 越しの実証ではない。
workbench は OCI A1 Flex の KVM ゲスト。2026-09-20 にホスト側でも
`/dev/kvm` が無く、kernel journal に `HYP mode not available` があることを
確認したため、現在のホストで KVM による追加 VM を動かす前提は満たせない。
カーネル共有を許容し、専用 OS ユーザーで本人の環境・権限から分離する方針とする。
native Podman を VM と同等とは扱わない。

### 専用ユーザーの入口

`modules/nixos/chelly-agent.nix` を workbench で有効にし、`chelly-agent` を追加する。
通常の `chelly` は変更せず、Emacs は `/srv/chelly-workspaces` 内の起動だけを専用入口に向ける。以下は設定適用後の手順であり、
実機での起動確認が済むまでは、自律作業環境全体の移行完了とは扱わない。

| 対象 | 専用環境での扱い |
| --- | --- |
| 実行ユーザー | `chelly-agent`。wheel・trusted Nix user にしない |
| home・Podman storage | `/var/lib/chelly-agent`、モード `0700` |
| 作業 clone | `/srv/chelly-workspaces` 以下。本人の clone と Git メタデータを共有しない |
| 本人からの閲覧 | `chelly-workspaces` グループ経由。親ディレクトリは `2750` で書き込み権限を渡さない |
| Nix store | ホストの store を read-only 共有。既存 proxy の専用グループ経由で接続 |
| Claude・Copilot の状態 | `.claude`・`.copilot` を専用ユーザーの Podman named volume に保存。本人の状態や brainium はマウントしない |
| Git ignore | Home Manager のルールを read-only で渡す。Git 設定全体・署名鍵は渡さない |
| 環境変数 | 呼び出し元の環境を捨て、端末情報と専用環境のパスだけを再設定 |

launcher は本人から専用ユーザーへの固定 runner だけを sudo で実行する。
runner は実行ユーザー、本人の home にアクセスできないこと、作業場所、
専用ユーザーの runtime directory を確認し、条件を満たさなければ停止する。
専用ユーザーには独立した subordinate UID/GID の範囲を割り当て、
`--userns=keep-id:uid=1000,gid=100` で workbench のイメージ内ユーザーへ対応させる。
Claude の設定先は `CLAUDE_CONFIG_DIR=/home/warashi/.claude` として明示する。

```sh
# ホスト側で NixOS 設定を適用し、グループ変更を反映するためログインし直す
just switch-for workbench

# 新しいログインセッションから。本人の普段の clone 内では起動しない
cd /srv/chelly-workspaces
chelly-agent config list
chelly-agent build &&
  chelly-agent run -- id &&
  chelly-agent run -- nix store info --json
```

ベースイメージは `docker.io/library/debian:stable` と完全修飾し、個人の
短縮名 alias や検索レジストリ設定に依存させない。`chelly-agent run` は
`--pull=never` で専用ユーザーがビルドしたローカルイメージだけを使う。
ビルドに失敗した場合はその原因を直してから `run` に進む。
`chelly:latest` が無い場合に同名の外部イメージを取得して代用しない。

作業用 clone は専用ユーザーの所有でこの領域に用意する。
本人の clone から `git worktree add` で作らない。
閲覧のためにホストの `safe.directory = "*"` を設定したり、
作業 clone の Git 設定・hooks を信頼する clone にコピーしたりしない。

成果は Git bundle 経由で commit の objects だけを本人の repo の remote-tracking
branch に受け取る。新規追跡ファイルの履歴検査には
[`git-check-new-ignored`](../git/handoff/README.md) を使う。
agent が変更した ignore ルールではなく、信頼する base と本人側のルールで判定する。
これは差分の確認や機密情報の検査全般を代替しない。署名は本人側の既存設定で行い、
署名鍵・socket は専用環境へ渡さない。検査コマンドは署名・取り込み・公開を自動実行しない。

agent の個人設定・skills・global hooks の選別した配布と private module の取得経路も未実装。

ホストでの受け入れ確認では、専用ユーザーが本人の home に入れないこと、
外側の Podman が rootless であること、コンテナ内の `nix store info --json` が
`"trusted":false` を返すこと、複数作業で store・cache を共用できること、
入れ子の Podman が動くことを確認する。runner と設定の回帰チェックは
`nix build .#checks.aarch64-linux.chelly-agent-config` で実行するが、実機確認の代わりではない。

既存ユーザーの Podman image・volume は移動・削除しない。新しい専用 storage での
image build は追加のディスクを使うが、ホストの Nix store 自体は複製しない。
公開先への送信制限、ディスク枯渇防止、並行する AI 同士の強い隔離は保証しない。

### 専用のモデル認証

workbench では `secrets/default.yaml` の SOPS キー `chelly-agent-dotenv` を
`/run/secrets/chelly-agent-dotenv` に復号し、`chelly-agent:chelly-agent` 所有・
モード `0400` で配置する。`hosts/workbench/chelly.nix` が
`warashi.chelly-agent.envfiles` にこのパスだけを指定する。
専用環境を無効化した場合は secret の配備と envfile の指定も外れる。
モジュール自体の envfiles の既定値は空のまま。

このキーの中身は dotenv 形式の複数行文字列とし、次の 2 変数だけを
本人が SOPS の編集画面で保存する。

- `CLAUDE_CODE_OAUTH_TOKEN`: `claude setup-token` で発行した token。
- `COPILOT_GITHUB_TOKEN`: Copilot Requests 専用の token。

値を会話・平文の Git ファイル・Nix 式・Nix store に置かない。
本人の既存 `chelly-dotenv` や Git 認証にはフォールバックせず、本人の
認証状態・署名鍵も共有しない。token はコンテナの環境変数として渡すため、
agent から読み出せる。持ち出しや利用枠の消費を防ぐ境界ではない。

専用コンテナには `IS_DEMO=1` も指定する。Claude Code 2.1.278 では
token で非対話のモデル応答が成功しても、初回の対話起動でログインを要求された。
[公式の環境変数](https://code.claude.com/docs/en/env-vars)で初回セットアップを
スキップすると対話でも応答できたため、追加ログインや内部の `.claude.json` の
直接編集は行わない。メールアドレス・組織名の表示も隠れる。
通常の `chelly` の起動設定や共通 Dockerfile にはこの指定を追加しない。
ツールの権限確認を無効化するフラグも追加しない。

ホスト側の configurations で次を実行する。envfile の追加・更新だけなら
image の再ビルドや再ログインは不要。更新は次に起動するコンテナから反映される。

```sh
just switch-for workbench &&
  sudo stat -Lc '%a %U:%G %n' /run/secrets/chelly-agent-dotenv &&
  cd /srv/chelly-workspaces &&
  chelly-agent run -- sh -c '
    : "${CLAUDE_CODE_OAUTH_TOKEN:?missing Claude token}"
    : "${COPILOT_GITHUB_TOKEN:?missing Copilot token}"
    echo model-tokens-present
  '
```

権限が `400 chelly-agent:chelly-agent` で、`model-tokens-present` が出れば
値を表示せずに注入を確認できる。`env` や `printenv` で値を表示しない。
これは認証成功の確認ではない。続いてホストの `/srv/chelly-workspaces` から
次を一つずつ起動し、それぞれ「ツールは使わず、この会話の目印
`chelly-resume-check-01` を会話の中だけで覚えて」と依頼する。
応答を確認したら CLI を終了し、ホストに戻る。

```sh
chelly-agent run -- claude
chelly-agent run -- copilot
```

次もホストの同じディレクトリから一つずつ起動する。既存コンテナ内で CLI を
起動し直すのではなく、`chelly-agent run` で新しいコンテナを作る。
確認中は同じ CLI で別の会話を始めない。

```sh
chelly-agent run -- claude --continue
chelly-agent run -- copilot --continue
```

それぞれ「ツールは使わず、前に伝えた会話の目印は何？」と尋ね、
目印をもう一度入力せずに答えられることと、以前の会話が表示されることを確認する。
Claude は初回ログインを求められずに進めること、Copilot も引き続き応答することを
確認する。これは CLI の会話保存の確認で、プロセスや一時ファイルの復元ではない。
ACP の新規会話／再開は別途確認する。通常の `chelly` と専用領域外の
Emacs の起動は変更しない。

### Emacs/ACP の専用検証入口

ホストの Emacs では `warashi-agent-shell-chelly-start` を使う。
通常の agent-shell の `("chelly" "run")` は変更しない。
専用入口は `chelly-agent run -- claude-agent-acp` または
`chelly-agent run -- copilot --acp` を起動し、buffer 名に `[chelly-agent]` を付ける。
ローカルの `/srv/chelly-workspaces` 以下に限定し、TRAMP や領域外へ向く
symlink は拒否する。起動後・再接続時も同じ専用 client-maker を使う。

ACP のファイル読み書き能力は無効として通知する。それだけでは上流の要求処理を
止められないため、専用セッションでは権限確認の UI 要求以外を実際に拒否する。
ファイル・端末操作、`session/push`、未知の要求は JSON-RPC エラーにし、
Emacs の `*Messages*` に拒否を表示する。agent 自身のコンテナ内ツールまで
無効化する設定ではない。ホストの認証 getter・MCP 設定・自動権限応答は使わない。
AI 所有の clone の dir-local variables は適用せず、Emacs の自動 transcript
保存も無効にする。会話は agent 側の専用 volume に保存する。
これは ACP のホスト操作委譲を制限する入口で、Emacs 全体のサンドボックスではない。
検証中はファイルの手動添付や agent が提示するリンクを開く操作は行わない。

新しい Emacs 設定を読み込んでから、ホストの Emacs で次を `M-:` から評価する。
既存の Emacs にこの入口だけを読み込む場合は、`M-x load-file` で
`applications/emacs/twist/packages/warashi-agent-shell/warashi-agent-shell-chelly.el`
を読み込めばよい。コンテナ image の再ビルドは不要。

```elisp
(let ((default-directory "/srv/chelly-workspaces/"))
  (warashi-agent-shell-chelly-start 'claude))
```

CLI と同じように、ツールを使わず会話の中だけで目印を覚えるよう依頼する。
応答後に **shell buffer 自体を kill** して接続を終了する。画面を閉じるだけでは
プロセスを終了したことにならない。その後、次を評価し、会話一覧から対象を選ぶ。

```elisp
(let ((default-directory "/srv/chelly-workspaces/"))
  (warashi-agent-shell-chelly-start 'claude t))
```

目印を再入力せずに回答できることで、会話の文脈が復元されたことを確認する。
固定した agent-shell の `agent-shell-session-restore-verbosity` は既定で
`minimal`。agent が `session/resume` をサポートしていれば、過去の発言を
再表示せずに再開するため、履歴の表示は成功条件に含めない。
履歴の再表示は `full` などの表示設定と agent の `session/load` 対応に依存し、
この専用入口では既定の表示設定を変更しない。
Copilot は上の `'claude` を `'copilot` に置き換えて同じ確認を行う。
作業領域の buffer からなら `M-x warashi-agent-shell-chelly-start`、
再開は `C-u M-x warashi-agent-shell-chelly-start` でも実行できる。
接続・認証・会話一覧取得が失敗したら、ホストのファイル能力や通常ログインを
追加して回避せず、token を伏せたエラーを確認する。

### 依頼から取り込みまで

専用の会話管理画面や取り込み画面は作らず、いつもの agent-shell と Magit を使う。
Git の受け渡しだけをホストの [`chelly-handoff`](../git/handoff/README.md) が補助し、
状態は本人の repo の remote `handoff-名前` だけに置く。

| 段階 | 操作 |
| --- | --- |
| clone 作成 | 本人の repo で基点の branch を checkout し、`chelly-handoff create [名前]`。名前の既定は branch 名 |
| 起動・対話 | `/srv/chelly-workspaces/<repo 名>/名前` で既存の `warashi-agent-shell-claude-*` / `copilot-*` を使う。会話は `C-c a` から開く |
| 受け取り | agent の作業が止まり、検証済みの**未署名 commit** が残ったら `chelly-handoff fetch [名前]` |
| 差分確認 | Magit で `handoff-名前/branch` の log・diff を見る。基点は `remote.handoff-名前.chelly-base` |
| 取り込み | Magit の cherry-pick や merge。既存設定で SSH 署名され、本人の hooks が動く |
| 後片付け | `chelly-handoff remove [名前]`。未取得の commit や未コミット変更があれば止まる |

`create` は現在の HEAD だけを bundle で渡し、専用ユーザーが `origin` も hooks も
持たない clone を作る。未コミット変更は転送しない。`fetch` は clone が clean で
基点より進んでいるときだけ bundle を受け取り、`git-check-new-ignored` で
新規追跡ファイルを検査する。検査に引っかかっても ref は残るので Magit で確認できるが、
取り込む前に agent に直させる。修正後は `fetch` を繰り返す。

専用領域内では同じ model・effort のまま `chelly-agent` を使い、領域外の通常起動は
変えない。Pi は専用 runner 非対応のため領域内では拒否する。
署名鍵・socket・本人の Git 設定は専用環境へ渡さず、agent の Git 設定・hooks も
本人側に持ち込まない。macOS/TRAMP、push・PR 作成は対象外。

### proxy socket に旧権限が残っている場合

`nix store info` が socket の `Permission denied` で止まったら、ホストで
`stat -c '%a %U:%G %n' /run/chelly-nix/socket` と
`systemctl cat chelly-nix-proxy.socket --no-pager` を比較する。
unit が `0660`・`chelly-agent` グループに更新済みなのに実体が旧 `0600` の場合は、
ほかの Nix ビルドが動いていないタイミングで次を実行する。

```sh
sudo systemctl daemon-reload &&
  sudo systemctl restart chelly-nix-proxy.socket &&
  stat -c '%a %U:%G %n' /run/chelly-nix/socket
```

`660 warashi:chelly-agent` を確認してから専用入口の Nix 接続を再試行する。
この不一致の解消に、image の再ビルド、Nix daemon 全体の再起動、`chmod 666` は不要。

## athena: Podman machine

複数の chelly から Nix store とビルドキャッシュを同時に使うため、
athena は `podman machine` の共有 Linux VM でコンテナを動かす。
`hosts/athena/homes/chelly.nix` で Podman を明示選択し、
CLI は共通の chelly モジュールで `isDarwin` の場合に `pkgs.podman` を導入する。
macOS 用パッケージには
VM 起動用の vfkit とネットワーク用の gvproxy も組み込まれている。
apple/container は比較・切り戻し用に残す。
コンテナ間は VM ではなく Linux の namespace で分離される。

### 初回セットアップ

athena 上で設定を適用した後、VM を一度だけ作る。既存の machine がある場合は
先に `podman machine list` と `podman system connection list` で状態を確認する。
初期化・起動は Home Manager の activation では行わない。

```sh
just switch-for athena
export CONTAINERS_MACHINE_PROVIDER=applehv
podman machine init --cpus 4 --memory 8192 \
  --rootful=false --volume "$HOME:$HOME" chelly
podman machine start chelly
podman system connection default chelly
podman info
chelly config get container_cmd
chelly build
```

固定した nixpkgs の Podman 5.8.6 では `--provider` と `--update-connection` は
使えない。プロバイダは `CONTAINERS_MACHINE_PROVIDER` で指定し、
`podman system connection default chelly` でこの VM の rootless 接続を既定にする。
CPU 4 個・メモリ 8 GiB はコンテナごとではなく VM 全体の割り当て。
rootless の接続を使い、VM 内の `id` とコンテナ内の `id` を確認する。
athena のイメージ内ユーザーは UID 501 / GID 1000 を前提にしている。

```sh
podman machine ssh chelly id
chelly run -- id
```

Podman の bind mount 元は VM 側のパスなので、リポジトリ、Git worktree の
共通ディレクトリ、追加マウント元は VM からも同じ絶対パスで見える必要がある。
ホーム外のリポジトリは、このホーム共有だけでは使えない。
ホーム全体ではなく共有範囲を限定する場合は、既定の追加マウント元である
`~/.claude`、`~/.copilot`、`~/.pi`、`~/.local/share/chelly`、
`~/ghq/github.com/Warashi/brainium` と、利用する worktree のディレクトリも共有する。

`~/.config/git/ignore` は Home Manager が Mac の `/nix/store` へのリンクとして
生成するため、activation で `~/.local/share/chelly/git-ignore` に実体を
read-only（モード `0444`）で配置する。内容の更新も activation で行う。
コンテナにはその実体を渡し、Mac の `/nix` は共有しない。
その他の追加マウントにホーム外へのリンクを足す場合も、VM からの解決を確認する。
Dockerfile も Nix store へのリンクなので、Podman の build には `--file` で
実体のパスを指定する。Mac 側の CLI がファイルを VM に転送するため、
VM から Mac の Nix store をマウントする必要はない。

### 起動・停止とデータ

```sh
# 作業開始時
export CONTAINERS_MACHINE_PROVIDER=applehv
podman machine start chelly
podman system connection default chelly

# 全コンテナの作業が終わった後
podman ps
podman machine stop chelly
```

VM は自動起動・自動停止しない。停止は実行中の全コンテナに影響するため、
エージェントやビルドが残っている間は行わない。

`chelly-nix`、`nix-cache`、`go-cache`、`go-mod` は VM 内の Podman named volume
として共有され、コンテナ終了や VM 停止後も残る。Apple 側の同名 volume とは
別物なので、初回は空のキャッシュから始まる。Apple 側のデータは削除しない。
`podman machine rm` や volume の削除はキャッシュと Nix store を失うため行わない。

共有 `/nix` の初期インストールは entrypoint の `flock` で直列化する。
コンテナごとに見えるプロセスと GC root が異なるため、各コンテナから
`nix store gc` や `nix-collect-garbage` は実行しない。
共有 store の GC 運用は、この移行では扱わない。

### Mac 実機での受け入れ確認

同じ VM のまま、別ターミナルから二つの `chelly run` を同時に動かす。
次を満たしてから通常利用へ移す。

- 両方が起動し、`podman inspect` で同じ named volume の利用を確認できる。
- 一方が動いたまま他方も `nix develop` とビルドを実行できる。
- Go のプロジェクトでは両方からビルドでき、キャッシュを再利用できる。
- コンテナから編集したファイルを Mac で読み書きでき、所有者が変わらない。
- Git worktree と追加マウント先の設定ファイルを両方から読める。
- chelly 内で `podman run --rm docker.io/library/alpine:latest true` が成功する。
- VM を停止・再起動した後も named volume の内容を使える。

設定の回帰チェックは `nix build .#checks.<system>.chelly-config` で実行する。
これはランタイム選択、共有マウント、Git ignore の実体配置の設定と、
remote build の Dockerfile 指定、workbench の既存設定の維持を検査するもので、
Mac 実機の動作確認の代わりではない。

Podman インストールの有無 (Darwin では入る/Linux では入らない) だけは、
host の完全な設定 (athena/workbench の `config`) を辿らず、chelly の
home-manager モジュールと対応する `hosts/*/homes/chelly.nix` だけを
取り込んだ最小構成で評価する。host 全体をたどると emacs-twist 等の
無関係なパッケージまで評価されて Darwin 向け IFD ビルドを要求してしまい、
aarch64-linux では `nix flake check` が失敗するため。この最小構成での
評価は、Darwin ホスト全体のビルドを Linux 上で検証したことを意味しない。

切り戻し時は `CHELLY_CONTAINER_CMD=container chelly run` で既存の Apple 側
イメージ・volume を使える。ただし、元の named volume の同時利用制約も戻る。

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
| Claude・Copilot の状態 | `.claude`・`.copilot` を専用ユーザーの Podman named volume に保存。本人の状態はマウントせず、Nix が生成する設定だけを起動時に写す |
| brainium | 本人の clone はマウントしない。`/srv/chelly-workspaces/brainium` を `~/ghq/github.com/Warashi` に見せ、そこに置いた handoff clone を本人と同じ path で使う |
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
短縮名 alias や検索レジストリ設定に依存させない。

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

Claude/Copilot の設定は、本人の home-manager が `~/.claude` と `~/.copilot` に書く生成物
(CLAUDE.md、settings の override、output-styles、skills、copilot-instructions.md) を
`warashi.claude.bundle` と `warashi.copilot.bundle` で束ね、専用入口の `podman run` に
`CHELLY_AGENT_CONFIG` として store path で渡す。image の entrypoint がそれを volume へ写し、
settings は volume にある runtime の値を残して override を重ねる。認証状態・履歴・
host の runtime にある `extraSettingsSources` は含めない。設定を変えたら switch と
次回のコンテナ起動で反映され、image の再 build は要らない。global hooks の配布と
private module の取得経路は未実装。

brainium は本人の CLAUDE.md が `~/ghq/github.com/Warashi/brainium` を指すので、
説明を書き分けずに済むよう handoff clone を同じ path に見せる。本人の brainium で
`chelly-handoff create brainium` を一度実行すると `/srv/chelly-workspaces/brainium/brainium`
に clone ができ、コンテナ内では `~/ghq/github.com/Warashi/brainium` になる。
clone が無ければ path は空で、agent は本人に create を依頼する。mount 元の `/srv/chelly-workspaces/brainium` は podman が作らないので runner が毎回用意する。project の clone と違い
長く置いて使い、agent の capture は `chelly-handoff fetch brainium` で受け取り Magit で
取り込む。本人の brainium が進んだら `chelly-handoff update brainium` で clone を本人の
main の先端に合わせ直す。update は未取得の commit や未コミット変更があれば止まるので、
日常は「agent が capture → `fetch brainium` → Magit で範囲を cherry-pick → `update brainium`」の
3 手になる。brainium も本人の署名で取り込む。

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
workbench の通常の `chelly` の起動設定や共通 Dockerfile にはこの指定を追加しない
(athena は `chelly` 自体が専用構成なので付く)。
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
専用 clone では project 名を `<repo 名> / <handoff 名>` にし、一覧や header で
どの repo の作業か分かるようにする。
ローカルの `/srv/chelly-workspaces` (macOS は `~/chelly-workspaces`) 以下に限定し、TRAMP や領域外へ向く
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
Emacs では本人の repo の Magit で `@` を押すと各操作の transient が開き
(`c` create、`f` fetch、`u` update、`k` remove)、名前は remote から選べる。
`fetch` の後は `基点..handoff-名前/branch` の log が開くので、そのまま取り込める。

| 段階 | 操作 |
| --- | --- |
| clone 作成 | 本人の repo で基点の branch を checkout し、`chelly-handoff create [名前]`。名前の既定は branch 名 |
| 起動・対話 | `/srv/chelly-workspaces/<repo 名>/名前` (macOS は `~/chelly-workspaces/…`) で既存の `warashi-agent-shell-claude-*` / `copilot-*` を使う。会話は `C-c a` から開く |
| 受け取り | agent の作業が止まり、検証済みの**未署名 commit** が残ったら `chelly-handoff fetch [名前]`。agent が branch を切っていても HEAD までを拾う |
| 差分確認 | Magit で `handoff-名前/branch` の log・diff を見る。branch は agent が HEAD を置いていた branch 名 (detached なら create 時の branch)。基点は `remote.handoff-名前.chelly-base` |
| 取り込み | Magit の log で `基点..handoff-名前/branch` の region を選んで `A A` (範囲の cherry-pick)。commit 数に関わらず 1 回で、既存設定で SSH 署名され、本人の hooks が動く。署名が要らない repo なら `git merge --ff-only` でもよい |
| 追従 | 本人側が進んだら `chelly-handoff update [名前]`。未取得の commit や未コミット変更があれば止まる。clone は create 時の branch に戻り、agent が切った branch は消える |
| 後片付け | `chelly-handoff remove [名前]`。未取得の commit や未コミット変更があれば止まる |

`create` は現在の HEAD だけを bundle で渡し、専用ユーザーが `origin` も hooks も
持たない clone を作る。未コミット変更は転送しない。`fetch` は clone が clean で
基点より進んでいるときだけ bundle を受け取り、`git-check-new-ignored` で
新規追跡ファイルを検査する。検査に引っかかっても ref は残るので Magit で確認できるが、
取り込む前に agent に直させる。修正後は `fetch` を繰り返す。

専用領域内では同じ model・effort のまま `chelly-agent` を使い、領域外の通常起動は
変えない。Pi は専用 runner 非対応のため領域内では拒否する。
署名鍵・socket・本人の Git 設定は専用環境へ渡さず、agent の Git 設定・hooks も
本人側に持ち込まない。TRAMP、push・PR 作成は対象外。macOS は下の athena 節。

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

## athena: 専用領域だけを共有する Podman machine

athena は `podman machine` の共有 Linux VM でコンテナを動かす。
`hosts/athena/homes/chelly.nix` で Podman を明示選択し、
CLI は共通の chelly モジュールで `isDarwin` の場合に `pkgs.podman` を導入する。
macOS 用パッケージには VM 起動用の vfkit とネットワーク用の gvproxy も組み込まれている。
apple/container は比較・切り戻し用に残す。コンテナ間は VM ではなく Linux の namespace で分離される。

### 境界: VM に共有する範囲

macOS には別の OS ユーザーも sudo の入口も無いので、workbench の専用ユーザーの代わりに
**Podman machine に共有するディレクトリ**を境界にする。`warashi.chelly.dedicated = true`
(`dedicated.nix`) で `chelly` 自体が専用構成になり、別入口は作らない。
`chelly-agent` は `chelly` へ exec するだけの wrapper で、`chelly-handoff` と Emacs の
専用入口から同じ名前で呼べるようにするためにある。

| 対象 | 専用構成での扱い |
| --- | --- |
| VM に共有するもの | `~/chelly-workspaces` (専用 clone) と `~/.local/share/chelly` (git-ignore と設定 bundle の実体)、Home Manager の podman モジュールが足す `~/.config/containers` (podman の設定、認証情報は含まない) だけ。home 全体・`~/.claude`・`~/.copilot`・`~/ghq` は共有しない |
| 作業 clone | `~/chelly-workspaces/<repo 名>/<名前>`。`chelly-handoff create` で作る。本人の clone を直接 mount する経路は無い |
| Claude・Copilot の状態 | `claude-state`・`copilot-state` の named volume。本人の `~/.claude`・`~/.copilot` は mount しない |
| 設定の配布 | `warashi.claude.bundle`・`warashi.copilot.bundle` を activation で `~/.local/share/chelly/agent-config` に実体として写し、同じ path に read-only で bind mount して `CHELLY_AGENT_CONFIG` で渡す。Mac の `/nix` は VM に無いので store path は渡せない。mount が無いと entrypoint は黙って何も写さない |
| モデル認証 | Home Manager の sops secret `chelly-agent-dotenv` だけ。本人の `chelly-dotenv` は使わない。`--env-file` は Mac 側の podman client が読むので VM に共有しなくてよい |
| brainium | 本人の clone は mount しない。`~/chelly-workspaces/brainium` をコンテナの `~/ghq/github.com/Warashi` に見せ、`chelly-handoff create brainium` で作った clone を使う。mount 元は `chelly-agent` が起動ごとに作る。`remove brainium` は親ごと消すので、その直後は素の `chelly run` ではなく `chelly-agent run` を使う |
| Git ignore | 従来どおり `~/.local/share/chelly/git-ignore` の実体を read-only で渡す |
| userns | athena の既存 `--userns=keep-id` のまま (イメージ内ユーザーは UID 501 / GID 1000) |

コンテナを抜けて VM の `core` ユーザーになっても、届くのは上の共有範囲、named volume、
コンテナに渡した限定 token に限る。SSH 鍵・1Password・署名設定・他の repository には届かない。
Emacs の ACP 経路は `warashi-agent-shell-chelly.el` が host 要求を拒否するので、
VM の共有範囲を絞っても Emacs 経由で home を触られることはない。
公開先への送信制限、ディスク枯渇防止、並行する AI 同士の強い隔離は保証しない。

専用領域の外 (本人の clone など) で `chelly run` すると、VM に無い cwd を bind mount
しようとして podman が statfs のエラー (exit 125) で止まる。これは想定どおりで、
`chelly-handoff create` で専用領域に clone を作ってから起動する。

通常入口を別に残さないのは、本人の clone を直接 mount する経路を残すと `~/ghq` を VM に
共有することになり、agent が本人の clone の `.git` (hooks・config) を書き換えて次の
`git` 実行で host 上のコードが動く経路が開くため。Claude/Copilot を chelly の外で使わない
以上、本人の `~/.claude` を共有する理由も無い。

### 初回セットアップ

machine は Home Manager の `services.podman.machines.chelly` (`dedicated.nix`) が宣言し、
switch 時の activation が **無いときだけ** `podman machine init` する。CPU 4 個・メモリ 8 GiB
(VM 全体の割り当て)・rootless・共有は上の 2 ディレクトリと podman の設定ディレクトリ
`~/.config/containers` だけ。provider は containers.conf の `[machine] provider = "applehv"` で
指定するので `CONTAINERS_MACHINE_PROVIDER` の export は要らない。
`/Users` を丸ごと共有する既定 machine (`useDefaultMachine`) と、停止しても起動し直す
launchd の watchdog (`autoStart`) は無効にしてある。

`podman machine set` (固定版 5.8.6) は volume を変えられず、activation も既存 machine は
触らない。home 全体を共有していた旧 `chelly` machine は、switch の前に本人が消す。
VM 内の named volume (`chelly-nix`・`nix-cache`・`go-cache`・`go-mod`) は machine と
一緒に消え、初回は空のキャッシュから始まる。activation は宣言に無い machine も
`machine rm -f` するので、名前を変えた machine を残さない。

```sh
podman ps && podman machine stop chelly && podman machine rm chelly
just switch-for athena            # activation が chelly を init する
podman machine inspect chelly --format '{{json .Mounts}}'
podman machine start chelly
podman system connection list     # chelly の rootless 接続が既定でなければ default にする
podman system connection default chelly
chelly build
```

`inspect` の Mounts が `~/chelly-workspaces`・`~/.local/share/chelly`・`~/.config/containers`
の 3 つだけであることを確認する。固定した nixpkgs の Podman 5.8.6 では `--provider` と
`--update-connection` は使えない。init が既定接続を切り替えるかは実機で確認し、
切り替わらなければ `podman system connection default chelly` を一度実行する。

`~/chelly-workspaces` と `~/.local/share/chelly` は switch 時の activation が作る。
Dockerfile も Nix store へのリンクなので、Podman の build には `--file` で
実体のパスを指定する。Mac 側の CLI がファイルを VM に転送するため、
VM から Mac の Nix store をマウントする必要はない。

### athena での依頼から取り込みまで

workbench と同じ `chelly-handoff` と Magit の手順を使う (上の「依頼から取り込みまで」)。
作業領域は `~/chelly-workspaces` で、`chelly-handoff` は Nix の `warashi.chelly.workspaces`
から既定を受け取る。Emacs の `warashi-chelly-workspace-root` も macOS では同じ既定になる。
専用領域内での Emacs の起動は通常の `warashi-agent-shell-claude-*` / `copilot-*` を使う。
署名は Mac 側の 1Password の signer のまま、本人が範囲の cherry-pick で行う。

### 起動・停止とデータ

```sh
# 作業開始時
podman machine start chelly

# 全コンテナの作業が終わった後
podman ps
podman machine stop chelly
```

VM は自動起動・自動停止しない (`autoStart = false`)。停止は実行中の全コンテナに影響するため、
エージェントやビルドが残っている間は行わない。

`chelly-nix`、`nix-cache`、`go-cache`、`go-mod`、`claude-state`、`copilot-state` は
VM 内の Podman named volume として共有され、コンテナ終了や VM 停止後も残る。
Apple 側の同名 volume とは別物で、Apple 側のデータは削除しない。
セットアップ後に `podman machine rm` や volume の削除を行うとキャッシュ・Nix store・
agent の会話を失う。

共有 `/nix` の初期インストールは entrypoint の `flock` で直列化する。
コンテナごとに見えるプロセスと GC root が異なるため、各コンテナから
`nix store gc` や `nix-collect-garbage` は実行しない。
共有 store の GC 運用は、この移行では扱わない。

### Mac 実機での受け入れ確認

次を満たしてから通常利用へ移す。

- `podman machine inspect` の Mounts が `~/chelly-workspaces`・`~/.local/share/chelly`・`~/.config/containers` だけ。
  `podman machine list` に `podman-machine-default` が無い。
  `podman machine ssh chelly ls ~/.claude ~/ghq` が失敗する。
- `chelly-handoff create` → 専用 clone で `chelly run -- claude` / `copilot` → `fetch` → `remove`
  の一巡が通り、受け取った commit が未署名である。
- `chelly run -- sh -c 'echo ${CLAUDE_CODE_OAUTH_TOKEN:?} >/dev/null && echo ok'` で
  値を表示せずに専用 token の注入を確認できる。`~/.claude` はコンテナに無く、
  `CLAUDE.md` と output-styles は volume に写っている。
- 会話の再開が `chelly run -- claude --continue` と Emacs の `C-u M-x warashi-agent-shell-chelly-start`
  で通る (workbench の手順と同じ)。
- 同じ VM のまま、別ターミナルから二つの `chelly run` を同時に動かし、
  `podman inspect` で同じ named volume を使い、一方が動いたまま他方も `nix develop` とビルドを実行できる。
- コンテナから専用 clone に書いたファイルを Mac の Emacs で読み書きでき、所有者が変わらない。
  handoff の agent 側 script は `GIT_CONFIG_GLOBAL=/dev/null` で Dockerfile の
  `safe.directory` を無効にしているので、virtiofs の所有者が揺れると `create` の clone や
  `status` が dubious ownership で落ちる。起きたら直すのは handoff script 側で、Dockerfile ではない。
- Emacs の専用入口で host のファイル要求が `*Messages*` に拒否として出る。
- chelly 内で `podman run --rm docker.io/library/alpine:latest true` が成功する。
- VM を停止・再起動した後も named volume の内容を使える。

`chelly-handoff` の python テストは Linux 以外では skip されるので、athena での
package build は handoff の動作を検査しない。

設定の回帰チェックは `nix build .#checks.<system>.chelly-config` で実行する。
これはランタイム選択、共有マウント、Git ignore と設定 bundle の実体配置、
専用 token・volume・brainium の見せ方、workbench の既存設定の維持を検査するもので、
Mac 実機の動作確認の代わりではない。

Podman インストールの有無 (Darwin では入る/Linux では入らない) だけは、
host の完全な設定 (athena/workbench の `config`) を辿らず、chelly の
home-manager モジュールと対応する `hosts/*/homes/chelly.nix` だけを
取り込んだ最小構成で評価する。host 全体をたどると emacs-twist 等の
無関係なパッケージまで評価されて Darwin 向け IFD ビルドを要求してしまい、
aarch64-linux では `nix flake check` が失敗するため。この最小構成での
評価は、Darwin ホスト全体のビルドを Linux 上で検証したことを意味しない。

切り戻し時は `CHELLY_CONTAINER_CMD=container chelly run` で既存の Apple 側
イメージ・volume を使える。ただし、元の named volume の同時利用制約も戻り、
apple/container は home 全体を共有するので上の境界にはならない。

## macOS: private Go module の取得

仕事の Mac の専用構成 (`warashi.chelly.dedicated`) で、agent が private Go module を
本人の認証なしで取得・更新できるようにする。実装は `go-proxy/`。

| 項目 | 内容 |
| --- | --- |
| 取得 | Mac 上の `chelly-go-proxy` (本人の launchd agent、`127.0.0.1:3140`) が、本人の `go`・`git` と Git 認証で VCS から直接取得する |
| 許可 | `warashi.chelly.goProxy.allow` の pattern (GOPRIVATE と同じ書式) に一致する module だけ。一致しない path では go も git も呼ばずに 404 を返す |
| コンテナ | `GOPROXY=http://host.containers.internal:3140,https://proxy.golang.org` と、許可 pattern の `GONOSUMDB` だけを渡す。`GOPRIVATE` は渡さない (proxy を迂回して認証の無い direct 取得になる) |
| 状態 | proxy 専用の module cache は `~/.cache/chelly-go-proxy`、ログは `~/Library/Logs/chelly-go-proxy.log`。どちらも VM に共有しない |

許可リストは configurations を input に持つ private flake の host 設定で与える。社内の
repository 名を公開の configurations に書かないため。

```nix
warashi.chelly.goProxy.allow = [
  "github.com/<org>/<repo>"
];
```

新しい private repository が必要になると、agent の `go` は proxy の 404 の後に
proxy.golang.org でも失敗して止まる。go が表示するのは最後の proxy.golang.org の
`could not read Username for 'https://github.com'` と「private repository なら」の案内で、
proxy の「not in the allowed module list」は出ない。本人が内容を確認し、private flake の
許可リストに足して switch する。
許可から外した module も、次の要求からは go を呼ばずに 404 になる。コンテナ内の
`go-mod` volume に既に取得済みの分は残る。

`GOPROXY` の区切りは `,` なので、go が次の proxy に進むのは 404/410 のときだけ。
launchd agent が止まっていて接続できないと、公開 module を含めてコンテナ内の取得が
すべて失敗する。そのときは下の `launchctl print` で state を見る。

守らないもの:

- 許可しない module path がコンテナから proxy.golang.org や sum.golang.org に問い合わせられること。
  許可した module でも、取得に失敗した path と version は proxy.golang.org に流れる。
  コンテナの外向き通信は制限していない。
- private module の新しい version の改ざん検出。sumdb の対象外なので、本人が普段 `GOPRIVATE`
  で取得するときと同じく、取得元の Git と HTTPS を信頼する。取得済みの version は repository の
  `go.sum` が検出する。
- NixOS (workbench) は対象外で、有効にすると assertion で止まる。

### Mac 実機での受け入れ確認

switch 後に次を確かめる。`<mod>` は許可した module、`<other>` は本人が読めるが許可していない
private module。

```sh
launchctl print gui/$(id -u)/org.nix-community.home.chelly-go-proxy | grep state
curl -s http://127.0.0.1:3140/<mod>/@v/list        # version が並ぶ
curl -s http://127.0.0.1:3140/<other>/@v/list      # not in the allowed module list
chelly-agent run -- curl -s http://host.containers.internal:3140/<mod>/@v/list
```

- コンテナから `host.containers.internal:3140` に届く。届かなければ Podman machine の
  host への経路 (gvproxy の host gateway) を確かめ、`go-proxy/default.nix` の宛先を直す。
- 専用 clone の Go repository で `go mod download` と `go get -u <mod>` が通り、
  `~/.cache/chelly-go-proxy` に取得した module が増える。
- `<other>` を import した状態の `go mod download` が失敗し、`~/.cache/chelly-go-proxy` に
  `<other>` が無い。
- 許可から外して switch した後、取得済みだった module の `@v/list` も 404 になる。

設定の検査は `nix build .#checks.<system>.chelly-go-proxy-config`、proxy 本体のテストは
`.#checks.<system>.chelly-go-proxy` で実行する。どちらも Mac 実機の確認の代わりではない。

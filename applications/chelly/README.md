# chelly

## athena: Podman machine

複数の chelly から Nix store とビルドキャッシュを同時に使うため、
athena は `podman machine` の共有 Linux VM でコンテナを動かす。
`hosts/athena/homes/chelly.nix` で Podman を明示選択し、
CLI は Homebrew で管理する。apple/container は比較・切り戻し用に残す。
コンテナ間は VM ではなく Linux の namespace で分離される。

### 初回セットアップ

athena 上で設定を適用した後、VM を一度だけ作る。既存の machine がある場合は
先に `podman machine list` と `podman system connection list` で状態を確認する。
初期化・起動は Home Manager の activation では行わない。

```sh
just switch-for athena
podman machine init --provider applehv --cpus 4 --memory 8192 \
  --rootful=false --volume "$HOME:$HOME" chelly
podman machine start --update-connection chelly
podman info
chelly config get container_cmd
chelly build
```

`--update-connection` は Mac の Podman の既定接続先をこの VM に変更する。
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

`~/.config/git/ignore` は Home Manager が Mac の `/nix/store` へのリンクとして
生成するため、activation で `~/.local/share/chelly/git-ignore` に実体を配置する。
コンテナにはその実体を渡し、Mac の `/nix` は共有しない。
その他の追加マウントにホーム外へのリンクを足す場合も、VM からの解決を確認する。
Dockerfile も Nix store へのリンクなので、Podman の build には `--file` で
実体のパスを指定する。Mac 側の CLI がファイルを VM に転送するため、
VM から Mac の Nix store をマウントする必要はない。

### 起動・停止とデータ

```sh
# 作業開始時
podman machine start --update-connection chelly

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

切り戻し時は `CHELLY_CONTAINER_CMD=container chelly run` で既存の Apple 側
イメージ・volume を使える。ただし、元の named volume の同時利用制約も戻る。

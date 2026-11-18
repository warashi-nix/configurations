#!/usr/bin/env bash
# chelly run の前に、同じ handoff 名の専用 clone を集めて本人と同じ ghq の path に mount する。
# 設定は Nix の wrapper が HANDOFF_SESSION_* で渡す。chelly には渡さない。
#   HANDOFF_SESSION_WORKSPACES  専用領域
#   HANDOFF_SESSION_MOUNTS      chelly の設定にある additional_mounts (カンマ区切り)
#   HANDOFF_SESSION_FIXED       設定で常に mount する clone (改行区切り)
#   HANDOFF_SESSION_CHELLY      本体の chelly
#   HANDOFF_SESSION_DIRECTORY   --handoff のときに起動する clone
#   HANDOFF_SESSION_BUSY_WAIT   使用中の clone が空くのを待つ秒数 (既定 10)
set -euo pipefail

usage() {
	echo "usage: chelly [--handoff NAME] run [-- command [args...]]" >&2
	exit 2
}

fail() {
	echo "chelly: $*" >&2
	exit 1
}

workspaces=$HANDOFF_SESSION_WORKSPACES
base_mounts=$HANDOFF_SESSION_MOUNTS
fixed_list=$HANDOFF_SESSION_FIXED
chelly=$HANDOFF_SESSION_CHELLY
session_directory=$HANDOFF_SESSION_DIRECTORY
busy_wait=${HANDOFF_SESSION_BUSY_WAIT:-10}
unset HANDOFF_SESSION_WORKSPACES HANDOFF_SESSION_MOUNTS HANDOFF_SESSION_FIXED HANDOFF_SESSION_CHELLY \
	HANDOFF_SESSION_DIRECTORY HANDOFF_SESSION_BUSY_WAIT

# default branch の名前は参加 repo を表さないので集めない。
excluded_names=(main master)

is_excluded_name() {
	local excluded
	for excluded in "${excluded_names[@]}"; do
		[[ $1 == "$excluded" ]] && return 0
	done
	return 1
}

name=
# cobra の補完 (__complete ARGS... 入力中の語) のうち、本体が知らない --handoff の部分を受ける。
completing=
if [[ ${1:-} == __complete || ${1:-} == __completeNoDesc ]] && [[ ${2:-} == --handoff && $# -ge 3 ]]; then
	completing=$1
	shift 2
	if [[ $# -ge 3 && $2 == run ]]; then
		exec "$chelly" "$completing" "${@:2}"
	fi
elif [[ ${1:-} == --handoff ]]; then
	[[ $# -ge 3 && -n $2 && $3 == run ]] || usage
	name=$2
	shift 2
	# 計画は brainium の task で立てるので、横断セッションは cwd に関わらずそこで動かす。
	cd -- "$session_directory" || fail "cannot enter $session_directory"
fi
[[ -n $completing || ${1:-} == run ]] || exec "$chelly" "$@"

# 4 は ShellCompDirectiveNoFileComp。
if [[ -n $completing && $# -ge 2 ]]; then
	[[ $# -eq 2 && run == "$2"* ]] && echo run
	echo :4
	exit 0
fi
if ! root=$(cd -P -- "$workspaces" 2>/dev/null && pwd -P); then
	# 専用領域が無いホストでも、補完は候補が無いだけにする。
	[[ -n $completing ]] || fail "cannot enter $workspaces"
	echo :4
	exit 0
fi
fixed=()
while IFS= read -r path; do
	[[ -n $path ]] || continue
	fixed+=("$(cd -P -- "$path" 2>/dev/null && pwd -P || echo "$path")")
done <<<"$fixed_list"

is_fixed() {
	local path
	for path in "${fixed[@]}"; do
		[[ $1 == "$path" ]] && return 0
	done
	return 1
}

# 設定で常に mount する project は、別の clone を集めると同じ destination に重なる。
is_fixed_project() {
	local path
	for path in "${fixed[@]}"; do
		[[ $path == "$root/$1"/* ]] && return 0
	done
	return 1
}

# clone は .git を持つ最初のディレクトリで、その中には下りない。find は symlink を辿らず、
# -type d は symlink に一致しないので、専用領域の外にある clone は集まらない。
list_clones() {
	find "$root" -mindepth 2 \( -name .git -prune \) -o \
		\( -type d -exec test -e '{}/.git' ';' -prune -print0 \)
}

mounts=()
# 書き込む clone。集めた clone と cwd の clone で、設定で常に mount する clone は除く。
targets=()

add_target() {
	local target
	is_fixed "$1" && return
	for target in "${targets[@]}"; do
		[[ $1 == "$target" ]] && return
	done
	targets+=("$1")
}

# cwd を含む clone は、領域の root から下りて最初に .git を持つディレクトリ。
cwd_clone() {
	local dir path component
	local -a components
	dir=$(pwd -P)
	[[ $dir == "$root"/?* ]] || return 0
	path=$root
	IFS=/ read -r -a components <<<"${dir#"$root"/}"
	for component in "${components[@]}"; do
		path=$path/$component
		if [[ -e $path/.git ]]; then
			add_target "$path"
			return
		fi
	done
}

# 他のコンテナが mount している clone を busy に集める。
# 単独起動は cwd を mount するので、clone の下のディレクトリもその clone の使用にあたる。
find_busy_targets() {
	local ids source target
	busy=()
	((${#targets[@]})) || return 0
	ids=$(podman ps --quiet) || fail "cannot list running containers to check workspaces in use"
	[[ -n $ids ]] || return 0
	while IFS= read -r source; do
		[[ $source == /* ]] || continue
		source=$(realpath -m -- "$source")
		for target in "${targets[@]}"; do
			if [[ $source == "$target" || $source == "$target"/* ]]; then
				busy+=("$target")
			fi
		done
	done < <(
		# shellcheck disable=SC2086  # ID は空白区切りの一覧として渡す
		podman inspect --format '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' $ids
	)
}

# 同じ clone に複数の agent が書かないよう、他のコンテナが mount している clone では起動しない。
# agentel の /clear と /resume は古い agent を止めてすぐ起動し直すが、コンテナは agent が
# 終わった後で消えるので、空くまで少し待つ。
refuse_busy_targets() {
	local deadline=$((SECONDS + busy_wait))
	local -a busy
	while find_busy_targets && ((${#busy[@]})); do
		((SECONDS < deadline)) ||
			fail "workspace in use by another container: $(printf '%s\n' "${busy[@]}" | sort -u | tr '\n' ' ')"
		sleep 0.5
	done
}

# CLONE の ghq の path を project に入れる。ghq の path は host/path の 2 段以上で、
# 1 段のものは <repo 名>/<ID> の旧配置なので mount 先が無い。
clone_project() {
	project=${1#"$root"/}
	project=${project%/*}
	[[ $project == */* ]]
}

# 起動時に集める名前を、入力中の PREFIX で絞って「名前<TAB>repo の一覧」で並べる。
complete_names() {
	local prefix=$1 described=$2 clone entry projects line joined
	local -A found=()
	while IFS= read -r -d '' clone; do
		clone_project "$clone" || continue
		is_fixed_project "$project" && continue
		entry=$(chelly-handoff name "${clone##*/}" 2>/dev/null) || continue
		[[ $entry == "$prefix"* ]] || continue
		is_excluded_name "$entry" && continue
		found[$entry]+="$project"$'\n'
	done < <(list_clones)
	for entry in "${!found[@]}"; do
		if [[ -z $described ]]; then
			printf '%s\n' "$entry"
			continue
		fi
		projects=$(LC_ALL=C sort <<<"${found[$entry]%$'\n'}")
		joined=
		while IFS= read -r line; do
			joined+="${joined:+, }$line"
		done <<<"$projects"
		printf '%s\t%s\n' "$entry" "$joined"
	done | LC_ALL=C sort
	echo :4
}

if [[ -n $completing ]]; then
	complete_names "$1" "$([[ $completing == __complete ]] && echo yes)"
	exit 0
fi

if [[ -n $name ]] && is_excluded_name "$name"; then
	echo "chelly: '$name' is a default branch name; starting a single session" >&2
	name=
fi
if [[ -n $name ]]; then
	id=$(chelly-handoff id "$name") || fail "invalid handoff name '$name'"
	while IFS= read -r -d '' clone; do
		[[ ${clone##*/} == "$id" ]] || continue
		clone_project "$clone" || continue
		if is_fixed_project "$project"; then
			echo "chelly: $clone is not mounted; $project is always mounted from its own clone" >&2
			continue
		fi
		mounts+=("$clone:/home/warashi/ghq/$project")
		add_target "$clone"
	done < <(list_clones)
	((${#mounts[@]})) || fail "no workspace named '$name' under $root"
fi
cwd_clone
refuse_busy_targets

if ((${#mounts[@]})); then
	extra=$(
		IFS=,
		echo "${mounts[*]}"
	)
	export CHELLY_ADDITIONAL_MOUNTS="$base_mounts,$extra"
fi
exec "$chelly" "$@"

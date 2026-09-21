#!/bin/sh

set -eu

dockerfile="$1"
work="$2"
real_nix="$3"
system="$4"
entrypoint="${work}/chelly-entrypoint"

mkdir -p "${work}"
extract_file() {
  awk -v target="$1" '
    $1 == "COPY" && $NF == target {
      found = 1
      next
    }
    found && /^EOF$/ {
      exit
    }
    found {
      print
    }
  ' "${dockerfile}" >"$2"
  test -s "$2"
}

extract_file /home/warashi/.local/bin/chelly-entrypoint "${entrypoint}"
extract_file /home/warashi/.local/bin/chelly-apply-agent-config "${work}/chelly-apply-agent-config"
chmod +x "${work}/chelly-apply-agent-config"
extract_file /etc/chelly/AGENTS.md "${work}/container-instructions"
grep -Fxq 'RUN ln -s /etc/chelly/AGENTS.md /etc/claude-code/CLAUDE.md' "${dockerfile}"
chmod +x "${entrypoint}"

expect_output() {
  if [ "$(cat "$1")" != "$2" ]; then
    printf 'Unexpected output in %s; expected:\n%s\nActual:\n' "$1" "$2" >&2
    cat "$1" >&2
    exit 1
  fi
}

make_agent() {
  cat >"$1/agent" <<'EOF'
#!/bin/sh
printf '%s' "${COPILOT_CUSTOM_INSTRUCTIONS_DIRS-}" >instruction-dirs
printf 'ACP response'
for argument in "$@"; do
  printf ' <%s>' "${argument}"
done
printf '\n'
EOF
  chmod +x "$1/agent"
}

run_mock_case() {
  name="$1"
  expected_stdout="$2"
  expected_stderr="$3"
  shift 3
  case_dir="${work}/${name}"
  mkdir -p "${case_dir}/bin" "${case_dir}/home"
  if [ "${name}" != no-flake ]; then
    printf '%s\n' "${name}" >"${case_dir}/flake.nix"
  fi
  make_agent "${case_dir}/bin"
  if [ "${name}" = shell-nix ] || [ "${name}" = broken-shell-nix ]; then
    touch "${case_dir}/shell.nix"
  fi

  cat >"${case_dir}/bin/nix" <<EOF
#!/bin/sh
case "\$1" in
  config) printf '%s\n' "${system}" ;;
  eval)
    case "\$(cat flake.nix)" in
      absent | shell-nix | extra-instructions) printf '%s\n' none ;;
      broken | broken-shell-nix) echo 'error: broken flake' >&2; exit 1 ;;
      *) printf '%s\n' derivation ;;
    esac
    ;;
  develop)
    printf '%s' "\${COPILOT_CUSTOM_INSTRUCTIONS_DIRS-}" >instruction-dirs
    printf 'develop'
    for argument in "\$@"; do
      printf ' <%s>' "\${argument}"
    done
    printf '\n'
    ;;
esac
EOF
  cat >"${case_dir}/bin/nix-shell" <<'EOF'
#!/bin/sh
printf '%s' "${COPILOT_CUSTOM_INSTRUCTIONS_DIRS-}" >instruction-dirs
printf 'nix-shell'
for argument in "$@"; do
  printf ' <%s>' "${argument}"
done
printf '\n'
EOF
  chmod +x "${case_dir}/bin/nix" "${case_dir}/bin/nix-shell"

  (
    cd "${case_dir}"
    COPILOT_CUSTOM_INSTRUCTIONS_DIRS="${instructions_dirs:-}" \
      CHELLY_NIX_BIN="${case_dir}/bin" HOME="${case_dir}/home" PATH="${case_dir}/bin:${PATH}" \
      "${entrypoint}" "$@"
  ) >"${case_dir}/stdout" 2>"${case_dir}/stderr"
  expect_output "${case_dir}/stdout" "${expected_stdout}"
  expect_output "${case_dir}/stderr" "${expected_stderr}"
  expect_output "${case_dir}/instruction-dirs" "/etc/chelly${instructions_dirs:+,${instructions_dirs}}"
}

run_mock_case no-flake "ACP response <one two> <three*>" "" agent "one two" 'three*'
run_mock_case absent "ACP response <one two> <three*>" "" agent "one two" 'three*'
instructions_dirs='/extra instructions,/other' \
  run_mock_case extra-instructions "ACP response" "" agent
run_mock_case broken "ACP response <one>" \
  "error: broken flake
chelly: unable to evaluate default development environment; starting without it" \
  agent one
run_mock_case shell-nix "nix-shell <--run> <agent one two>" "" agent one two
run_mock_case broken-shell-nix "nix-shell <--run> <agent one two>" \
  "error: broken flake
chelly: unable to evaluate default development environment; starting without it" \
  agent one two

run_real_case() {
  name="$1"
  flake="$2"
  expected_stdout="$3"
  expect_diagnostic="$4"
  case_dir="${work}/real-${name}"
  mkdir -p "${case_dir}/bin" "${case_dir}/home"
  printf '%s\n' "${flake}" >"${case_dir}/flake.nix"
  make_agent "${case_dir}/bin"
  cat >"${case_dir}/bin/nix" <<EOF
#!/bin/sh
case "\$1" in
  config) printf '%s\n' "${system}" ;;
  develop)
    printf '%s' "\${COPILOT_CUSTOM_INSTRUCTIONS_DIRS-}" >instruction-dirs
    printf 'develop'
    for argument in "\$@"; do
      printf ' <%s>' "\${argument}"
    done
    printf '\n'
    ;;
  *) exec "${real_nix}" --extra-experimental-features "nix-command flakes" "\$@" ;;
esac
EOF
  chmod +x "${case_dir}/bin/nix"

  (
    cd "${case_dir}"
    COPILOT_CUSTOM_INSTRUCTIONS_DIRS="/extra instructions,/other" \
      CHELLY_NIX_BIN="${case_dir}/bin" HOME="${case_dir}/home" PATH="${case_dir}/bin:${PATH}" \
      "${entrypoint}" agent "one two" 'three*'
  ) >"${case_dir}/stdout" 2>"${case_dir}/stderr"
  # 実 nix の失敗理由は stderr にしか出ないので、stdout の不一致時に併せて示す。
  if [ "$(cat "${case_dir}/stdout")" != "${expected_stdout}" ]; then
    printf 'stderr of %s:\n' "${case_dir}" >&2
    cat "${case_dir}/stderr" >&2
  fi
  expect_output "${case_dir}/stdout" "${expected_stdout}"
  expect_output "${case_dir}/instruction-dirs" "/etc/chelly,/extra instructions,/other"
  if [ -n "${expect_diagnostic}" ]; then
    case "$(cat "${case_dir}/stderr")" in
    *"${expect_diagnostic}"*) ;;
    *)
      printf 'Missing diagnostic %s in %s:\n' "${expect_diagnostic}" "${case_dir}" >&2
      cat "${case_dir}/stderr" >&2
      exit 1
      ;;
    esac
  else
    case "$(cat "${case_dir}/stderr")" in
    *"unable to evaluate default development environment"*) exit 1 ;;
    esac
  fi
}

derivation='builtins.derivation { name = "entrypoint-test"; system = "'"${system}"'"; builder = "/bin/sh"; }'
run_real_case devshell \
  "{ outputs = { self }: { devShells.\"${system}\".default = ${derivation}; devShell.\"${system}\" = throw \"legacy must not win\"; }; }" \
  "develop <develop> <--accept-flake-config> <--command> <agent> <one two> <three*>" ""
run_real_case legacy-devshell \
  "{ outputs = { self }: { devShell.\"${system}\" = ${derivation}; packages.\"${system}\".default = throw \"package must not win\"; }; }" \
  "develop <develop> <--accept-flake-config> <--command> <agent> <one two> <three*>" ""
run_real_case package \
  "{ outputs = { self }: { packages.\"${system}\".default = ${derivation}; defaultPackage.\"${system}\" = throw \"legacy package must not win\"; }; }" \
  "develop <develop> <--accept-flake-config> <--command> <agent> <one two> <three*>" ""
run_real_case default-package \
  "{ outputs = { self }: { defaultPackage.\"${system}\" = ${derivation}; }; }" \
  "develop <develop> <--accept-flake-config> <--command> <agent> <one two> <three*>" ""
run_real_case absent "{ outputs = { self }: { }; }" "ACP response <one two> <three*>" ""
run_real_case broken \
  "{ outputs = { self }: { devShells.\"${system}\".default = throw \"real broken flake\"; }; }" \
  "ACP response <one two> <three*>" "real broken flake"
run_real_case null \
  "{ outputs = { self }: { devShells.\"${system}\".default = null; packages.\"${system}\".default = ${derivation}; }; }" \
  "ACP response <one two> <three*>" "default development environment is not a derivation"
run_real_case wrong-type \
  "{ outputs = { self }: { devShells.\"${system}\".default = { type = \"other\"; }; }; }" \
  "ACP response <one two> <three*>" "default development environment is not a derivation"
run_real_case impure \
  "{ outputs = { self }: { devShells.\"${system}\".default = if builtins.currentSystem == \"${system}\" then ${derivation} else null; }; }" \
  "ACP response <one two> <three*>" "currentSystem"

# 専用環境では CHELLY_AGENT_CONFIG が指す bundle を volume 側の設定に適用する。
# 通常入口は本人の実 ~/.claude を mount しているので、変数が無ければ何も触らない。
run_config_case() {
  name="$1"
  config_env="$2"
  case_dir="${work}/config-${name}"
  bundle="${case_dir}/bundle"
  mkdir -p "${case_dir}/bin" "${case_dir}/home/.claude/skills/stale" "${case_dir}/home/.copilot" \
    "${bundle}/claude/skills/pair/nested" "${bundle}/claude/output-styles" "${bundle}/copilot/skills/pair"
  make_agent "${case_dir}/bin"
  cat >"${case_dir}/bin/nix" <<'EOF'
#!/bin/sh
case "$1" in config) printf 'x86_64-linux\n' ;; eval) printf 'none\n' ;; esac
EOF
  chmod +x "${case_dir}/bin/nix"
  printf 'memory\n' >"${bundle}/claude/CLAUDE.md"
  printf '{"outputStyle":"grilling","env":{"A":"bundle","B":"bundle"},"permissions":{"allow":["b"]}}\n' \
    >"${bundle}/claude/settings.json"
  printf 'style\n' >"${bundle}/claude/output-styles/grilling.md"
  printf 'skill\n' >"${bundle}/claude/skills/pair/SKILL.md"
  printf 'deep\n' >"${bundle}/claude/skills/pair/nested/file"
  printf 'instructions\n' >"${bundle}/copilot/copilot-instructions.md"
  printf '{"theme":"auto","disabledSkills":["b"],"footer":{"showAgent":true}}\n' >"${bundle}/copilot/settings.json"
  printf 'skill\n' >"${bundle}/copilot/skills/pair/SKILL.md"
  printf '{"runtime":"kept","env":{"A":"runtime","C":"runtime"},"permissions":{"allow":["a"]}}\n' \
    >"${case_dir}/home/.claude/settings.json"
  printf 'old\n' >"${case_dir}/home/.claude/skills/stale/SKILL.md"
  printf 'old\n' >"${case_dir}/home/.claude/skills/pair-old-file"
  printf '{"runtime":"kept","disabledSkills":["a"],"footer":{"showBranch":true}}\n' \
    >"${case_dir}/home/.copilot/settings.json"
  # bundle は Nix store path なので、実機では書き込み不可の mode で渡される。
  chmod -R a-w "${bundle}"

  run_config_entrypoint "${case_dir}" "${config_env}"
}

run_config_entrypoint() {
  case_dir="$1"
  config_env="$2"
  (
    cd "${case_dir}"
    CHELLY_AGENT_CONFIG="${config_env}" CLAUDE_CONFIG_DIR="${case_dir}/home/.claude" \
      CHELLY_NIX_BIN="${case_dir}/bin" HOME="${case_dir}/home" PATH="${case_dir}/bin:${PATH}" \
      "${entrypoint}" agent one
  ) >"${case_dir}/stdout" 2>"${case_dir}/stderr"
  expect_output "${case_dir}/stdout" "ACP response <one>"
  expect_output "${case_dir}/stderr" ""
}

run_config_case applied "${work}/config-applied/bundle"
expect_output "${work}/config-applied/home/.claude/CLAUDE.md" "memory"
expect_output "${work}/config-applied/home/.claude/output-styles/grilling.md" "style"
expect_output "${work}/config-applied/home/.claude/skills/pair/nested/file" "deep"
test -f "${work}/config-applied/home/.claude/skills/stale/SKILL.md"
expect_output "${work}/config-applied/home/.copilot/copilot-instructions.md" "instructions"
expect_output "${work}/config-applied/home/.copilot/skills/pair/SKILL.md" "skill"
# Claude は host の activation と同じ jq の * で、object は深く、配列は bundle 側で置き換える。
jq -e '.runtime == "kept" and .outputStyle == "grilling"
  and .env == {A: "bundle", B: "bundle", C: "runtime"} and .permissions.allow == ["b"]' \
  "${work}/config-applied/home/.claude/settings.json" >/dev/null
# Copilot は host の deep_merge と同じで、配列は和集合にする。
jq -e '.runtime == "kept" and .theme == "auto" and (.disabledSkills | sort) == ["a", "b"]
  and .footer == {showAgent: true, showBranch: true}' \
  "${work}/config-applied/home/.copilot/settings.json" >/dev/null
test -z "$(find "${work}/config-applied/home" -name 'settings.json.*')"
# 2 回目以降の起動でも、前回写した内容を上書きできること。
chmod -R u+w "${work}/config-applied/bundle"
printf 'memory 2\n' >"${work}/config-applied/bundle/claude/CLAUDE.md"
printf 'style 2\n' >"${work}/config-applied/bundle/claude/output-styles/grilling.md"
printf 'skill 2\n' >"${work}/config-applied/bundle/copilot/skills/pair/SKILL.md"
chmod -R a-w "${work}/config-applied/bundle"
run_config_entrypoint "${work}/config-applied" "${work}/config-applied/bundle"
expect_output "${work}/config-applied/home/.claude/CLAUDE.md" "memory 2"
expect_output "${work}/config-applied/home/.claude/output-styles/grilling.md" "style 2"
expect_output "${work}/config-applied/home/.copilot/skills/pair/SKILL.md" "skill 2"

run_config_case untouched ""
test ! -e "${work}/config-untouched/home/.claude/CLAUDE.md"
test ! -e "${work}/config-untouched/home/.copilot/copilot-instructions.md"
expect_output "${work}/config-untouched/home/.claude/skills/pair-old-file" "old"
jq -e '. == {runtime: "kept", env: {A: "runtime", C: "runtime"}, permissions: {allow: ["a"]}}' \
  "${work}/config-untouched/home/.claude/settings.json" >/dev/null

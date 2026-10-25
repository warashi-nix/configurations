{
  # agent team は agentel (ACP) からは扱えないので、TUI を eshell で動かす hestia でだけ使う。
  # tmux の中から起動した Emacs でも teammate を eshell の中に出すため、表示先を固定する。
  warashi.claude.settings = {
    env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
    teammateMode = "in-process";
  };
}

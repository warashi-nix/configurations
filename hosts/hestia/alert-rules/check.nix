{ prometheus, runCommand }:
# promtool は rule_files を test.yaml からの相対パスで探すので、ディレクトリごと渡す
runCommand "hestia-alert-rules" { nativeBuildInputs = [ prometheus.cli ]; } ''
  promtool check rules ${./.}/rules.yaml
  promtool test rules ${./.}/test.yaml
  touch $out
''

{ runCommand, chelly }:
# 入口の wrapper は本体の bin/chelly と同じ名前なので、本体からは補完だけを取り出して並べる。
runCommand "chelly-completions" { } ''
  mkdir "$out"
  ln -s ${chelly}/share "$out/share"
''

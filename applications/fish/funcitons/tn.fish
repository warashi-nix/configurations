function tn --description "Open a new tmux session in the selected directory"
  set -l selected_path "$(cat "$(echo '$HOME' | psub)" "$(ghq list --full-path | psub)" | fzf --delimiter=/ --with-nth=-2,-1 --scheme=path)"
  if [ -z "$selected_path" ]
    return 1
  end
  set -l session_name "$(basename "$(dirname "$selected_path")")/$(basename "$selected_path")"

  # HOME を選択した場合は、セッション名を $HOME にする
  if string match --quiet "$selected_path" '$HOME'
    set selected_path "$HOME"
    set session_name 'HOME'
  end

  # if inside a tmux session
  if set -q TMUX
    if not tmux has-session -t "$session_name" >/dev/null 2>&1
      tmux new-session -ds "$session_name" -c "$selected_path"
    end

    tmux switch-client -t "$session_name" 
    return 0
  end

  tmux new-session -ADs "$session_name" -c "$selected_path"
end

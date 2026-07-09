function ta --description "Attach existing tmux session with fzf selection"
  set -l selected_session (tmux list-sessions -F '#S' | fzf)
  if [ -z "$selected_session" ]
    return 1
  end

  if set -q TMUX
    tmux switch-client -t "$selected_session"
    return 0
  end

  tmux attach-session -t "$selected_session"
end

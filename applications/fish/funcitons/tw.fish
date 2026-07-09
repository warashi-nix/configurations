function tw --description "Open a new tmux window in the directory of a selected git wit."
  set -l selected_wit "$(git wit ls | fzf --with-nth=2,4 --accept-nth=1)"
  if [ -z "$selected_wit" ]
    return 1
  end
  set -l selected_wit_memo "$(git wit memo "$selected_wit")"
  set -l selected_wit_dir "$(git wit dir "$selected_wit")"

  tmux new-window -c "$selected_wit_dir" -n "$selected_wit_memo"
end

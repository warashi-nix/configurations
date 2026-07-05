vim9script

# --------------------------------------------------
#  Theme Sync (OSC 11)
# --------------------------------------------------

if has('gui_running') || !has('ttyin') || !has('ttyout')
  finish
endif

if &t_RB == ''
  &t_RB = "\e]11;?\e\\"
endif

def Query(timer: number = 0)
  echoraw(&t_RB)
enddef

timer_start(3'000, Query, {repeat: -1})

augroup ThemeSync
  autocmd!
  autocmd FocusGained * Query()
augroup END

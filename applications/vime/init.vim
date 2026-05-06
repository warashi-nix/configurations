vim9script

language message C
set nocompatible

augroup MyAutoCmd
  autocmd!
augroup END

g:denops#deno = '@deno@'

set runtimepath^=@denops@
set runtimepath^=@skkeleton@

# --------------------------------------------------
#  Skkeleton Configuration
# --------------------------------------------------

def SkkeletonInitialize()
  skkeleton#config({
    sources: ['skk_server']
  })
enddef

inoremap <C-j> <Plug>(skkeleton-enable)

augroup MyAutoCmd
  autocmd User skkeleton-initialize-pre SkkeletonInitialize()
augroup END

skkeleton#initialize()

# --------------------------------------------------
#  Start in Insert Mode
# --------------------------------------------------

augroup MyAutoCmd
  autocmd InsertEnter * ++once skkeleton#handle('enable', {})
  autocmd BufWinEnter * startinsert
augroup END

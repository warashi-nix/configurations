language message C
set nocompatible

augroup MyAutoCmd
  autocmd!
augroup END

let g:denops#deno = '@deno@'

set runtimepath^=@denops@
set runtimepath^=@skkeleton@

" --------------------------------------------------
"  Skkeleton Configuration
" --------------------------------------------------
function s:skkeleton_initialize()
  call skkeleton#config(#{
  \   sources: ['skk_server'],
  \   skkServerReqEnc: 'utf-8',
  \   skkServerResEnc: 'utf-8',
  \ })
endfunction

inoremap <C-j> <Plug>(skkeleton-enable)

augroup MyAutoCmd
  autocmd User skkeleton-initialize-pre call s:skkeleton_initialize()
augroup END

call skkeleton#initialize()

" --------------------------------------------------
"  Start in Insert Mode
" --------------------------------------------------
augroup MyAutoCmd
  autocmd InsertEnter * ++once call skkeleton#handle('enable', {})
  autocmd BufWinEnter * startinsert
augroup END

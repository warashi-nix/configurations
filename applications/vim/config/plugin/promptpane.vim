vim9script

# グローバル変数としてスクリプトIDを取得
const sid = expand('<SID>')

# ==========================================================================
# Persistent Undo (永続的アンドゥ) の設定
# ==========================================================================
# promptpane専用のundo履歴保存ディレクトリ
const undo_base_dir = expand('~/.cache/vim/undo_promptpane')

# カレントディレクトリ（CWD）のみから安全なファイルパスを生成する
def GetUndoFilePath(uri: string): string
    # 現在のカレントディレクトリを取得
    final cwd = getcwd()

    # ディレクトリパスの特殊文字（:, /, \, 空白）をすべて '_' に置換
    final safe_name = substitute(cwd, '[:/\\\\ ]', '_', 'g')

    # ペインに関わらず共通のプレフィックスを付与してファイル名にする
    return undo_base_dir .. '/promptpane_shared_' .. safe_name
enddef
# ==========================================================================

# ファイルパス補完関数
def PathComplete(findstart: number, base: string): any
    if findstart
        final line = getline('.')
        var start = col('.') - 1
        while start > 0 && line[start - 1] =~ '[a-zA-Z0-9_.,~@/\\-]'
            start -= 1
        endwhile

        final text = line[start : col('.') - 2]

        if text !~ '[/\\\\]' && text[0] != '~' && text != '.' && text != '..'
            return -2
        endif

        return start
    else
        final pattern = base .. '*'
        final files = glob(pattern, true, true)

        final results = []
        for f in files
            if isdirectory(f)
                add(results, f .. '/')
            else
                add(results, f)
            endif
        endfor
        return results
    endif
enddef

# 重複登録を防ぐため augroup を作成
augroup PromptPane
    autocmd!
    # バッファ作成時のセットアップ用コマンド
    autocmd BufReadCmd promptpane://tmux/* SetupBuffer()
    # :w 実行時のフック（送信処理）
    autocmd BufWriteCmd promptpane://tmux/* SendToTmux(expand('<amatch>'))
augroup END

def SetupBuffer()
    # 通常のファイル保存を無効化し、専用バッファとして扱う
    setlocal filetype=promptpane
    setlocal buftype=acwrite
    setlocal noswapfile
    setlocal nomodified

    # 補完をこのバッファ専用に設定
    setlocal autocomplete
    exec $'setlocal complete+=F{sid}PathComplete^10'

    # --------------------------------------------------------------------------
    # 起動時: 過去の undo 履歴をディスクから読み込む
    # --------------------------------------------------------------------------
    if has('persistent_undo')
        if !isdirectory(undo_base_dir)
            mkdir(undo_base_dir, 'p', 0o700)
        endif

        final uri = expand('<amatch>')
        final undo_file = GetUndoFilePath(uri)
        if filereadable(undo_file)
            # バッファが完全に空の状態で履歴を読み込む（保存時と状態を一致させるため）
            exec $'silent! rundofile {fnameescape(undo_file)}'
        endif
    endif
enddef

def SendToTmux(uri: string)
    final pane_id = matchstr(uri, 'promptpane://tmux/\zs.*')
    if pane_id == ''
        echohl ErrorMsg
        echomsg '[PromptPane] 無効なURIフォーマットです: ' .. uri
        echohl None
        return
    endif

    final lines = getline(1, '$')
    final payload = "\e[200~" .. join(lines, "\r") .. "\e[201~\e[13u"

    final result = system([
        'tmux',
        'send-keys',
        '-t',
        pane_id,
        '-l',
        '--',
        payload
    ])

    if v:shell_error != 0
        echohl ErrorMsg
        echomsg '[PromptPane] 送信失敗: ' .. trim(result)
        echohl None
        return
    endif

    setline(1, '')
    if line('$') > 1
        silent! deletebufline('%', 2, '$')
    endif
    setlocal nomodified

    if has('persistent_undo')
        final undo_file = GetUndoFilePath(uri)
        exec $'silent! wundofile {fnameescape(undo_file)}'
    endif

    echomsg '[PromptPane] 完了: Pane ' .. pane_id .. ' へ送信・実行しました'
enddef

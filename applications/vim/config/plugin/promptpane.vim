vim9script

# グローバル変数としてスクリプトIDを取得（補完関数の一意性確保のため）
const sid = expand('<SID>')

# ファイルパス補完関数
def PathComplete(findstart: number, base: string): any
    if findstart
        final line = getline('.')
        var start = col('.') - 1
        while start > 0 && line[start - 1] =~ '[a-zA-Z0-9_.,~@/\\-]'
            start -= 1
        endwhile
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
  # ※ BufReadCmd は対象バッファ内で実行されるため setlocal がそのまま有効
  setlocal filetype=promptpane
  setlocal buftype=acwrite
  setlocal noswapfile
  setlocal nomodified

  # 補完をこのバッファ専用に設定
  setlocal autocomplete
  exec $'setlocal complete+=F{sid}PathComplete^10'
enddef

def SendToTmux(uri: string)
  # URIから pane_id を抽出 (例: promptpane://tmux/1 -> 1)
  var pane_id = matchstr(uri, 'promptpane://tmux/\zs.*')
  if pane_id == ''
    echohl ErrorMsg
    echomsg '[PromptPane] 無効なURIフォーマットです: ' .. uri
    echohl None
    return
  endif

  # バッファの内容を取得
  var lines = getline(1, '$')
  
  # Vim9scriptのダブルクォート文字列では \e が ESC (0x1B) として解釈される
  var payload = "\e[200~" .. join(lines, "\r\n") .. "\e[201~\e[13u"

  # シェルを経由せず、直接tmuxプロセスにリスト形式で引数を渡す（結合・複雑性の極小化）
  # Vimの system() にリストを渡すとシェルエスケープを回避して直接実行される
  var result = system([
    'tmux',
    'send-keys',
    '-t',
    pane_id,
    '-l',
    '--',
    payload
  ])

  # 実行結果の確認
  if v:shell_error != 0
    echohl ErrorMsg
    # system() の結果には標準エラー出力も含まれるため trim して表示
    echomsg '[PromptPane] 送信失敗: ' .. trim(result)
    echohl None
    return
  endif

  # 送信成功: バッファをクリアし、未編集状態に戻す（Editing状態への回帰）
  # ※Undoツリーは維持されるため、`u` で直前のプロンプトを復元可能
  setline(1, '')
  if line('$') > 1
    # 2行目以降が存在する場合は削除
    silent! deletebufline('%', 2, '$')
  endif
  setlocal nomodified

  echomsg '[PromptPane] 完了: Pane ' .. pane_id .. ' へ送信・実行しました'
enddef

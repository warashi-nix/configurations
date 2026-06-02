vim9script

# -------------------------------------------------------------------------
# 状態管理
# -------------------------------------------------------------------------
const prop_type_name = 'CopilotGhostText'
const server_name = 'copilot-language-server'

# ゴーストテキストと、確定時のカーソル移動文字数の保持用
var current_suggestion: string = ''
var current_move_before: number = 0  # 挿入前に右移動する文字数
var current_move_after: number = 0   # 挿入後に右移動する文字数

if empty(prop_type_get(prop_type_name))
  prop_type_add(prop_type_name, { highlight: 'Comment' })
endif

def ClearGhostText()
  prop_remove({ type: prop_type_name, all: v:true })
  current_suggestion = ''
  current_move_before = 0
  current_move_after = 0
enddef

def ShowGhostText(line: number, col: number, text: string)
  prop_remove({ type: prop_type_name, all: v:true })

  # 改行で分割（空行も維持するために第3引数に 1 を指定）
  final lines = split(text, '\n', 1)
  if empty(lines)
    return
  endif

  try
    # 1行目: カーソル位置（インライン）に表示
    if !empty(lines[0])
      prop_add(line, col, {
        type: prop_type_name,
        text: lines[0],
      })
    endif

    # 2行目以降: 行の下（below）に追加表示
    if len(lines) > 1
      for i in range(1, len(lines) - 1)
        # Vimの仮想テキストは空文字("")を許容しないため、空行の場合はスペースに置換
        final display_text = empty(lines[i]) ? ' ' : lines[i]
        
        prop_add(line, 0, {
          type: prop_type_name,
          text: display_text,
          text_align: 'below',
        })
      endfor
    endif
  catch
    echohl ErrorMsg
    echomsg 'Failed to show Copilot suggestion: ' .. v:exception
    echohl None
  endtry
enddef
# -------------------------------------------------------------------------
# LSP リクエストとレスポンスの処理
# -------------------------------------------------------------------------
def FetchCopilotCompletion()
  if lsp#get_server_status(server_name) != 'running'
    return
  endif

  final bufnr = bufnr('%')
  final vim_pos = [line('.'), col('.')]
  final lsp_pos = lsp#utils#position#vim_to_lsp(bufnr, vim_pos)

  final uri = lsp#utils#get_buffer_uri(bufnr)
  final params = {
    textDocument: { uri: uri },
    position: lsp_pos,
    context: { triggerKind: 2 }
  }

  lsp#send_request(server_name, {
    method: 'textDocument/inlineCompletion',
    params: params,
    on_notification: (data) => HandleCopilotResponse(data, bufnr, lsp_pos)
  })
enddef

def HandleCopilotResponse(data: dict<any>, req_bufnr: number, req_lsp_pos: dict<any>)
  if mode() != 'i' || bufnr('%') != req_bufnr
    ClearGhostText()
    return
  endif

  final req_vim_pos = lsp#utils#position#lsp_to_vim(req_bufnr, req_lsp_pos)
  final req_line = req_vim_pos[0]
  final req_col = req_vim_pos[1]

  if line('.') != req_line || col('.') != req_col
    return
  endif

  if !has_key(data, 'response') || !has_key(data.response, 'result') || empty(data.response.result)
    return
  endif

  final result = data.response.result
  if !has_key(result, 'items') || empty(result.items)
    return
  endif

  final item = result.items[0]
  final insert_text = item.insertText
  if empty(insert_text)
    return
  endif

  var ghost_text = insert_text

  # 1. カーソル位置までの入力済み文字列（左側）と重複する部分を削る
  if has_key(item, 'range') && has_key(item.range, 'start')
    final start_pos = lsp#utils#position#lsp_to_vim(req_bufnr, item.range.start)
    final start_col = start_pos[1]

    if req_col > start_col
      final overlap_len = req_col - start_col
      final overlap_str = strpart(getline(req_line), start_col - 1, overlap_len)

      if strpart(insert_text, 0, len(overlap_str)) ==# overlap_str
        ghost_text = strpart(insert_text, len(overlap_str))
      endif
    endif
  endif

  var move_before = 0
  var move_after = 0
  var display_text = ghost_text
  var display_col = req_col

  # 2. カーソル位置より後ろ（右側・行末方向）の既存文字列との重複を判定
  if has_key(item, 'range') && has_key(item.range, 'end')
    final end_pos = lsp#utils#position#lsp_to_vim(req_bufnr, item.range.end)
    final end_line = end_pos[0]
    final end_col = end_pos[1]

    if end_line == req_line && end_col > req_col
      final right_len = end_col - req_col
      final right_str = strpart(getline(req_line), req_col - 1, right_len)
      final r_len = len(right_str)

      # 【パターンA】ghost_text の「先頭」が右側文字列と一致する場合（例: tion() {\n} と tion()）
      if strpart(ghost_text, 0, r_len) ==# right_str
        ghost_text = strpart(ghost_text, r_len)
        move_before = strchars(right_str)
        # 表示上も削って、ゴーストテキストの表示位置を右にずらす
        display_text = ghost_text
        display_col += r_len

      # 【パターンB】ghost_text の「末尾」が右側文字列と一致する場合（例: "hello") と ) ）
      elseif len(ghost_text) >= r_len && strpart(ghost_text, len(ghost_text) - r_len) ==# right_str
        ghost_text = strpart(ghost_text, 0, len(ghost_text) - r_len)
        move_after = strchars(right_str)
        # 表示上も末尾を削る（表示位置 col はカーソル位置のまま）
        display_text = ghost_text
      endif
    endif
  endif

  # 重複を削った結果、挿入するものも移動するものも無い場合は終了
  if empty(ghost_text) && move_before == 0 && move_after == 0
    return
  endif

  current_suggestion = ghost_text
  current_move_before = move_before
  current_move_after = move_after

  if !empty(display_text)
    ShowGhostText(req_line, display_col, display_text)
  endif
enddef

# -------------------------------------------------------------------------
# 補完の確定処理 (Accept)
# -------------------------------------------------------------------------
def AcceptCopilotCompletion(): string
  if empty(current_suggestion) && current_move_before == 0 && current_move_after == 0
    return "\<Tab>"
  endif

  final text = current_suggestion
  final before = current_move_before
  final after = current_move_after
  ClearGhostText()

  # 1. 挿入前に通り抜けるべき文字があれば移動
  var prefix = before > 0 ? repeat("\<Right>", before) : ''
  # 2. 挿入後に通り抜けるべき文字があれば移動
  var suffix = after > 0 ? repeat("\<Right>", after) : ''

  return prefix .. substitute(text, '\n', "\<CR>", 'g') .. suffix
enddef

inoremap <expr> <Tab> <SID>AcceptCopilotCompletion()

# -------------------------------------------------------------------------
# Auto Commands
# -------------------------------------------------------------------------
augroup CopilotInline
  autocmd!
  autocmd CursorHoldI * FetchCopilotCompletion()
  autocmd CursorMovedI,InsertCharPre,InsertLeave * ClearGhostText()
augroup END

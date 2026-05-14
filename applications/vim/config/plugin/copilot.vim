vim9script

# -------------------------------------------------------------------------
# 状態管理
# -------------------------------------------------------------------------
const prop_type_name = 'CopilotGhostText'
const server_name = 'copilot-language-server'

# ゴーストテキストの保持用。実行時に何度も書き換わるため、これだけは var にする
var current_suggestion: string = ''

if empty(prop_type_get(prop_type_name))
  prop_type_add(prop_type_name, { highlight: 'Comment' })
endif

def ClearGhostText()
  prop_remove({ type: prop_type_name, all: v:true })
  current_suggestion = ''
enddef

def ShowGhostText(line: number, col: number, text: string)
  prop_remove({ type: prop_type_name, all: v:true })

  final first_line = split(text, '\n')[0]
  if empty(first_line)
    return
  endif

  try
    prop_add(line, col, {
      type: prop_type_name,
      text: first_line,
    })
  catch
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

  # 補完テキストが置換範囲 (range) を指定している場合、
  # カーソル位置までの入力済み文字列と重複する部分を削る
  if has_key(item, 'range') && has_key(item.range, 'start')
    final start_pos = lsp#utils#position#lsp_to_vim(req_bufnr, item.range.start)
    final start_col = start_pos[1]

    # range の開始位置がカーソルより前にある場合は重複がある
    if req_col > start_col
      final overlap_len = req_col - start_col
      # バッファ上にあるすでに入力済みの文字列を取得
      final overlap_str = strpart(getline(req_line), start_col - 1, overlap_len)

      # insert_text の先頭が入力済み文字列と一致していれば、その部分を削除する
      if strpart(insert_text, 0, len(overlap_str)) ==# overlap_str
        ghost_text = strpart(insert_text, len(overlap_str))
      endif
    endif
  endif

  # 重複を削った結果、表示するものが無くなった場合は終了
  if empty(ghost_text)
    return
  endif

  current_suggestion = ghost_text
  ShowGhostText(req_line, req_col, ghost_text)
enddef

# -------------------------------------------------------------------------
# 補完の確定処理 (Accept)
# -------------------------------------------------------------------------
def AcceptCopilotCompletion(): string
  if empty(current_suggestion)
    return "\<Tab>"
  endif

  # 確定するテキストを一時退避するため final で宣言
  final text = current_suggestion
  ClearGhostText()

  return substitute(text, '\n', "\<CR>", 'g')
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

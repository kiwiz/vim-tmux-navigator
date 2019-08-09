" Maps <C-h/j/k/l> to switch vim splits in the given direction. If there are
" no more windows in that direction, forwards the operation to tmux.
" Additionally, <C-\> toggles between last active vim splits/tmux panes.

" Check if plugin is already loaded
if exists("g:loaded_tmux_navigator") || &cp || v:version < 700
  finish
endif
let g:loaded_tmux_navigator = 1

" Define mapping between a direction and its opposite
let s:opp = {
\ 'j': 'k',
\ 'k': 'j',
\ 'h': 'l',
\ 'l': 'h',
\}

" Wrapper for wincmd with wrapping support
" - arg to pass thru
" - whether to wrap (true)
" Returns whether a movement was made
function g:Wincmd(arg, ...)
  let l:wrap = get(a:, 1, v:true)

  " Try executing the wincmd
  let l:nr = winnr()
  exec 'wincmd' a:arg
  let l:moved = winnr() != l:nr

  " Stop processing if the arg doesn't exist in the mapping
  if !has_key(s:opp, a:arg)
    return l:moved
  endif

  " Emulate a wrap by moving in the opposite direction
  if !l:moved && l:wrap
    exec winnr('$') 'wincmd' s:opp[a:arg]
    return v:true
  endif

  return l:moved
endfunction

function s:VimEdgeNavigate(arg)
  exec winnr('$') 'wincmd' a:arg
endfunction

" Wrapper?
function! s:VimNavigate(direction, wrap)
  try
    return !Wincmd(a:direction, a:wrap)
  catch
    echohl ErrorMsg | echo 'E11: Invalid in command-line window; <CR> executes, CTRL-C quits: wincmd k' | echohl None
  endtry
endfunction

" Define key mappings
if !get(g:, 'tmux_navigator_no_mappings', 0)
  nnoremap <silent> <c-h> :TmuxNavigateLeft<cr>
  nnoremap <silent> <c-j> :TmuxNavigateDown<cr>
  nnoremap <silent> <c-k> :TmuxNavigateUp<cr>
  nnoremap <silent> <c-l> :TmuxNavigateRight<cr>
  nnoremap <silent> <c-\> :TmuxNavigatePrevious<cr>

  nmap <silent> <C-w>j :call Wincmd('j')<cr>
  nmap <silent> <C-w>k :call Wincmd('k')<cr>
  nmap <silent> <C-w>h :call Wincmd('h')<cr>
  nmap <silent> <C-w>l :call Wincmd('l')<cr>
endif

command! VimEdgeNavigateLeft call s:VimEdgeNavigate('h')
command! VimEdgeNavigateDown call s:VimEdgeNavigate('j')
command! VimEdgeNavigateUp call s:VimEdgeNavigate('k')
command! VimEdgeNavigateRight call s:VimEdgeNavigate('l')

if empty($TMUX)
  command! TmuxNavigateLeft call s:VimNavigate('h', v:true)
  command! TmuxNavigateDown call s:VimNavigate('j', v:true)
  command! TmuxNavigateUp call s:VimNavigate('k', v:true)
  command! TmuxNavigateRight call s:VimNavigate('l', v:true)
  command! TmuxNavigatePrevious call s:VimNavigate('p', v:true)
  finish
endif

command! TmuxNavigateLeft call s:TmuxAwareNavigate('h')
command! TmuxNavigateDown call s:TmuxAwareNavigate('j')
command! TmuxNavigateUp call s:TmuxAwareNavigate('k')
command! TmuxNavigateRight call s:TmuxAwareNavigate('l')
command! TmuxNavigatePrevious call s:TmuxAwareNavigate('p')

if !exists("g:tmux_navigator_save_on_switch")
  let g:tmux_navigator_save_on_switch = 0
endif

if !exists("g:tmux_navigator_disable_when_zoomed")
  let g:tmux_navigator_disable_when_zoomed = 0
endif

function! s:TmuxOrTmateExecutable()
  return (match($TMUX, 'tmate') != -1 ? 'tmate' : 'tmux')
endfunction

function! s:TmuxVimPaneIsZoomed()
  return s:TmuxCommand("display-message -p '#{window_zoomed_flag}'") == 1
endfunction

function! s:TmuxPaneId()
  return s:TmuxCommand("display-message -p '#{pane_id}'")
endfunction

function! s:TmuxSocket()
  " The socket path is the first value in the comma-separated list of $TMUX.
  return split($TMUX, ',')[0]
endfunction

function! s:TmuxCommand(args)
  let cmd = s:TmuxOrTmateExecutable() . ' -S ' . s:TmuxSocket() . ' ' . a:args
  return system(cmd)
endfunction

function! s:TmuxNavigatorProcessList()
  echo s:TmuxCommand("run-shell 'ps -o state= -o comm= -t ''''#{pane_tty}'''''")
endfunction
command! TmuxNavigatorProcessList call s:TmuxNavigatorProcessList()

let s:tmux_is_last_pane = 0
augroup tmux_navigator
  au!
  autocmd WinEnter * let s:tmux_is_last_pane = 0
augroup END

function! s:NeedsVitalityRedraw()
  return exists('g:loaded_vitality') && v:version < 704 && !has("patch481")
endfunction

function! s:ShouldForwardNavigationBackToTmux(tmux_last_pane, at_tab_page_edge)
  if g:tmux_navigator_disable_when_zoomed && s:TmuxVimPaneIsZoomed()
    return 0
  endif
  return a:tmux_last_pane || a:at_tab_page_edge
endfunction

function! s:TmuxAwareNavigate(direction)
  let tmux_last_pane = (a:direction == 'p' && s:tmux_is_last_pane)
  if !tmux_last_pane
    let at_tab_page_edge = s:VimNavigate(a:direction, v:false)
  endif

  " Forward the switch panes command to tmux if:
  " a) we're toggling between the last tmux pane;
  " b) we tried switching windows in vim but it didn't have effect.
  let s:tmux_is_last_pane = 0
  if s:ShouldForwardNavigationBackToTmux(tmux_last_pane, at_tab_page_edge)
    let l:pane_id = s:TmuxPaneId()
    let args = 'select-pane -t ' . shellescape($TMUX_PANE) . ' -' . tr(a:direction, 'phjkl', 'lLDUR')
    silent call s:TmuxCommand(args)

    if l:pane_id == s:TmuxPaneId()
      call s:VimNavigate(a:direction, v:true)
    else
      let s:tmux_is_last_pane = 1
    endif
  endif

  if s:tmux_is_last_pane == 1
    if g:tmux_navigator_save_on_switch == 1
      try
        update " save the active buffer. See :help update
      catch /^Vim\%((\a\+)\)\=:E32/ " catches the no file name error
      endtry
    elseif g:tmux_navigator_save_on_switch == 2
      try
        wall " save all the buffers. See :help wall
      catch /^Vim\%((\a\+)\)\=:E141/ " catches the no file name error
      endtry
    endif
    if s:NeedsVitalityRedraw()
      redraw!
    endif
  endif
endfunction

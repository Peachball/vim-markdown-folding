" Fold expressions {{{1
function! StackedMarkdownFolds()
  let thisline = getline(v:lnum)
  let prevline = getline(v:lnum - 1)
  let nextline = getline(v:lnum + 1)
  if thisline =~ '^```.*$' && prevline =~ '^\s*$'  " start of a fenced block
    return ">2"
  elseif thisline =~ '^```$' && nextline =~ '^\s*$'  " end of a fenced block
    return "<2"
  endif

  if HeadingDepth(v:lnum) > 0
    return ">1"
  else
    return "="
  endif
endfunction

function! NestedMarkdownFolds(lnum)
  " Syntax loading seems to depend on the foldexpr. Not sure how to break the
  " dependency, so adding this check to avoid that edge case
  if !(exists("b:current_syntax") && b:current_syntax ==# 'markdown')
    return 0
  endif
  let thisline = getline(a:lnum)
  let prevline = getline(a:lnum - 1)
  let nextline = getline(a:lnum + 1)

  call s:UpdateShortestHeader()
  let currentHeadingDepth = s:HeadingDepthOfLine(a:lnum) - b:shortestHeader

  " Code block folding
  if LineIsFenced(a:lnum)
    if thisline !~ '^```.*$'
      return currentHeadingDepth + 1
    endif
    if thisline =~ '^```.*$' && !LineIsFenced(a:lnum-1)  " start of a fenced block
      return ">" . (currentHeadingDepth + 1)
    elseif thisline =~ '^```$' && !LineIsFenced(a:lnum+1)  " end of a fenced block
      return "<" . (currentHeadingDepth + 1)
    endif
  endif

  " Header folding
  let depth = HeadingDepth(a:lnum)
  if depth > 0
    return ">".(depth - b:shortestHeader)
  endif



  " Add list folding as well
  " Do so via the following:
  " 1. Figure out if list starts (prefix "-")
  " 2. Figure out previous fold level as a result of the heading
  " 3. Set fold level by adding heading fold level to list fold level
  if thisline =~ '^ *-'
    let currentListDepth = (len(matchstr(thisline, ' *-')) + 1) / 2
    return ">" . (currentListDepth + currentHeadingDepth)
  endif

  if thisline =~ '^ \+'
    return "="
  endif
  if nextline =~ '^ *-'
    return ">" . (currentHeadingDepth + 1)
  endif

  return currentHeadingDepth
endfunction

function HeadingDepthOfLinePub(lnum)
  echo s:HeadingDepthOfLine(a:lnum)
endfunction

" Helpers {{{1
function! s:SID()
  return matchstr(expand('<sfile>'), '<SNR>\d\+_')
endfunction

function! s:HeadingDepthOfLine(lnum)
  let currentHeadingDepth = -1
  let cursorPosition = [line("."), col(".")]
  let currentLine = a:lnum
  while currentHeadingDepth ==# -1
    call cursor(currentLine, 1)
    let [prevHeadingLnum, prevHeadingCol] = searchpos('^#\+', 'bW')
    let currentLine = prevHeadingLnum
    if currentLine ==# 0
      let currentHeadingDepth = 0
      break
    endif
    if LineIsFenced(currentLine)
      let currentLine = currentLine - 1
      continue
    endif
    let currentHeadingDepth = HeadingDepth(currentLine)
  endwhile
  call cursor(cursorPosition)
  return currentHeadingDepth
endfunction

function! HeadingDepth(lnum)
  let level=0


  let thisline = getline(a:lnum)
  if thisline =~ '^#\+\s\+'
    let hashCount = len(matchstr(thisline, '^#\{1,6}'))
    if hashCount > 0
      let level = hashCount
    endif
  else
    if thisline != ''
      let nextline = getline(a:lnum + 1)
      if nextline =~ '^=\+\s*$'
        let level = 1
      elseif nextline =~ '^-\+\s*$'
        let level = 2
      endif
    endif
  endif
  if level > 0 && LineIsFenced(a:lnum)
    " Ignore # or === if they appear within fenced code blocks
    let level = 0
  endif
  return level
endfunction

function! LineIsFenced(lnum)
  if exists("b:current_syntax") && b:current_syntax ==# 'markdown'
    " It's cheap to check if the current line has 'markdownCode' syntax group
    return HasSyntaxGroup(a:lnum, '\vmarkdown(Code|Highlight)')
  else
    " Using searchpairpos() is expensive, so only do it if syntax highlighting
    " is not enabled
    return s:HasSurroundingFencemarks(a:lnum)
  endif
endfunction

function! HasSyntaxGroup(lnum, targetGroup)
  let syntaxGroup = map(synstack(a:lnum, 1), 'synIDattr(v:val, "name")')
  for value in syntaxGroup
    if value =~ a:targetGroup
        return 1
    endif
  endfor
endfunction

function! s:HasSurroundingFencemarks(lnum)
  let cursorPosition = [line("."), col(".")]
  call cursor(a:lnum, 1)
  let startFence = '\%^```\|^\n\zs```'
  let endFence = '```\n^$'
  let fenceEndPosition = searchpairpos(startFence,'',endFence,'W')
  call cursor(cursorPosition)
  return fenceEndPosition != [0,0]
endfunction

function! s:FoldText()
  let level = HeadingDepth(v:foldstart)
  let indent = repeat('#', level)
  let title = substitute(getline(v:foldstart), '^#\+\s\+', '', '')
  let foldsize = (v:foldend - v:foldstart)
  let linecount = '['.foldsize.' line'.(foldsize>1?'s':'').']'

  if level < 6
    let spaces_1 = repeat(' ', 6 - level)
  else
    let spaces_1 = ' '
  endif

  if exists('*strdisplaywidth')
      let title_width = strdisplaywidth(title)
  else
      let title_width = len(title)
  endif

  if title_width < 40
    let spaces_2 = repeat(' ', 40 - title_width)
  else
    let spaces_2 = ' '
  endif

  return indent.spaces_1.title.spaces_2.linecount
endfunction

function! s:UpdateShortestHeader()
  if exists('b:shortestHeaderUpdateTick') &&
        \ b:shortestHeaderUpdateTick ==# b:changedtick + 1
    return
  endif

  let b:shortestHeaderUpdateTick = b:changedtick + 1

  let totalLines = line('$')
  let b:shortestHeader = -1
  for lnum in range(1, totalLines)
    let lineHeaderDepth = HeadingDepth(lnum)
    if lineHeaderDepth ==# 0
      continue
    endif
    if b:shortestHeader ==# -1 || b:shortestHeader > lineHeaderDepth
      let b:shortestHeader = lineHeaderDepth
    endif
  endfor
  if b:shortestHeader ==# -1
    let b:shortestHeader = 0
  else
    let b:shortestHeader = b:shortestHeader - 1
  endif
endfunction


" API {{{1
function! ToggleMarkdownFoldexpr()
  if &l:foldexpr ==# 'StackedMarkdownFolds()'
    setlocal foldexpr=NestedMarkdownFolds()
  else
    setlocal foldexpr=StackedMarkdownFolds()
  endif
endfunction
command! -buffer FoldToggle call ToggleMarkdownFoldexpr()

" Setup {{{1
if !exists('g:markdown_fold_style')
  let g:markdown_fold_style = 'stacked'
endif

if !exists('g:markdown_fold_override_foldtext')
  let g:markdown_fold_override_foldtext = 1
endif

function! FoldTextWorkaround()
    let level = HeadingDepth(v:foldstart)
    let indent = repeat('#', level)
    let title = substitute(getline(v:foldstart), '^#\+\s*', '', '')
    let foldsize = (v:foldend - v:foldstart)
    let linecount = '['.foldsize.' line'.(foldsize>1?'s':'').']'
    return indent.' '.title.' '.linecount
endfunction

setlocal foldmethod=expr

if g:markdown_fold_override_foldtext
  " let &l:foldtext = s:SID() . 'FoldText()'
  setlocal foldtext=FoldTextWorkaround()
endif

let &l:foldexpr =
  \ g:markdown_fold_style ==# 'nested'
  \ ? 'NestedMarkdownFolds(v:lnum)'
  \ : 'StackedMarkdownFolds()'

" Teardown {{{1
if !exists("b:undo_ftplugin") | let b:undo_ftplugin = '' | endif
let b:undo_ftplugin .= '
  \ | setlocal foldmethod< foldtext< foldexpr<
  \ | delcommand FoldToggle
  \ '
" vim:set fdm=marker:

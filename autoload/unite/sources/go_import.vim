let s:save_cpo = &cpo
set cpo&vim

let g:unite_source_go_import_go_command = get(g:, 'unite_source_go_import_go_command', 'go')
let g:unite_source_go_import_disable_cache = get(g:, 'unite_source_go_import_disable_cache', 0)
let g:unite_source_go_import_min_input = get(g:, 'unite_source_go_import_min_input', 3)
let g:unite_source_go_import_search_filename = get(g:, 'unite_source_go_import_search_filename', 1)

let s:source = {
            \   'name' : 'go/import',
            \   'description' : 'Go packages to import',
            \   'default_action' : {'common' : 'import'},
            \   'required_pattern_length' : g:unite_source_go_import_min_input,
            \   'action_table' : {},
            \ }

let s:previous_result = []

function! unite#sources#go_import#define() abort
    if s:cmd_for('import') ==# ''
        return {}
    endif
    return s:source
endfunction

function! unite#sources#go_import#reset_cache() abort
    let s:previous_result = []
endfunction

if $GOOS != ''
    let s:OS = $GOOS
elseif has('mac')
    let s:OS = 'darwin'
elseif has('win32') || has('win64')
    let s:OS = 'windows'
else
    let s:OS = '*'
endif

if $GOARCH != ''
    let s:ARCH = $GOARCH
else
    let s:ARCH = '*'
endif

function! s:gopath() abort
    let path = $GOPATH
    if path ==# ''
        let path = expand('~/go')
    endif
    return path
endfunction

function! s:go_packages() abort
    if executable('gopkgs')
      " https://github.com/haya14busa/gopkgs
      return split(system('gopkgs'), "\n")
    endif

    let dirs = []

    if executable('go')
        let goroot = substitute(system('go env GOROOT'), '\n', '', 'g')
        if v:shell_error
            echohl ErrorMsg | echomsg "'go env GOROOT' failed" | echohl None
            return []
        endif
    else
        let goroot = $GOROOT
    endif

    if goroot != '' && isdirectory(goroot)
        call add(dirs, goroot)
    endif

    if s:OS ==# 'windows'
        let pathsep = ';'
    else
        let pathsep = ':'
    endif
    let workspaces = split(s:gopath(), pathsep)
    let dirs += workspaces

    if dirs == []
        return []
    endif

    let ret = []
    for dir in dirs
        " Note:
        " Reject '_race' suffix because the directory is for binaries for
        " race detector.
        let roots = filter(split(expand(dir . '/pkg/' . s:OS . '_' . s:ARCH), "\n"), 'v:val !~# "_race$"')
        call add(roots, expand(dir . '/src'))
        for root in roots
            call extend(ret,
                \   map(
                \       map(
                \           split(globpath(root, '**/*.a'), "\n"),
                \           'substitute(v:val, ''\.a$'', "", "g")'
                \       ),
                \       'substitute(v:val, ''\\'', "/", "g")[len(root)+1:]'
                \   )
                \)
        endfor
    endfor
    return filter(ret, 'stridx(v:val, "/internal/") == -1')
endfunction

function! s:cmd_for(name) abort
    if exists('g:unite_source_go_import_' . a:name . '_cmd')
        return g:unite_source_go_import_{a:name}_cmd
    endif

    let camelized = toupper(a:name[0]) . a:name[1:]

    if exists(':' . camelized)
        let g:unite_source_go_import_{a:name}_cmd = camelized
        return camelized
    else
        " For vim-go
        let name = a:name =~# '^go' ? a:name[2:] : a:name
        let camelized = 'Go' . toupper(name[0]) . name[1:]

        if exists(':' . camelized)
            let g:unite_source_go_import_{a:name}_cmd = camelized
            return camelized
        endif
    endif

    return ''
endfunction

function! s:source.gather_candidates(args, context) abort
    if ! g:unite_source_go_import_disable_cache &&
                \ (empty(s:previous_result) || a:args == ['!'])
        let s:previous_result = map(s:go_packages(), '{
                                        \ "word" : v:val,
                                        \ }')
    endif
    return s:previous_result
endfunction

let s:source.action_table.import = {
            \ 'description' : 'Import Go package(s)',
            \ 'is_selectable' : 1,
            \ }

function! s:source.action_table.import.func(candidates) abort
    let cmd = s:cmd_for('import')
    if cmd ==# '' | return | endif

    for candidate in a:candidates
        execute cmd candidate.word
    endfor
endfunction

let s:source.action_table.import_as = {
            \ 'description' : 'Import Go package with local name',
            \ 'is_selectable' : 0,
            \ }

function! s:source.action_table.import_as.func(candidate) abort
    let local_name = input('Enter local name: ')
    if local_name ==# ''
        echo 'Canceled.'
        return
    endif

    let cmd = s:cmd_for('importAs')
    if cmd ==# '' | return | endif

    execute cmd local_name a:candidate.word
endfunction

let s:source.action_table.drop = {
            \ 'description' : 'Drop Go package(s)',
            \ 'is_selectable' : 1,
            \ }

function! s:source.action_table.drop.func(candidates) abort
    let cmd = s:cmd_for('drop')
    if cmd ==# '' | return | endif

    for candidate in a:candidates
        execute cmd candidate.word
    endfor
endfunction

let s:source.action_table.godoc = {
            \ 'description' : 'Show documentation for the package',
            \ 'is_selectable' : 0,
            \ }

function! s:source.action_table.godoc.func(candidate) abort
    let cmd = s:cmd_for('godoc')
    if cmd ==# '' | return | endif
    execute cmd a:candidate.word
endfunction

let s:source.action_table.godoc_browser = {
            \ 'description' : 'Show documentation for the package with browser',
            \ 'is_selectable' : 1,
            \ }

function! s:source.action_table.godoc_browser.func(candidates) abort
    if exists(':OpenBrowser')
        for c in a:candidates
            execute 'OpenBrowser' 'https://godoc.org/' . c.word
        endfor
        return
    endif

    let cmdline = ''
    if has('win32') || has('win64')
        let cmdline = '!start "https://godoc.org/%s"'
    elseif (has('mac') || has('macunix') || has('gui_macvim')) && executable('sw_vers')
        let cmdline = 'open "https://godoc.org/%s"'
    elseif executable('xdg-open')
        let cmdline = 'xdg-open "https://godoc.org/%s"'
    endif

    if cmdline ==# ''
        echohl ErrorMsg | echomsg 'No command was found to open a browser' | echohl None
        return
    endif

    for c in a:candidates
        let output = system(printf(cmdline, c.word))
        if v:shell_error
            echohl ErrorMsg | echomsg 'Error on opening a browser: ' . output | echohl None
            return
        endif
    endfor
endfunction

let s:source.action_table.preview = {
            \ 'description' : 'Preview the package with godoc',
            \ 'is_quit' : 0,
            \ }

function! s:source.action_table.preview.func(candidate) abort
    let cmd = s:cmd_for('godoc')
    if cmd ==# '' | return | endif
    let b = bufnr('%')

    execute cmd a:candidate.word
    setlocal previewwindow
    let bufnr = bufnr('%')

    let w = bufwinnr(b)
    execute w . 'wincmd w'

    if !buflisted(bufnr)
        call unite#add_previewed_buffer_list(bufnr)
    endif
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo

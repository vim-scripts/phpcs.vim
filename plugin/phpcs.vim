"#################################################################################
"
"       Filename:  phpcs.vim
"
"    Description:  PHP coding rules checking utility.
"
"   GVIM Version:  7.0+
"
"         Author:  Kai ZHANG
"          Email:  longbowk@yeah.net
"
"        Version:  1.1
"        License:  
"                  This program is free software; you can redistribute it and/or
"                  modify it under the terms of the GNU General Public License as
"                  published by the Free Software Foundation, version 2 of the
"                  License.
"                  This program is distributed in the hope that it will be
"                  useful, but WITHOUT ANY WARRANTY; without even the implied
"                  warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
"                  PURPOSE.
"                  See the GNU General Public License version 2 for more details.
"------------------------------------------------------------------------------
"  Configuration:  There are some personal details which should be configured
"                  1. Set the list of coding rule standards to follow.
"
"                       let g:phpcs_std_list="Zend,Streamwide"
"
"                  2. Set the VCS type(Only needed when running 'Phpcs commit')
"
"                       let g:phpcs_vcs_type = 'svn'
"
"                       Currently only support 'svn' or 'cvs'.
"
"                  3. Set the max allowed output lines. 
"                     This is useful in case there are too many errors and memory is running out.
"
"                       let g:phpcs_max_output = 0 " Unlimited output.
"
"                       or
"
"                       let g:phpcs_max_output = 2000 " Output limited to 2000 lines
"------------------------------------------------------------------------------
"  Modification History:
"  1.1  Fixed the issue that when minibufexpl plugin enabled, the window operation is totally wrong in DIFF mode. 
"  1.0  Initial release.
"------------------------------------------------------------------------------

if exists('g:loaded_phpcs_plugin')
    finish
endif
let g:loaded_phpcs_plugin = 1

" Unlimit output by default.
if ! exists('g:phpcs_max_output')
    let g:phpcs_max_output = 0
endif

" Load the configured standard list
if exists('g:phpcs_std_list')
    let s:std_list = split(g:phpcs_std_list, ',')
else
    " if standard not set, use default 'Zend'
    let s:std_list = ['Zend']     
endif

" The VCS supported
let s:vcs_supported = {
            \'svn' : "svn diff | grep '^Index' | cut -f2 -d' '",
            \'cvs' : "cvs status 2>/dev/null | grep 'File:' |egrep 'Merge|Modified'"
            \}

" If VCS type not set, use 'svn' as default
if !exists('g:phpcs_vcs_type')
    let g:phpcs_vcs_type = 'svn'
endif

if has_key(s:vcs_supported, g:phpcs_vcs_type)
    let s:vcs_lsco = s:vcs_supported[g:phpcs_vcs_type]
else
    echohl WarningMsg
    echomsg "VCS NOT SUPPORTED"
    echohl None
    finish
endif


" Get a phpcs result in emacs report format
function! s:runPhpcsCmd(std, filename, filters)
    if strlen(a:filename) == 0
        return []
    endif

    " strip all whitespace
    let std = substitute(a:std, "\\s", "", "g")

    let phpcs_output = system('phpcs --report=emacs --standard=' . std . ' ' . a:filename)
    let phpcs_result = split(phpcs_output, "\n")

    " run callback filters
    if !empty(a:filters)
        for filter in a:filters
            if !exists('*' . filter)
                continue
            endif
            let Callback = function(filter)

            let phpcs_list = []
            for item in phpcs_result
                if 0 != Callback(item)
                    let phpcs_list = add(phpcs_list, item)
                endif
            endfor
            let phpcs_result = phpcs_list
        endfor
    endif

    return phpcs_result
endfunction

" The wrapper Phpcs function
function! s:doCheck(fname_list, std_list, filter_list)
    let g:phpcs_checking = 1

    " run phpcs on the files
    let cs_list = []
    try
        for fname in a:fname_list
            for std in a:std_list
                let cs_list += s:runPhpcsCmd(std, fname, a:filter_list)

                if g:phpcs_max_output > 0 && len(cs_list) >= g:phpcs_max_output
                    throw "Exp_MaxOutPutReached"
                endif
            endfor
        endfor
    catch /Exp_MaxOutPutReached/
        let cs_list = cs_list[:phpcs_max_output-1]
    endtry

    return cs_list
endfunction

" Filter the line in VIM DIFF mode
function! s:diffModeFilter(cs_line)
    let cs = split(a:cs_line, ':')

    return diff_hlID(str2nr(cs[1]), str2nr(cs[2]))
endfunction

function! s:compare(l1, l2)
    let cs1 = split(a:l1, ':')
    let cs2 = split(a:l2, ':')

    if cs1[0] == cs2[0]
        return str2nr(cs1[1]) - str2nr(cs2[1])
    else
        return cs1[0] < cs2[0] ? -1 : 1
    endif
endfunction

function! s:sort(cs_list)
  let sortedList = sort(a:cs_list, 's:compare')
  let uniqedList = []

  let last = ''
  for item in sortedList
    if item !=# last
      call add(uniqedList, item)
      let last = item
    endif
  endfor

  return uniqedList
endfunction


" If argument == 'commit', then check all files changed recursively.
" If argument == 'all', then check all files in current directory recursively.
" If argument not and DIFF mode off, check the current editing file only.
" If argument not and DIFF mode on, check the modified lines in current file.
function! phpcs#phpcsCheck(...)
    let fname_list = []
    let filter_list = []

    " close quickfix windows(help getting the correct &diff)
    cclose

    if a:0 == 0
        if !&diff
            let fname_list = add(fname_list, @%)
        else
            " Make sure there is only 2 windows exists in diff view:
            "  * the 1st window displays the original file
            "  * the 2nd window displays the modified file.
            " So we can use the wincmd with number(1,2) directly.
            " If you have plugins open extra window by default, you should
            " close these window here.
            " Some people use MiniBufExplorer plugin, so close it first.
            if exists(':CMiniBufExplorer') 
                execute 'CMiniBufExplorer'
            endif

            if exists('g:phpcs_checking')
                vsplit
                execute '1' . 'wincmd w'
                buffer 1
                execute '2' . 'wincmd w'
                buffer 2
                diffupdate
                unlet g:phpcs_checking
                return
            endif

            execute '1' . 'wincmd w'
            hide

            let fname_list = add(fname_list, @%)
            let filter_list = ['s:diffModeFilter']
        endif
    elseif a:1 == 'commit'
        let fname_commit = system(s:vcs_lsco)
        let fname_list = split(fname_commit, "\n")
    elseif a:1 == 'all'
        let fname_all = system('find . -path "*/.svn" -prune -o -iname "*.php" -print')
        let fname_list = split(fname_all, "\n")
    else
        echohl ErrorMsg
        echomsg "ARGUMENTS NOT SUPPORTED"
        echohl None
        return
    endif
    
    let cs_list = s:doCheck(fname_list, s:std_list, filter_list)
    if empty(cs_list)
        echohl MoreMsg
        echomsg "CODING RULES OK"
        echohl None
        return
    endif

    " Sort and Unique
    let cs_list = s:sort(cs_list)

    " show result
    let errfmt_saved=&errorformat
    set errorformat=%f:%l:%c:\ %t%*[a-zA-Z]\ -\ %m
    cexpr cs_list
    set errorformat=errfmt_saved
    cwindow
endfunction

" Define the Phpcs command
command! -nargs=? Phpcs call phpcs#phpcsCheck(<f-args>)

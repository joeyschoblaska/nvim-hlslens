local M = {}
local fn = vim.fn
local api = vim.api
local cmd = vim.cmd
local uv = vim.loop

M.has06 = (function()
    local has06
    return function()
        if has06 == nil then
            has06 = fn.has('nvim-0.6') == 1
        end
        return has06
    end
end)()

M.has08 = (function()
    local has08
    return function()
        if has08 == nil then
            has08 = fn.has('nvim-0.8') == 1
        end
        return has08
    end
end)()

M.isWindows = (function()
    local cache
    return function()
        if cache == nil then
            cache = uv.os_uname().sysname == 'Windows_NT'
        end
        return cache
    end
end)()

M.jitEnabled = (function()
    local enabled
    return function()
        if enabled == nil then
            enabled = jit ~= nil and (not M.isWindows() or M.has06())
        end
        return enabled
    end
end)()

function M.binSearch(items, element, comp)
    vim.validate({items = {items, 'table'}, comp = {comp, 'function'}})
    local min, max, mid = 1, #items, 1
    local r = 0
    while min <= max do
        mid = math.floor((min + max) / 2)
        r = comp(items[mid], element)
        if r == 0 then
            return mid
        elseif r > 0 then
            max = mid - 1
        else
            min = mid + 1
        end
    end
    return -min
end

function M.comparePosition(p1, p2)
    if p1[1] == p2[1] then
        if p1[2] == p2[2] then
            return 0
        else
            return p1[2] > p2[2] and 1 or -1
        end
    else
        return p1[1] > p2[1] and 1 or -1
    end
end

function M.getWinInfo(winid)
    local winfos = fn.getwininfo(winid)
    assert(type(winfos) == 'table' and #winfos == 1,
           '`getwininfo` expected 1 table with single element.')
    return winfos[1]
end

function M.textoff(winid)
    vim.validate({winid = {winid, 'number'}})
    local textoff
    if M.has06() then
        textoff = M.getWinInfo(winid).textoff
    end

    if not textoff then
        M.winExecute(winid, function()
            local wv = fn.winsaveview()
            api.nvim_win_set_cursor(winid, {wv.lnum, 0})
            textoff = fn.wincol() - 1
            fn.winrestview(wv)
        end)
    end
    return textoff
end

function M.isCmdLineWin(bufnr)
    local function isCmdWin()
        return fn.bufname() == '[Command Line]'
    end

    return bufnr and api.nvim_buf_call(bufnr, isCmdWin) or isCmdWin()
end

function M.vcol(winid, pos)
    local vcol = fn.virtcol(pos)
    if not vim.wo[winid].wrap then
        M.winExecute(winid, function()
            vcol = vcol - fn.winsaveview().leftcol
        end)
    end
    return vcol
end

function M.hlAttrs(hlgroup)
    vim.validate({hlgroup = {hlgroup, 'string'}})
    local attrTbl = {
        'bold', 'standout', 'underline', 'undercurl', 'italic', 'reverse', 'strikethrough'
    }
    local t = {}
    local hl2tbl = function(gui)
        local ok, hl = pcall(api.nvim_get_hl_by_name, hlgroup, gui)
        if not ok then
            return
        end
        local fg, bg, colorFmt = hl.foreground, hl.background, gui and '#%x' or '%s'
        if fg then
            t[gui and 'guifg' or 'ctermfg'] = colorFmt:format(fg)
        end
        if bg then
            t[gui and 'guibg' or 'ctermbg'] = colorFmt:format(bg)
        end
        hl.foreground, hl.background = nil, nil
        local attrs = {}
        for attr in pairs(hl) do
            if vim.tbl_contains(attrTbl, attr) then
                table.insert(attrs, attr)
            end
        end
        t[gui and 'gui' or 'cterm'] = #attrs > 0 and attrs or nil
    end
    hl2tbl(true)
    hl2tbl(false)
    return t
end

function M.matchaddpos(hlgroup, plist, prior, winid)
    vim.validate({
        hlgroup = {hlgroup, 'string'},
        plist = {plist, 'table'},
        prior = {prior, 'number', true},
        winid = {winid, 'number'}
    })
    prior = prior or 10

    local ids = {}
    local l = {}
    for i, p in ipairs(plist) do
        table.insert(l, p)
        if i % 8 == 0 then
            table.insert(ids, fn.matchaddpos(hlgroup, l, prior, -1, {window = winid}))
            l = {}
        end
    end
    if #l > 0 then
        table.insert(ids, fn.matchaddpos(hlgroup, l, prior, -1, {window = winid}))
    end
    return ids
end

function M.killableDefer(timer, func, delay)
    vim.validate({
        timer = {timer, 'userdata', true},
        func = {func, 'function'},
        delay = {delay, 'number'}
    })
    if timer and timer:has_ref() then
        timer:stop()
        if not timer:is_closing() then
            timer:close()
        end
    end
    timer = uv.new_timer()
    timer:start(delay, 0, function()
        vim.schedule(function()
            if not timer:has_ref() then
                return
            end
            timer:stop()
            if not timer:is_closing() then
                timer:close()
            end
            func()
        end)
    end)
    return timer
end

function M.winExecute(winid, func)
    vim.validate({
        winid = {
            winid, function(w)
                return w and api.nvim_win_is_valid(w)
            end, 'a valid window'
        },
        func = {func, 'function'}
    })

    local curWinid = api.nvim_get_current_win()
    local noaSetWin = 'noa call nvim_set_current_win(%d)'
    if curWinid ~= winid then
        cmd(noaSetWin:format(winid))
    end
    local ret = func()
    if curWinid ~= winid then
        cmd(noaSetWin:format(curWinid))
    end
    return ret
end

return M

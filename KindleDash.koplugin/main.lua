-- Shawn Kanban — 越狱 Kindle 常驻看板插件
-- 拉取 PC/Mac 上 kindle-dash 服务的 /api/dashboard，渲染到墨水屏，
-- 每个整点/半点自动刷新（如 08:30、09:00）。
-- 模块化线框布局：Shawn Kanban 标题 → Token Usage → 天气/股市/汇率/时钟/更新。
-- 两列内容右列从中线开始；内容超宽时自动降字号。
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local CenterContainer = require("ui/widget/container/centercontainer")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local Font = require("ui/font")
local Blitbuffer = require("ffi/blitbuffer")
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local http = require("socket.http")
local json = require("json")
local logger = require("logger")

local REFRESH_SEC = 30 * 60 -- 自动刷新间隔：30 分钟
local DEFAULT_HOST = "192.168.31.188"
local DEFAULT_PORT = "8787"
local SIZES = { 26, 24, 22, 20, 18 } -- 候选字号，从大到小，超宽自动降

local KindleDash = WidgetContainer:new{
    name = "KindleDash",
    is_doc_only = false,
    sorting_hint = "tools", -- 归到「工具」分组
}

function KindleDash:init()
    self.auto_on = true
    self.host = self:loadHost()
    self.dash_widget = nil
    self._auto_timer = nil
    self.font_size = 26
    self.colw = 27
    self:armAutoRefresh()
    self.ui.menu:registerToMainMenu(self)
end

-- ---------- 设置持久化 ----------
function KindleDash:settingsPath()
    return DataStorage:getSettingsDir() .. "/kindledash.lua"
end
function KindleDash:loadHost()
    local host, port = DEFAULT_HOST, DEFAULT_PORT
    local ok, s = pcall(function() return LuaSettings:open(self:settingsPath()) end)
    if ok and s then
        if s:has("host") then host = s:readSetting("host") or DEFAULT_HOST end
        if s:has("port") then port = s:readSetting("port") or DEFAULT_PORT end
    end
    -- host 可能是 "IP"、"IP:port" 或 "IP" + 单独存了 port
    if host and not host:find(":", 1, true) then
        host = host .. ":" .. port
    end
    return host
end
function KindleDash:saveHost(host)
    local ok, s = pcall(function() return LuaSettings:open(self:settingsPath()) end)
    if ok and s then
        s:saveSetting("host", host)
        local h, p = host:match("^(.-):(%d+)$")
        if h and p then
            s:saveSetting("host", h)
            s:saveSetting("port", p)
        end
        s:flush()
    end
    self.host = host
end

-- ---------- 网络拉取 ----------
function KindleDash:fetchDashboard()
    local url = "http://" .. self.host .. "/api/dashboard"
    local body, code = http.request(url)
    if not body or code ~= 200 then
        return nil, "fetch failed (" .. tostring(code) .. ")"
    end
    local ok, data = pcall(json.decode, body)
    if not ok then
        return nil, "bad json"
    end
    return data, nil
end

-- ---------- 文本工具 ----------
local num = function(v, d)
    if v == nil then return "n/a" end
    if d then return string.format("%." .. d .. "f", v) end
    return tostring(v)
end
local pct = function(v)
    if v == nil then return "" end
    return num(math.abs(v), 1) .. "%" -- 符号由 sign 提供
end
local priceText = function(v)
    if v == nil then return "?" end
    return num(v, v >= 1000 and 1 or 2)
end

-- 中英文混排宽度补空格（中文按 2 格计）
local function padText(s, width)
    s = tostring(s)
    local len = 0
    for u in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        len = len + (#u > 1 and 2 or 1)
    end
    return s .. string.rep(" ", math.max(0, width - len))
end

-- 估算一行文本在字号 sz 下的像素宽度（CJK=sz，ASCII=sz/2）
local function textWidth(line, sz)
    local w, half = 0, sz / 2
    for u in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        w = w + (#u > 1 and sz or half)
    end
    return w
end

local function stockCell(s)
    local mkt = s.mkt == "US" and "美" or (s.mkt == "A" and "A" or " ")
    local sign = s.changePct == nil and "" or (s.changePct >= 0 and "+" or "-")
    return string.format("%s %s %s %s%s",
        mkt, tostring(s.label or s.sym), priceText(s.price),
        sign, s.changePct == nil and "" or pct(s.changePct))
end
local function clockCell(c)
    return string.format("%s %s %s", tostring(c.city), tostring(c.time), tostring(c.date))
end

-- 生成各模块文本。self.colw 已由 chooseSize 按字号算好。
function KindleDash:buildModuleTexts(d)
    local colw = self.colw
    local fullw = 2 * colw + 1 -- 两列 + 1 分隔空格 = 固定行宽
    local function col2full(left, right)
        return padText(left, colw) .. " " .. padText(right, colw)
    end
    local q = d.quotas or {}
    local w = d.weather or {}
    local st = (d.stocks and d.stocks.items) or {}
    local fx = d.fx or {}
    local cl = (d.clocks and d.clocks.items) or {}

    -- Token Usage
    local tok = {}
    local wb = q.workbuddy or {}
    if wb.ok then
        local t = wb.token or {}
        table.insert(tok, padText(string.format("WorkBuddy %s/%s (%d%%)",
            tostring(t.remaining or "?"), tostring(t.size or "?"), t.percent or 0), fullw))
    else
        table.insert(tok, padText("WorkBuddy 不可用", fullw))
    end
    local cc = q.claudecode or {}
    local cx = q.codex or {}
    table.insert(tok, col2full(
        string.format("ClaudeCode %s/%s", tostring(cc.used7d or "?"), tostring(cc.cap or "?")),
        string.format("Codex %s/%s", tostring(cx.used7d or "?"), tostring(cx.cap or "?"))))

    -- 天气
    local wea = {}
    if w.ok then
        table.insert(wea, padText(string.format("%s  %s %s°C  高%s 低%s 湿%s%%",
            tostring(w.city or ""), tostring(w.text or ""), tostring(w.temp or "?"),
            tostring(w.high or "?"), tostring(w.low or "?"), tostring(w.humidity or "?")), fullw))
    else
        table.insert(wea, padText("天气 不可用", fullw))
    end

    -- 股市（两列，右列从中线开始）
    local stk = {}
    for i = 1, #st, 2 do
        table.insert(stk, col2full(stockCell(st[i]), st[i + 1] and stockCell(st[i + 1]) or ""))
    end

    -- 汇率
    local fxx = {}
    table.insert(fxx, col2full("CNY " .. num(fx.cny, 3), "INR " .. num(fx.inr, 3)))

    -- 时钟（两列）
    local clk = {}
    for i = 1, #cl, 2 do
        table.insert(clk, col2full(clockCell(cl[i]), cl[i + 1] and clockCell(cl[i + 1]) or ""))
    end

    -- 更新
    local upd = { padText("更新 " .. os.date("%H:%M:%S") .. "  顶部下滑返回", fullw) }

    local function moduleText(title, lines)
        local all = { padText(title, fullw) }
        for _, l in ipairs(lines) do
            table.insert(all, l)
        end
        return table.concat(all, "\n")
    end

    return {
        { title = "TOKEN USAGE", text = moduleText("TOKEN USAGE", tok) },
        { title = "天气", text = moduleText("天气", wea) },
        { title = "股市", text = moduleText("股市", stk) },
        { title = "汇率", text = moduleText("汇率", fxx) },
        { title = "时钟", text = moduleText("时钟", clk) },
        { title = "更新", text = moduleText("更新", upd) },
    }
end

-- 选择字号：从大到小试，直到 ①所有行宽 ≤ 可用宽 ②模块总高 ≤ 可用高
function KindleDash:chooseSize(data, availW, availH)
    for _, sz in ipairs(SIZES) do
        local half = math.max(1, math.floor(sz / 2))
        self.colw = math.floor((availW - half) / 2 / half)
        local mods = self:buildModuleTexts(data)
        local ok, totalLines = true, 0
        for _, m in ipairs(mods) do
            for line in (m.text or ""):gmatch("[^\n]+") do
                totalLines = totalLines + 1
                if textWidth(line, sz) > availW then
                    ok = false
                    break
                end
            end
            if not ok then break end
        end
        if ok then
            local lineH = math.ceil(sz * 1.3)
            local titleH = math.ceil((sz + 2) * 1.3)
            -- 每个模块边框+padding+margin 实际开销 ≈ 10px（border1*2+padding2*2+margin2*2）
            local totalH = titleH + totalLines * lineH + #mods * 10
            if totalH <= availH then
                return sz
            end
        end
    end
    return SIZES[#SIZES]
end

-- ---------- 展示（线框模块；手势全部吃掉防退出，返回键关闭） ----------
function KindleDash:showDashboard(data)
    if self.dash_widget then
        UIManager:close(self.dash_widget)
        self.dash_widget = nil
    end
    local scr = self.ui.dimen
    local w = scr and scr.w or 600
    local h = scr and scr.h or 800
    local pad = 12

    local sz = self:chooseSize(data, w - 2 * pad, h - 2 * pad)
    self.font_size = sz
    local mods = self:buildModuleTexts(data)
    local face = Font:getFace("ffont", sz)
    local titleFace = Font:getFace("ffont", sz + 2)

    -- 垂直堆叠：标题 + 各线框模块
    local vg = VerticalGroup:new{ align = "left" }
    table.insert(vg, FrameContainer:new{
        bordersize = 0,
        padding = 2,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        TextWidget:new{ text = "SHAWN KANBAN", face = titleFace },
    })
    for _, m in ipairs(mods) do
        -- 多行文本必须用 TextBoxWidget（TextWidget 只支持单行）
        local tw = TextBoxWidget:new{ text = m.text, face = face, width = w - 4 }
        local frame = FrameContainer:new{
            bordersize = 1,
            padding = 2,
            margin = 2,
            background = Blitbuffer.COLOR_WHITE,
            tw,
        }
        table.insert(vg, frame)
    end

    -- 全屏白底 + 内容垂直居中（尺寸由 center=全屏 决定，无需给 FrameContainer 设 dimen）
    local center = CenterContainer:new{
        dimen = Geom:new{ w = w, h = h },
        vg,
    }
    local bg = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        center,
    }

    local container = InputContainer:new{
        dimen = Geom:new{ w = w, h = h },
    }
    container[1] = bg
    container.ges_events = {
        TapScroll = {
            GestureRange:new{ ges = "tap", range = function() return container.dimen end },
        },
        SwipeScroll = {
            GestureRange:new{ ges = "swipe", range = function() return container.dimen end },
        },
    }
    function container:onTapScroll(_, ges)
        -- 点击顶部 = 返回（Kindle 无实体返回键，KOReader 靠顶部手势返回）
        if ges and ges.pos and ges.pos.y < h * 0.1 then
            container:onClose()
        end
        return true -- 其余 tap 吃掉防穿透
    end
    function container:onSwipeScroll(_, ges)
        -- 从顶部开始下滑 = 返回；其余滑动吃掉（防穿透，内容一屏无需滚动）
        if ges and ges.pos and ges.direction == "south" and ges.pos.y < h * 0.25 then
            container:onClose()
        end
        return true
    end
    function container:onClose()
        UIManager:close(self)
        return true
    end
    function container:onBack()
        UIManager:close(self)
        return true
    end
    self.dash_widget = container
    UIManager:show(container)
end

function KindleDash:refreshDashboard(silent)
    local data, err = self:fetchDashboard()
    if not data then
        if not silent then
            UIManager:show(InfoMessage:new{ text = "刷新失败: " .. tostring(err), timeout = 3 })
        end
        logger.warn("ShawnKanban refresh failed:", err)
        return
    end
    self:showDashboard(data)
end

-- ---------- 自动刷新（对齐整点/半点，如 08:30、09:00） ----------
local function secondsToNextSlot()
    local t = os.date("*t")
    local mins = t.min
    local target = mins < 30 and 30 or 60
    return (target - mins) * 60 - t.sec
end

function KindleDash:armAutoRefresh()
    if not self.auto_on then return end
    local function tick()
        if not self.auto_on then return end
        self:refreshDashboard(true) -- 静默刷新；看板若开着则原地更新
        self._auto_timer = UIManager:scheduleIn(REFRESH_SEC, tick)
    end
    local first = secondsToNextSlot()
    if first < 30 then first = first + REFRESH_SEC end
    self._auto_timer = UIManager:scheduleIn(first, tick)
end
function KindleDash:toggleAutoRefresh()
    self.auto_on = not self.auto_on
    if self.auto_on then
        self:armAutoRefresh()
        UIManager:show(InfoMessage:new{ text = "自动刷新: 开 (整点/半点)", timeout = 2 })
    else
        UIManager:show(InfoMessage:new{ text = "自动刷新: 关", timeout = 2 })
    end
end

-- ---------- 菜单 ----------
function KindleDash:setServerAddress()
    local dialog
    dialog = InputDialog:new{
        title = "服务器地址 (IP:端口)",
        input = self.host,
        input_hint = "例如 192.168.31.188:8787",
        buttons = {
            {
                {
                    text = "取消", callback = function()
                        UIManager:close(dialog)
                    end
                },
                {
                    text = "保存", callback = function()
                        local v = dialog:getInputValue()
                        if v and v ~= "" then
                            self:saveHost(v)
                            UIManager:close(dialog)
                            UIManager:show(InfoMessage:new{ text = "已保存: " .. v, timeout = 2 })
                        end
                    end
                }
            }
        }
    }
    UIManager:show(dialog)
end

function KindleDash:addToMainMenu(menu_items)
    menu_items.kindledash = {
        text = "Shawn Kanban",
        sorting_hint = "tools",
        callback = function()
            self:refreshDashboard(false)
        end,
        submenus = {
            {
                text = "刷新看板",
                callback = function() self:refreshDashboard(false) end
            },
            {
                text = "设置服务器地址",
                callback = function() self:setServerAddress() end
            },
            {
                text = "切换自动刷新 (整点/半点)",
                callback = function() self:toggleAutoRefresh() end
            },
            {
                text = "关于",
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = "Shawn Kanban\n拉取 PC/Mac 的 /api/dashboard\n含限额/天气/股市/时钟/汇率\n整点/半点自动刷新，返回键关闭",
                        timeout = 5
                    })
                end
            }
        }
    }
end

return KindleDash

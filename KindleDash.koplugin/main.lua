-- Shawn Kanban — 越狱 Kindle 常驻看板插件
-- 拉取 PC/Mac 上 kindle-dash 服务的 /api/dashboard，渲染到墨水屏，
-- 每个整点/半点自动刷新（如 08:30、09:00）。
-- 模块化线框布局：Shawn Kanban 标题 → Token Usage → 天气/股市/汇率/时钟/更新。
-- 两列内容严格中线对齐：左列右对齐到中线 + 右列左对齐从中线开始。
-- 模块标题用粗体（tfont=NotoSans-Bold）；内容超宽时自动降字号。
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local CenterContainer = require("ui/widget/container/centercontainer")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local Font = require("ui/font")
local Screen = require("device").screen  -- 用于 scaleBySize（face.size 物理 = scaleBySize(逻辑)）
local Blitbuffer = require("ffi/blitbuffer")
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local http = require("socket.http")
local json = require("json")
local logger = require("logger")

local REFRESH_SEC = 30 * 60
local DEFAULT_HOST = "192.168.31.188"
local DEFAULT_PORT = "8787"
-- 字号候选（逻辑像素，Font:getFace 内部 Screen:scaleBySize 缩放为物理）。
-- PW3 scaleBySize 系数 ≈ 1.416。从大到小试，选最大能装下且撑满屏的字号。
local SIZES = { 30, 28, 26, 24, 22, 20, 18, 16 }

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
    self.font_size = 22
    self.colwW = 500       -- 每列物理像素宽，由 chooseSize 设置
    self.colw_gap = 4      -- 中线两侧空隙
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

-- 估算文本在字号 physSz 下的像素宽度（CJK=physSz，ASCII=physSz/2）
local function textWidth(line, physSz)
    local w, half = 0, physSz / 2
    for u in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        w = w + (#u > 1 and physSz or half)
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

-- 生成各模块结构化数据。每行：{kind="single", text=...} 或 {kind="double", left=..., right=...}。
-- double 行在 showDashboard 中用 HorizontalGroup + 左右两个 TextBoxWidget 严格中线对齐。
function KindleDash:buildModules(d)
    local q = d.quotas or {}
    local w = d.weather or {}
    local st = (d.stocks and d.stocks.items) or {}
    local fx = d.fx or {}
    local cl = (d.clocks and d.clocks.items) or {}

    local function single(text) return { kind = "single", text = text } end
    local function double(left, right) return { kind = "double", left = left, right = right or "" } end

    -- Token Usage（标题混合大小写，不再全大写）
    local tok = {}
    local wb = q.workbuddy or {}
    if wb.ok then
        local t = wb.token or {}
        table.insert(tok, single(string.format("WorkBuddy %s/%s (%d%%)",
            tostring(t.remaining or "?"), tostring(t.size or "?"), t.percent or 0)))
    else
        table.insert(tok, single("WorkBuddy 不可用"))
    end
    local cc = q.claudecode or {}
    local cx = q.codex or {}
    table.insert(tok, double(
        string.format("ClaudeCode %s/%s", tostring(cc.used7d or "?"), tostring(cc.cap or "?")),
        string.format("Codex %s/%s", tostring(cx.used7d or "?"), tostring(cx.cap or "?"))))

    -- 天气
    local wea = {}
    if w.ok then
        table.insert(wea, single(string.format("%s  %s %s°C  高%s 低%s 湿%s%%",
            tostring(w.city or ""), tostring(w.text or ""), tostring(w.temp or "?"),
            tostring(w.high or "?"), tostring(w.low or "?"), tostring(w.humidity or "?"))))
    else
        table.insert(wea, single("天气 不可用"))
    end

    -- 股市
    local stk = {}
    for i = 1, #st, 2 do
        table.insert(stk, double(stockCell(st[i]), st[i + 1] and stockCell(st[i + 1]) or ""))
    end

    -- 汇率
    local fxx = {}
    table.insert(fxx, double("CNY " .. num(fx.cny, 3), "INR " .. num(fx.inr, 3)))

    -- 时钟
    local clk = {}
    for i = 1, #cl, 2 do
        table.insert(clk, double(clockCell(cl[i]), cl[i + 1] and clockCell(cl[i + 1]) or ""))
    end

    -- 更新
    local upd = { single("更新 " .. os.date("%H:%M:%S") .. "  顶部下滑返回") }

    return {
        { title = "Token Usage", lines = tok },
        { title = "天气",        lines = wea },
        { title = "股市",        lines = stk },
        { title = "汇率",        lines = fxx },
        { title = "时钟",        lines = clk },
        { title = "更新",        lines = upd },
    }
end

-- 选择字号：从大到小试，选最大能装下且总高 ≤ availH 的字号。
-- 关键：Font:getFace(size) 内部 Screen:scaleBySize(size) → 物理 size = 逻辑 × ~1.416
-- textWidth 用物理 sz 算（与渲染一致）；single 行宽=tbw，double 每列宽=colwW（严格中线对齐）
function KindleDash:chooseSize(data, availW, availH)
    local gap = 4  -- 中线两侧 2+2 像素空隙
    local tbw = availW - 4                      -- 单行 TextBoxWidget width
    local colwW = math.floor((availW - gap) / 2) -- 每列物理宽（严格中线对齐）
    for _, sz in ipairs(SIZES) do
        local physSz = Screen:scaleBySize(sz)
        local titlePhysSz = Screen:scaleBySize(sz + 2)
        local mods = self:buildModules(data)
        local ok, totalLines = true, 0
        for _, m in ipairs(mods) do
            totalLines = totalLines + 1  -- 标题行
            if textWidth(m.title, titlePhysSz) > tbw then ok = false; break end
            for _, line in ipairs(m.lines) do
                totalLines = totalLines + 1
                if line.kind == "single" then
                    if textWidth(line.text, physSz) > tbw then ok = false; break end
                else
                    if textWidth(line.left, physSz) > colwW or textWidth(line.right, physSz) > colwW then
                        ok = false; break
                    end
                end
            end
            if not ok then break end
        end
        if ok then
            local lineH = math.ceil(physSz * 1.3)
            local titleH = math.ceil(titlePhysSz * 1.3)
            -- 每个模块：标题 + 内容行 + 边框/padding/margin 开销 ≈ 16px
            local totalH = titleH + totalLines * lineH + #mods * 16
            if totalH <= availH then
                self.colwW = colwW
                self.colw_gap = gap
                return sz
            end
        end
    end
    -- 全部装不下时取最小字号
    self.colwW = colwW
    self.colw_gap = gap
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
    local pad = 8

    local sz = self:chooseSize(data, w - 2 * pad, h - 2 * pad)
    self.font_size = sz
    local mods = self:buildModules(data)
    local face = Font:getFace("ffont", sz)
    local titleFace = Font:getFace("tfont", sz)        -- 模块标题粗体（tfont=NotoSans-Bold）
    local mainTitleFace = Font:getFace("tfont", sz + 4) -- 主标题更大粗体

    local colwW = self.colwW
    local gap = self.colw_gap
    local tbw = w - 2 * pad - 4  -- 单行 TextBoxWidget width

    -- 计算实际总高，把剩余空间分配给模块间距（撑满屏幕）
    local physSz = Screen:scaleBySize(sz)
    local titlePhysSz = Screen:scaleBySize(sz + 2)
    local mainTitlePhysSz = Screen:scaleBySize(sz + 4)
    local lineH = math.ceil(physSz * 1.3)
    local titleH = math.ceil(titlePhysSz * 1.3)
    local mainTitleH = math.ceil(mainTitlePhysSz * 1.3)
    local totalLines = 0
    for _, m in ipairs(mods) do totalLines = totalLines + 1 + #m.lines end
    local baseModuleOverhead = 16  -- border1*2 + padding4*2 + margin2*2
    local totalH = mainTitleH + totalLines * lineH + #mods * baseModuleOverhead
    local availH = h - 2 * pad
    local extra = math.max(0, availH - totalH)
    -- 每模块额外 margin（上下分摊）+ padding 增加
    local extraPerMod = math.floor(extra / #mods)
    local modMargin = 2 + math.floor(extraPerMod / 2)
    local modPadding = 4 + math.floor(extraPerMod / 4)

    local vg = VerticalGroup:new{ align = "left" }
    -- 主标题（粗体）
    table.insert(vg, TextWidget:new{ text = "Shawn Kanban", face = mainTitleFace })

    for _, m in ipairs(mods) do
        local modVg = VerticalGroup:new{ align = "left" }
        -- 模块标题（粗体，左对齐）
        table.insert(modVg, TextBoxWidget:new{
            text = m.title, face = titleFace, width = tbw, alignment = "left",
        })
        -- 内容行
        for _, line in ipairs(m.lines) do
            if line.kind == "single" then
                table.insert(modVg, TextBoxWidget:new{
                    text = line.text, face = face, width = tbw, alignment = "left",
                })
            else
                -- 两列严格中线对齐：左列右对齐到中线 + 右列左对齐从中线开始
                local hg = HorizontalGroup:new{ align = "center" }
                table.insert(hg, TextBoxWidget:new{
                    text = line.left, face = face, width = colwW, alignment = "right",
                })
                table.insert(hg, TextBoxWidget:new{
                    text = line.right, face = face, width = colwW, alignment = "left",
                })
                table.insert(modVg, hg)
            end
        end
        local frame = FrameContainer:new{
            bordersize = 1,
            padding = modPadding,
            margin = modMargin,
            background = Blitbuffer.COLOR_WHITE,
            modVg,
        }
        table.insert(vg, frame)
    end

    -- 全屏白底 + 内容垂直居中
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
                        text = "Shawn Kanban\n拉取 PC/Mac 的 /api/dashboard\n含限额/天气/股市/时钟/汇率\n整点/半点自动刷新，顶部下滑返回",
                        timeout = 5
                    })
                end
            }
        }
    }
end

return KindleDash

-- KindleDash — 越狱 Kindle 常驻看板插件
-- 拉取 PC/Mac 上 kindle-dash 服务的 /api/dashboard，渲染到墨水屏，每 30 分钟自动刷新。
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local TextViewer = require("ui/widget/textviewer")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local http = require("socket.http")
local json = require("json")
local logger = require("logger")

local REFRESH_SEC = 30 * 60 -- 自动刷新间隔：30 分钟
local DEFAULT_HOST = "192.168.31.188"
local DEFAULT_PORT = "8787"

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

-- ---------- 文本渲染 ----------
local function num(v, d)
    if v == nil then return "n/a" end
    if d then return string.format("%." .. d .. "f", v) end
    return tostring(v)
end
local function pct(v)
    if v == nil then return "" end
    return (v > 0 and "+" or "") .. num(v, 1) .. "%"
end

function KindleDash:renderText(d)
    local L = {}
    local q = d.quotas or {}

    table.insert(L, "=== 限额 QUOTA ===")
    local wb = q.workbuddy or {}
    if wb.ok then
        local t = wb.token or {}
        table.insert(L, string.format("WorkBuddy  %s", tostring(wb.model or "?")))
        table.insert(L, string.format("   剩余 %s / %s  (%.1f%%)",
            tostring(t.remaining or "?"), tostring(t.size or "?"), t.percent or 0))
    else
        table.insert(L, "WorkBuddy  不可用 (" .. tostring(wb.error or "") .. ")")
    end
    local cc = q.claudecode or {}
    table.insert(L, string.format("ClaudeCode  本周 %s / %s%s",
        tostring(cc.used7d or "?"), tostring(cc.cap or "?"),
        cc.ok and "" or "  (本地统计)"))
    local cx = q.codex or {}
    table.insert(L, string.format("Codex       本周 %s / %s%s",
        tostring(cx.used7d or "?"), tostring(cx.cap or "?"),
        cx.ok and "" or "  (本地统计)"))

    local w = d.weather or {}
    table.insert(L, "")
    table.insert(L, "=== 天气 WEATHER ===")
    if w.ok then
        table.insert(L, string.format("%s  %s %s°C", tostring(w.city or ""),
            tostring(w.text or ""), tostring(w.temp or "?")))
        table.insert(L, string.format("   高%s / 低%s  湿%s%%",
            tostring(w.high or "?"), tostring(w.low or "?"), tostring(w.humidity or "?")))
    else
        table.insert(L, "不可用 (" .. tostring(w.error or "") .. ")")
    end

    local st = (d.stocks and d.stocks.items) or {}
    table.insert(L, "")
    table.insert(L, "=== 股市 MARKETS ===")
    for _, s in ipairs(st) do
        local mkt = s.mkt == "US" and "美" or (s.mkt == "A" and "A" or " ")
        local arrow = s.changePct == nil and "" or (s.changePct >= 0 and "↑" or "↓")
        table.insert(L, string.format("%s %s[%s] %s %s", mkt, tostring(s.label or s.sym),
            tostring(s.sym), tostring(s.price or "?"),
            s.changePct == nil and "" or arrow .. pct(s.changePct)))
    end

    local fx = d.fx or {}
    table.insert(L, "")
    table.insert(L, "=== 汇率 FX (1 " .. tostring(fx.base or "USD") .. ") ===")
    table.insert(L, string.format("人民币 CNY  %s", num(fx.cny, 3)))
    table.insert(L, string.format("卢比   INR  %s", num(fx.inr, 3)))

    local cl = (d.clocks and d.clocks.items) or {}
    table.insert(L, "")
    table.insert(L, "=== 世界时钟 CLOCKS ===")
    for _, c in ipairs(cl) do
        table.insert(L, string.format("%s  %s  %s", tostring(c.city),
            tostring(c.time), tostring(c.date)))
    end

    table.insert(L, "")
    table.insert(L, "更新 " .. os.date("%H:%M:%S") .. "  源 " .. tostring(self.host))
    return table.concat(L, "\n")
end

-- ---------- 展示 ----------
function KindleDash:showDashboard(data, silent)
    local text = self:renderText(data)
    if self.dash_widget then
        UIManager:close(self.dash_widget)
        self.dash_widget = nil
    end
    local viewer = TextViewer:new{
        title = "Kindle Dash",
        text = text,
        text_type = "general",
        width = self.ui.dimen and self.ui.dimen.w or 600,
        height = self.ui.dimen and self.ui.dimen.h or 800,
    }
    self.dash_widget = viewer
    UIManager:show(viewer)
end

function KindleDash:refreshDashboard(silent)
    local data, err = self:fetchDashboard()
    if not data then
        if not silent then
            UIManager:show(InfoMessage:new{ text = "刷新失败: " .. tostring(err), timeout = 3 })
        end
        logger.warn("KindleDash refresh failed:", err)
        return
    end
    self:showDashboard(data, silent)
end

-- ---------- 自动刷新 ----------
function KindleDash:armAutoRefresh()
    if not self.auto_on then return end
    local function tick()
        if not self.auto_on then return end
        self:refreshDashboard(true) -- 静默刷新；看板若开着则原地更新
        self._auto_timer = UIManager:scheduleIn(REFRESH_SEC, tick)
    end
    self._auto_timer = UIManager:scheduleIn(REFRESH_SEC, tick)
end
function KindleDash:toggleAutoRefresh()
    self.auto_on = not self.auto_on
    if self.auto_on then
        self:armAutoRefresh()
        UIManager:show(InfoMessage:new{ text = "自动刷新: 开 (30分钟)", timeout = 2 })
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
        text = "Kindle Dash",
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
                text = "切换自动刷新 (30分钟)",
                callback = function() self:toggleAutoRefresh() end
            },
            {
                text = "关于",
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = "Kindle Dash\n拉取 PC/Mac 的 /api/dashboard\n含限额/天气/股市/时钟/汇率\n自动刷新间隔 30 分钟",
                        timeout = 5
                    })
                end
            }
        }
    }
end

return KindleDash

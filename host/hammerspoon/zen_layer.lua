-- ZEN の現在レイヤーをメニューバーと画面右下 (HUD) に表示する
--
-- 使い方 (init.lua):
--   require("zen_layer").start()
--
-- zen-layer-hid (host/zen-layer-hid) がキーボードから Raw HID で受け取った
-- レイヤーを JSON 行で出力し、それを hs.task で読む。

local M = {}

-- install.sh が Hammerspoon の設定ディレクトリ (hs.configdir) に置く
M.helper = hs.configdir .. "/bin/zen-layer-hid"
M.product = "ZEN"

-- レイヤー番号 (キーマップ上の位置) -> 表示名。
-- 未定義ならファームウェアの display-name、それも無ければ "L<n>" を表示する。
M.labels = {
    [0] = "BASE",
    [1] = "MOUSE",
}

-- HUD を出さないレイヤー番号。0 (BASE) は常に出さない。
-- 例: トラックボールで頻繁に切り替わる自動マウスレイヤーを外す -> { [1] = true }
M.hudIgnore = {}

-- HUD の位置: "center" (画面中央) / "bottomRight" (右下)
M.hudPosition = "bottomRight"
-- HUD を出す画面: "primary" (メニューバーのあるメイン画面) / "focused" (操作中のウインドウがある画面)
M.hudScreen = "primary"

M.hudStyle = {
    width = 140,
    height = 44,
    margin = 24, -- bottomRight のときの画面端からの距離
    textSize = 22,
    fillColor = { white = 0.15, alpha = 0.85 },
    textColor = { white = 1.0, alpha = 0.95 },
}

local task, menu, hud, restartTimer
local stopped = true
local buffer = ""
local connected = 0

local function labelFor(index, name)
    if M.labels[index] then return M.labels[index] end
    if name and name ~= "" then return name end
    return "L" .. index
end

local function hideHud()
    if hud then hud:hide() end
end

local function showHud(text)
    local s = M.hudStyle
    local screen = M.hudScreen == "focused" and hs.screen.mainScreen() or hs.screen.primaryScreen()
    local frame = screen:frame()
    local rect = { w = s.width, h = s.height }
    if M.hudPosition == "bottomRight" then
        rect.x = frame.x + frame.w - s.width - s.margin
        rect.y = frame.y + frame.h - s.height - s.margin
    else
        rect.x = frame.x + (frame.w - s.width) / 2
        rect.y = frame.y + (frame.h - s.height) / 2
    end
    if not hud then
        hud = hs.canvas.new(rect)
        hud:level(hs.canvas.windowLevels.overlay)
        hud:behavior({ "canJoinAllSpaces", "stationary" })
        hud[1] = {
            type = "rectangle",
            action = "fill",
            fillColor = s.fillColor,
            roundedRectRadii = { xRadius = 10, yRadius = 10 },
        }
        hud[2] = {
            type = "text",
            text = "",
            textAlignment = "center",
            textSize = s.textSize,
            textColor = s.textColor,
            frame = { x = 0, y = (s.height - s.textSize * 1.25) / 2, w = "100%", h = s.textSize * 1.4 },
        }
    else
        hud:frame(rect)
    end
    hud[2].text = text
    hud:show()
end

local function setTitle(text)
    if menu then menu:setTitle(text) end
end

local function onMessage(msg)
    if msg.event == "connected" then
        connected = connected + 1
    elseif msg.event == "disconnected" then
        connected = math.max(connected - 1, 0)
        if connected == 0 then
            setTitle("ZEN -")
            hideHud()
        end
    elseif msg.event == "layer" then
        local label = labelFor(msg.index, msg.name)
        setTitle(label)
        if msg.index == 0 or M.hudIgnore[msg.index] then
            hideHud()
        else
            showHud(label)
        end
    end
end

local function onOutput(_, stdout, stderr)
    if stderr and stderr ~= "" then print("zen_layer: " .. stderr) end
    buffer = buffer .. (stdout or "")
    while true do
        local line, rest = buffer:match("^(.-)\n(.*)$")
        if not line then break end
        buffer = rest
        local ok, msg = pcall(hs.json.decode, line)
        if ok and type(msg) == "table" then onMessage(msg) end
    end
    return true
end

local function launch()
    buffer = ""
    connected = 0
    setTitle("ZEN -")
    hideHud()
    task = hs.task.new(M.helper, function(code, _, stderr)
        task = nil
        if stopped then return end
        print(string.format("zen_layer: helper exited (%d) %s", code, stderr or ""))
        setTitle("ZEN !")
        hideHud()
        restartTimer = hs.timer.doAfter(5, launch)
    end, onOutput, { M.product })
    if not task or not task:start() then
        task = nil
        print("zen_layer: failed to start " .. M.helper)
        setTitle("ZEN !")
    end
end

function M.start()
    if not stopped then return M end
    stopped = false
    menu = hs.menubar.new()
    launch()
    return M
end

function M.stop()
    stopped = true
    if restartTimer then restartTimer:stop(); restartTimer = nil end
    if task then task:terminate(); task = nil end
    if hud then hud:delete(); hud = nil end
    if menu then menu:delete(); menu = nil end
end

return M

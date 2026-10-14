--========================================================================
--  Roblox Executor Client
--========================================================================

local HTTP_HOST = "http://127.0.0.1:2026"

local http_request =
    (syn and syn.request) or
    (http and http.request) or
    (fluxus and fluxus.request) or
    (Krnl and Krnl.request) or
    http_request or
    request

assert(http_request, "Executor does not support HTTP requests.")

local Players     = game:GetService("Players")
local Workspace   = game:GetService("Workspace")
local RunService  = game:GetService("RunService")
local UIS         = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

local CFG = {
    ESP_RATE_HZ  = 20,
    ESP_MAX_DIST = 500,
}

local AIM = {
    assist_enabled  = false,
    assist_smooth   = 0.45,
    assist_jitter   = 0.05,
    assist_humanize = false,

    lock_enabled    = false,
    lock_humanize   = true,
    lock_jitter     = 0.15,
    lock_smooth     = 0.85,
    lock_reactMin   = 0.02,
    lock_reactMax   = 0.08,

    visible       = true,
    hold_rmb      = false,
    fov           = 25,
    maxDist       = 150,
    bone          = "Head",
    minTargetDist = 5.0,    -- ★ 3.0 → 5.0
}

--========================================================================
--  Utils
--========================================================================
local function worldToScreen(worldPos)
    local sp = Camera:WorldToViewportPoint(worldPos)
    if sp.Z <= 0 then return nil end
    return { x = math.floor(sp.X), y = math.floor(sp.Y) }
end

local function isVisible(part)
    if not AIM.visible then return true end
    local origin = Camera.CFrame.Position
    local dir = part.Position - origin
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character, Camera }
    local hit = Workspace:Raycast(origin, dir, params)
    return hit == nil or hit.Instance:IsDescendantOf(part.Parent)
end

--========================================================================
--  ESP
--========================================================================
local function collectESP()
    local list = {}
    local myPos  = Camera.CFrame.Position
    local myName = LocalPlayer.Name
    local myChar = LocalPlayer.Character
    local myUid  = LocalPlayer.UserId

    for _, plr in ipairs(Players:GetPlayers()) do
        local isSelf = (plr == LocalPlayer)
                    or (plr.Name == myName)
                    or (plr.Character == myChar)
                    or (plr.UserId == myUid)

        if not isSelf and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local dist = (hrp.Position - myPos).Magnitude
                if dist <= CFG.ESP_MAX_DIST then
                    local s = worldToScreen(hrp.Position)
                    if s then
                        table.insert(list, {
                            name = plr.Name,
                            x = s.x, y = s.y,
                            dist = math.floor(dist),
                        })
                    end
                end
            end
        end
    end
    return list
end

local espAccum = 0
RunService.Heartbeat:Connect(function(dt)
    local rate = math.max(CFG.ESP_RATE_HZ, 1)
    local interval = 1 / rate
    espAccum = espAccum + dt
    if espAccum < interval then return end
    espAccum = 0

    local players = collectESP()
    local ok, payload = pcall(function()
        return HttpService:JSONEncode({ get = "esp", players = players })
    end)
    if ok then
        pcall(function()
            http_request({
                Url = HTTP_HOST .. "/",
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = payload,
            })
        end)
    end
end)

--========================================================================
--  폴링
--========================================================================
task.spawn(function()
    while task.wait(0.5) do
        local ok, res = pcall(function()
            return http_request({
                Url = HTTP_HOST .. "/aim_poll",
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = "{}",
            })
        end)
        if ok and res and res.Body then
            local okj, data = pcall(function()
                return HttpService:JSONDecode(res.Body)
            end)
            if okj and data then
                if data.assist_enabled  ~= nil then AIM.assist_enabled  = data.assist_enabled  end
                if data.assist_smooth   ~= nil then AIM.assist_smooth   = data.assist_smooth   end
                if data.assist_jitter   ~= nil then AIM.assist_jitter   = data.assist_jitter   end
                if data.assist_humanize ~= nil then AIM.assist_humanize = data.assist_humanize end
                if data.lock_enabled  ~= nil then AIM.lock_enabled  = data.lock_enabled  end
                if data.lock_humanize ~= nil then AIM.lock_humanize = data.lock_humanize end
                if data.lock_jitter   ~= nil then AIM.lock_jitter   = data.lock_jitter   end
                if data.lock_smooth   ~= nil then AIM.lock_smooth   = data.lock_smooth   end
                if data.lock_reactMin ~= nil then AIM.lock_reactMin = data.lock_reactMin end
                if data.lock_reactMax ~= nil then AIM.lock_reactMax = data.lock_reactMax end
                if data.visible  ~= nil then AIM.visible  = data.visible  end
                if data.hold_rmb ~= nil then AIM.hold_rmb = data.hold_rmb end
                if data.fov      ~= nil then AIM.fov      = data.fov      end
                if data.max_dist ~= nil then AIM.maxDist  = data.max_dist end
            end
        end

        local ok2, res2 = pcall(function()
            return http_request({
                Url = HTTP_HOST .. "/esp_config",
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = "{}",
            })
        end)
        if ok2 and res2 and res2.Body then
            local okj2, d2 = pcall(function()
                return HttpService:JSONDecode(res2.Body)
            end)
            if okj2 and d2 then
                if d2.max_dist then
                    CFG.ESP_MAX_DIST = tonumber(d2.max_dist) or CFG.ESP_MAX_DIST
                end
                if d2.rate_hz then
                    CFG.ESP_RATE_HZ = tonumber(d2.rate_hz) or CFG.ESP_RATE_HZ
                end
            end
        end
    end
end)

--========================================================================
--  RMB
--========================================================================
local rmb_down = false
UIS.InputBegan:Connect(function(input, gp)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        rmb_down = true
    end
end)
UIS.InputEnded:Connect(function(input, gp)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        rmb_down = false
    end
end)

--========================================================================
--  Aim
--========================================================================
local function screenAngle(worldPos)
    local camPos = Camera.CFrame.Position
    local camDir = Camera.CFrame.LookVector
    local toT = worldPos - camPos
    if toT.Magnitude < 0.001 then return 0 end
    toT = toT.Unit
    return math.deg(math.acos(math.clamp(camDir:Dot(toT), -1, 1)))
end

local function isInFov(part)
    if AIM.fov >= 180 then return true end
    return screenAngle(part.Position) <= AIM.fov
end

local currentTarget = nil
local lastTarget    = nil
local nextReacquire = 0
local reactDelayUntil = 0

local function pickTarget()
    local best, bestScore = nil, math.huge
    local myPos  = Camera.CFrame.Position
    local myName = LocalPlayer.Name
    local myChar = LocalPlayer.Character
    local myUid  = LocalPlayer.UserId

    for _, plr in ipairs(Players:GetPlayers()) do
        local isSelf = (plr == LocalPlayer)
                    or (plr.Name == myName)
                    or (plr.Character == myChar)
                    or (plr.UserId == myUid)

        if not isSelf and plr.Character then
            local part = plr.Character:FindFirstChild(AIM.bone)
            local hum  = plr.Character:FindFirstChildOfClass("Humanoid")
            if part and hum and hum.Health > 0 then
                local dist = (part.Position - myPos).Magnitude
                -- ★ 5m 이상만 조준
                if dist >= AIM.minTargetDist and dist <= AIM.maxDist then
                    local isMyPart = myChar and part:IsDescendantOf(myChar)
                    if not isMyPart then
                        if isInFov(part) and isVisible(part) then
                            local score = dist
                            if AIM.fov < 180 then
                                score = screenAngle(part.Position) + dist * 0.02
                            end
                            if score < bestScore then
                                bestScore = score
                                best = part
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local aimState = {
    curYaw = 0, curPitch = 0,
    tgtYaw = 0, tgtPitch = 0,
    velYaw = 0, velPitch = 0,
    initialized = false,
}
local lastActive = false
local smoothTargetPos = nil
local lockSmoothPos   = nil

local function cframeToYawPitch(cf)
    local look = cf.LookVector
    local yaw   = math.atan2(-look.X, -look.Z)
    local pitch = math.asin(math.clamp(look.Y, -1, 1))
    return yaw, pitch
end

local function yawPitchToCFrame(pos, yaw, pitch)
    return CFrame.new(pos) * CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
end

local function normalizeAngle(a)
    while a >  math.pi do a = a - math.pi * 2 end
    while a < -math.pi do a = a + math.pi * 2 end
    return a
end

local function springStep(cur, tgt, vel, dt, k, d)
    local diff  = tgt - cur
    local accel = diff * k - vel * d
    vel = vel + accel * dt
    cur = cur + vel * dt
    return cur, vel
end

RunService:BindToRenderStep("AimCamera",
    Enum.RenderPriority.Camera.Value + 1,
    function(dt)
        local lockActive   = AIM.lock_enabled
        local assistActive = AIM.assist_enabled

        if AIM.hold_rmb and not rmb_down then
            lockActive   = false
            assistActive = false
        end

        local anyActive = lockActive or assistActive

        if anyActive ~= lastActive then
            lastActive = anyActive
            aimState.initialized = false
            smoothTargetPos = nil
            lockSmoothPos   = nil
            lastTarget      = nil
        end

        if not anyActive then
            aimState.initialized = false
            smoothTargetPos = nil
            lockSmoothPos   = nil
            lastTarget      = nil
            return
        end

        if not aimState.initialized then
            local y, p = cframeToYawPitch(Camera.CFrame)
            aimState.curYaw, aimState.curPitch = y, p
            aimState.tgtYaw, aimState.tgtPitch = y, p
            aimState.velYaw, aimState.velPitch = 0, 0
            aimState.initialized = true
        end

        local now = tick()
        local reacquireInterval = lockActive and 0.15 or 0.2

        if now >= nextReacquire or not currentTarget or not currentTarget.Parent then
            local hadTarget = currentTarget ~= nil
            currentTarget = pickTarget()
            nextReacquire = now + reacquireInterval
            if currentTarget and not hadTarget then
                if lockActive and AIM.lock_humanize then
                    local rmin = AIM.lock_reactMin or 0.02
                    local rmax = AIM.lock_reactMax or 0.08
                    reactDelayUntil = now + (rmin + math.random() * (rmax - rmin))
                end
            end
        end

        -- ★ 본인 캐릭터 파츠면 타겟/캐시 전부 리셋
        local myChar = LocalPlayer.Character
        if currentTarget and myChar and currentTarget:IsDescendantOf(myChar) then
            currentTarget   = nil
            lockSmoothPos   = nil
            smoothTargetPos = nil
            lastTarget      = nil
        end

        -- ★ 타겟 바뀌면 캐시 리셋 (부드러운 이동 방지)
        if currentTarget ~= lastTarget then
            lastTarget      = currentTarget
            lockSmoothPos   = nil
            smoothTargetPos = nil
        end

        if not currentTarget then
            aimState.velYaw   = aimState.velYaw   * 0.85
            aimState.velPitch = aimState.velPitch * 0.85
            aimState.curYaw   = aimState.curYaw   + aimState.velYaw   * dt
            aimState.curPitch = math.clamp(
                aimState.curPitch + aimState.velPitch * dt,
                -math.rad(85), math.rad(85))
            local camPos = Camera.CFrame.Position
            Camera.CFrame = yawPitchToCFrame(camPos,
                                             aimState.curYaw, aimState.curPitch)
            return
        end

        local camPos = Camera.CFrame.Position

        if lockActive then
            if AIM.lock_humanize and now < reactDelayUntil then
                return
            end
            local rawPos = currentTarget.Position
            if lockSmoothPos == nil then
                lockSmoothPos = rawPos
            else
                local alpha = AIM.lock_humanize and 0.35 or 1.0
                lockSmoothPos = lockSmoothPos:Lerp(rawPos, alpha)
            end
            local targetDir = lockSmoothPos - camPos
            if targetDir.Magnitude <= 0.001 then return end
            targetDir = targetDir.Unit
            local tgtYaw   = math.atan2(-targetDir.X, -targetDir.Z)
            local tgtPitch = math.asin(math.clamp(targetDir.Y, -1, 1))

            if AIM.lock_jitter > 0 then
                local jt = now * 3.5
                local jx = math.sin(jt * 6.283) * AIM.lock_jitter
                local jy = math.cos(jt * 5.113) * AIM.lock_jitter
                if AIM.lock_humanize then
                    jx = jx + (math.random() - 0.5) * AIM.lock_jitter * 0.6
                    jy = jy + (math.random() - 0.5) * AIM.lock_jitter * 0.6
                end
                tgtYaw   = tgtYaw   + math.rad(jx)
                tgtPitch = tgtPitch + math.rad(jy)
            end

            if not AIM.lock_humanize then
                aimState.curYaw   = tgtYaw
                aimState.curPitch = math.clamp(tgtPitch, -math.rad(85), math.rad(85))
                aimState.velYaw   = 0
                aimState.velPitch = 0
            else
                local s = math.clamp(AIM.lock_smooth or 0.85, 0.1, 1.0)
                local yawDiff   = normalizeAngle(tgtYaw - aimState.curYaw)
                local pitchDiff = tgtPitch - aimState.curPitch
                aimState.curYaw   = aimState.curYaw   + yawDiff   * s
                aimState.curPitch = aimState.curPitch + pitchDiff * s
                aimState.velYaw   = yawDiff   * s * 0.3
                aimState.velPitch = pitchDiff * s * 0.3
            end

            aimState.curPitch = math.clamp(aimState.curPitch,
                                           -math.rad(85), math.rad(85))
            Camera.CFrame = yawPitchToCFrame(camPos,
                                             aimState.curYaw, aimState.curPitch)
            return
        end

        if assistActive then
            local rawPos = currentTarget.Position
            if smoothTargetPos == nil then
                smoothTargetPos = rawPos
            else
                smoothTargetPos = smoothTargetPos:Lerp(rawPos, 0.25)
            end
            local targetDir = smoothTargetPos - camPos
            if targetDir.Magnitude <= 0.001 then return end
            targetDir = targetDir.Unit
            local tgtYaw   = math.atan2(-targetDir.X, -targetDir.Z)
            local tgtPitch = math.asin(math.clamp(targetDir.Y, -1, 1))

            if AIM.assist_jitter > 0 then
                local jt = now * 3.0
                tgtYaw   = tgtYaw   + math.rad(math.sin(jt * 6.283) * AIM.assist_jitter)
                tgtPitch = tgtPitch + math.rad(math.cos(jt * 5.113) * AIM.assist_jitter)
            end

            aimState.tgtYaw   = tgtYaw
            aimState.tgtPitch = tgtPitch

            local s = math.clamp(AIM.assist_smooth, 0.05, 1.0)
            local stiffness = 20 + s * 80
            local damping   = 12 + s * 20

            local yawDiff   = normalizeAngle(aimState.tgtYaw - aimState.curYaw)
            local yawTarget = aimState.curYaw + yawDiff

            aimState.curYaw, aimState.velYaw =
                springStep(aimState.curYaw, yawTarget,
                           aimState.velYaw, dt, stiffness, damping)
            aimState.curPitch, aimState.velPitch =
                springStep(aimState.curPitch, aimState.tgtPitch,
                           aimState.velPitch, dt, stiffness, damping)

            local maxVel = 5.0
            aimState.velYaw   = math.clamp(aimState.velYaw,   -maxVel, maxVel)
            aimState.velPitch = math.clamp(aimState.velPitch, -maxVel, maxVel)

            aimState.curPitch = math.clamp(aimState.curPitch,
                                           -math.rad(85), math.rad(85))
            Camera.CFrame = yawPitchToCFrame(camPos,
                                             aimState.curYaw, aimState.curPitch)
        end
    end
)

print("[CLIENT] Loaded")

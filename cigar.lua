--========================================================================
--  Roblox Executor Client — CIGARETTE V1
--  Python overlay.py 와 완전 호환
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

--========================================================================
--  Config
--========================================================================
local CFG = {
    ESP_RATE_HZ  = 30,
    ESP_MAX_DIST = 500,
    HITBOX_ON    = false,
    HITBOX_SCALE = 2.5,
}

-- AIM 테이블 키는 Python overlay 의 payload 키와 정확히 일치해야 함
local AIM = {
    -- Aim Assist
    assist_enabled  = false,
    assist_smooth   = 0.45,
    assist_jitter   = 0.05,
    assist_humanize = false,

    -- Aimlock
    lock_enabled    = false,
    lock_humanize   = true,
    lock_jitter     = 0.15,
    lock_smooth     = 0.85,
    lock_reactMin   = 0.02,
    lock_reactMax   = 0.08,

    -- Silent Aim
    silent_enabled  = false,
    silent_bone     = "Head",
    silent_fov      = 45,
    silent_mindist  = 5.0,
    silent_maxdist  = 300,

    -- Common
    visible        = true,
    hold_rmb       = false,
    fov            = 25,
    max_dist       = 150,     -- ★ maxDist → max_dist (Python 과 매칭)
    bone           = "Head",
    minTargetDist  = 1.5,
    humanize_level = 1.0,
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

local function isSelf(plr)
    if not plr then return true end
    if plr == LocalPlayer then return true end
    if plr.Name == LocalPlayer.Name then return true end
    if plr.UserId == LocalPlayer.UserId then return true end
    if plr.Character and plr.Character == LocalPlayer.Character then
        return true
    end
    return false
end

local function isMyPart(part)
    if not part then return true end
    local myChar = LocalPlayer.Character
    if not myChar then return false end
    if part:IsDescendantOf(myChar) then return true end
    local p = part
    while p do
        if p == myChar then return true end
        p = p.Parent
    end
    return false
end

-- ★ 캐릭터 파트 fallback (R6 / R15 호환)
local function findPart(char, name)
    if not char then return nil end
    local p = char:FindFirstChild(name)
    if p then return p end
    if name == "Torso" then
        return char:FindFirstChild("UpperTorso")
            or char:FindFirstChild("LowerTorso")
            or char:FindFirstChild("HumanoidRootPart")
    elseif name == "UpperTorso" then
        return char:FindFirstChild("Torso")
            or char:FindFirstChild("HumanoidRootPart")
    end
    return char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("Head")
end

--========================================================================
--  Humanize Engine
--========================================================================
local Human = {
    curYaw = 0, curPitch = 0,
    velYaw = 0, velPitch = 0,
    tgtYaw = 0, tgtPitch = 0,

    overshoot_active = false,
    overshoot_yaw = 0,
    overshoot_pitch = 0,
    overshoot_t = 0,
    overshoot_amount = 0,     -- ★ 초기화 (nil 산술 방지)
    last_target_pos = nil,

    react_delay = 0,
    next_react = 0,

    scan_t = 0,

    aim_offset = Vector3.new(0, 0, 0),
    offset_t = 0,
    breath_t = 0,

    seed = math.random() * 1000,
}

local function humanUpdateOffsets(dt)
    Human.offset_t = Human.offset_t + dt
    if Human.offset_t > 0.5 then
        Human.offset_t = 0
        local amp = 0.15 * AIM.humanize_level
        Human.aim_offset = Vector3.new(
            (math.random() - 0.5) * amp,
            (math.random() - 0.5) * amp,
            (math.random() - 0.5) * amp
        )
    end
    Human.breath_t = Human.breath_t + dt
end

local function humanJitter(dt, intensity)
    if intensity <= 0 then return 0, 0 end
    local t = tick()
    local a = math.noise(Human.seed + t * 0.8, 0, 0) * intensity
    local b = math.noise(0, Human.seed + t * 1.1, 0) * intensity
    local c = math.noise(Human.seed * 2 + t * 3.5, 0, 0) * intensity * 0.4
    local d = math.noise(0, Human.seed * 2 + t * 4.2, 0) * intensity * 0.4
    return a + c, b + d
end

local function humanTriggerOvershoot(target_pos)
    if AIM.humanize_level <= 0 then return end
    local amount = 0.04 + math.random() * 0.06
    Human.overshoot_active = true
    Human.overshoot_t = 0
    Human.overshoot_amount = amount
end

--========================================================================
--  Hitbox
--========================================================================
local hitboxOriginals = {}

local function restoreHitbox(part)
    local orig = hitboxOriginals[part]
    if orig then
        pcall(function()
            part.Size = orig.size
            part.Transparency = orig.trans
            part.CanCollide = orig.collide
            part.Massless = orig.massless
        end)
        hitboxOriginals[part] = nil
    end
end

local function applyHitbox(part, scale)
    if not part then return end
    if not hitboxOriginals[part] then
        hitboxOriginals[part] = {
            size = part.Size, trans = part.Transparency,
            collide = part.CanCollide, massless = part.Massless,
        }
    end
    local orig = hitboxOriginals[part]
    pcall(function()
        part.Size = Vector3.new(
            orig.size.X * scale, orig.size.Y * scale, orig.size.Z * scale)
        part.Transparency = 1
        part.CanCollide = false
        part.Massless = true
    end)
end

local function updateHitboxes()
    local scale = CFG.HITBOX_ON and CFG.HITBOX_SCALE or 1.0
    local active = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if not isSelf(plr) and plr.Character then
            local hrp  = plr.Character:FindFirstChild("HumanoidRootPart")
            local head = plr.Character:FindFirstChild("Head")
            if hrp then
                active[hrp] = true
                if scale > 1.0 then applyHitbox(hrp, scale) else restoreHitbox(hrp) end
            end
            if head then
                active[head] = true
                if scale > 1.0 then applyHitbox(head, scale) else restoreHitbox(head) end
            end
        end
    end
    for part in pairs(hitboxOriginals) do
        if not active[part] or not part.Parent then
            restoreHitbox(part)
        end
    end
end

task.spawn(function()
    while task.wait(0.2) do  -- ★ 0.5 → 0.2 (반응속도 개선)
        pcall(updateHitboxes)
    end
end)

--========================================================================
--  ESP
--========================================================================
local function collectESP()
    local list = {}
    local myPos = Camera.CFrame.Position
    for _, plr in ipairs(Players:GetPlayers()) do
        if not isSelf(plr) and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local dist = (hrp.Position - myPos).Magnitude
                if dist <= CFG.ESP_MAX_DIST then
                    local s = worldToScreen(hrp.Position)
                    if s then
                        table.insert(list, {
                            name = plr.Name, x = s.x, y = s.y,
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
    espAccum = espAccum + dt
    if espAccum < 1 / rate then return end
    espAccum = espAccum - 1 / rate   -- ★ 누적기 드리프트 수정

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
--  서버 폴링
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
                for k, v in pairs(data) do
                    if AIM[k] ~= nil then AIM[k] = v end
                end
                if data.hitbox_on    ~= nil then CFG.HITBOX_ON    = data.hitbox_on    end
                if data.hitbox_scale ~= nil then CFG.HITBOX_SCALE = data.hitbox_scale end
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
--  Input (RMB / LMB)
--========================================================================
local rmb_down = false

UIS.InputBegan:Connect(function(input, gp)
    if gp then return end   -- ★ 채팅창 입력 무시
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
--  Aim Math
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

local function cframeToYawPitch(cf)
    local look = cf.LookVector
    return math.atan2(-look.X, -look.Z),
           math.asin(math.clamp(look.Y, -1, 1))
end

local function yawPitchToCFrame(pos, yaw, pitch)
    return CFrame.new(pos) * CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
end

local function normalizeAngle(a)
    while a >  math.pi do a = a - math.pi * 2 end
    while a < -math.pi do a = a + math.pi * 2 end
    return a
end

--========================================================================
--  Aim Assist / Aimlock 타겟 선택
--========================================================================
local currentTarget = nil
local nextReacquire = 0

local function pickTarget()
    local best, bestScore = nil, math.huge
    local myPos = Camera.CFrame.Position
    for _, plr in ipairs(Players:GetPlayers()) do
        if not isSelf(plr) and plr.Character then
            local part = findPart(plr.Character, AIM.bone)
            local hum  = plr.Character:FindFirstChildOfClass("Humanoid")
            if part and hum and hum.Health > 0 then
                if not isMyPart(part) then
                    local dist = (part.Position - myPos).Magnitude
                    if dist >= AIM.minTargetDist and dist <= AIM.max_dist then
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

--========================================================================
--  ★ Silent Aim (카메라 스푸핑 방식)
--========================================================================
local silent_target      = nil
local silent_swap_frames = 0
local silent_saved_cf    = nil

local function pickSilentTarget()
    local best, bestScore = nil, math.huge
    local myPos = Camera.CFrame.Position
    for _, plr in ipairs(Players:GetPlayers()) do
        if not isSelf(plr) and plr.Character then
            local part = findPart(plr.Character, AIM.silent_bone)
            local hum  = plr.Character:FindFirstChildOfClass("Humanoid")
            if part and hum and hum.Health > 0 and not isMyPart(part) then
                local dist = (part.Position - myPos).Magnitude
                if dist >= AIM.silent_mindist and dist <= AIM.silent_maxdist then
                    if screenAngle(part.Position) <= AIM.silent_fov then
                        if isVisible(part) then
                            local score = screenAngle(part.Position) + dist * 0.01
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

-- LMB 누를 때 카메라 스푸핑
UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if not AIM.silent_enabled then return end
        local t = pickSilentTarget()
        if not t then return end
        local cur = Camera.CFrame
        silent_saved_cf = cur
        Camera.CFrame = CFrame.new(cur.Position, t.Position)
        silent_swap_frames = 2   -- 2 프레임 동안 스푸핑 유지
    end
end)

--========================================================================
--  Aim Camera Loop
--========================================================================
local lastActive = false

RunService:BindToRenderStep("AimCamera",
    Enum.RenderPriority.Camera.Value + 1,
    function(dt)
        -- ★ Silent Aim 스푸핑 중이면 카메라를 건드리지 않음
        if silent_swap_frames > 0 then
            silent_swap_frames = silent_swap_frames - 1
            if silent_swap_frames == 0 and silent_saved_cf then
                Camera.CFrame = silent_saved_cf
                silent_saved_cf = nil
            end
            return
        end

        local lockActive   = AIM.lock_enabled
        local assistActive = AIM.assist_enabled

        if AIM.hold_rmb and not rmb_down then
            lockActive   = false
            assistActive = false
        end

        local anyActive = lockActive or assistActive
        local humanize = AIM.humanize_level > 0 and (assistActive or lockActive)

        if anyActive ~= lastActive then
            lastActive = anyActive
            Human.curYaw, Human.curPitch = cframeToYawPitch(Camera.CFrame)
            Human.velYaw, Human.velPitch = 0, 0
            Human.tgtYaw, Human.tgtPitch = Human.curYaw, Human.curPitch
            currentTarget = nil
            Human.overshoot_active = false
            Human.last_target_pos = nil
        end

        if humanize then
            humanUpdateOffsets(dt)
        end

        if not anyActive then
            return
        end

        local now = tick()
        local reacquireInterval = lockActive and 0.15 or 0.2

        if now >= nextReacquire or not currentTarget or not currentTarget.Parent then
            local newTarget = pickTarget()
            if newTarget and newTarget ~= currentTarget then
                humanTriggerOvershoot(newTarget.Position + Human.aim_offset)
                if humanize then
                    local rMin = AIM.lock_reactMin or 0.02
                    local rMax = AIM.lock_reactMax or 0.08
                    Human.next_react = now + rMin
                        + math.random() * math.max(rMax - rMin, 0)
                else
                    Human.next_react = now
                end
            end
            currentTarget = newTarget
            nextReacquire = now + reacquireInterval
        end

        if currentTarget and isMyPart(currentTarget) then
            currentTarget = nil
        end

        -- 반응 지연 중
        if humanize and now < Human.next_react then
            local jx, jy = humanJitter(dt, 0.003 * AIM.humanize_level)
            local camPos = Camera.CFrame.Position
            Camera.CFrame = yawPitchToCFrame(camPos,
                Human.curYaw + jx, Human.curPitch + jy)
            return
        end

        -- 타겟 없음 → 스캔
        if not currentTarget then
            Human.scan_t = Human.scan_t + dt
            local scan_amp = 0.004 * AIM.humanize_level
            local scan_yaw   = math.noise(Human.seed,       Human.scan_t * 0.3,  0) * scan_amp
            local scan_pitch = math.noise(0, Human.seed,    Human.scan_t * 0.25) * scan_amp

            Human.velYaw   = Human.velYaw   * 0.9 + scan_yaw   * 0.1
            Human.velPitch = Human.velPitch * 0.9 + scan_pitch * 0.1

            Human.curYaw   = Human.curYaw   + Human.velYaw   * dt * 60
            Human.curPitch = math.clamp(
                Human.curPitch + Human.velPitch * dt * 60, -1.48, 1.48)

            local camPos = Camera.CFrame.Position
            Camera.CFrame = yawPitchToCFrame(camPos, Human.curYaw, Human.curPitch)
            return
        end

        -- 목표 계산
        local rawTargetPos = currentTarget.Position + Human.aim_offset

        local camPos = Camera.CFrame.Position
        local dir = (rawTargetPos - camPos)
        if dir.Magnitude < 0.001 then return end
        dir = dir.Unit

        local tgtYaw   = math.atan2(-dir.X, -dir.Z)
        local tgtPitch = math.asin(math.clamp(dir.Y, -1, 1))

        -- 오버슈트
        if Human.overshoot_active and humanize then
            Human.overshoot_t = Human.overshoot_t + dt
            local dur = 0.12
            if Human.overshoot_t < dur then
                local prog = Human.overshoot_t / dur
                local over = math.sin(prog * math.pi) * Human.overshoot_amount
                tgtYaw   = tgtYaw   + over * 0.5
                tgtPitch = tgtPitch + over * 0.5
            else
                Human.overshoot_active = false
            end
        end

        -- 지터
        if humanize then
            local jitter_amp = (assistActive and AIM.assist_jitter or AIM.lock_jitter)
                              * AIM.humanize_level
            local jx, jy = humanJitter(dt, jitter_amp * 0.01)
            tgtYaw   = tgtYaw   + jx
            tgtPitch = tgtPitch + jy
        end

        -- 호흡
        if humanize then
            local breath = math.sin(Human.breath_t * 0.25 * 6.283)
                           * 0.0008 * AIM.humanize_level
            tgtPitch = tgtPitch + breath
        end

        -- 속도 랜덤
        local speed_mult = 1.0
        if humanize then
            speed_mult = 0.75 + math.random() * 0.5
        end

        -- 스프링
        local base_smooth = lockActive and AIM.lock_smooth or AIM.assist_smooth
        local s = math.clamp(base_smooth, 0.05, 1.0)

        local stiffness, damping
        if lockActive then
            stiffness = 30 + s * 120
            damping   = 10 + s * 18
        else
            stiffness = 15 + s * 60
            damping   = 8 + s * 15
        end
        stiffness = stiffness * speed_mult

        local yawDiff   = normalizeAngle(tgtYaw - Human.curYaw)
        local pitchDiff = tgtPitch - Human.curPitch

        local accelY = yawDiff * stiffness - Human.velYaw * damping
        local accelP = pitchDiff * stiffness - Human.velPitch * damping

        Human.velYaw   = Human.velYaw   + accelY * dt
        Human.velPitch = Human.velPitch + accelP * dt

        local max_vel = humanize and 8.0 or 30.0
        Human.velYaw   = math.clamp(Human.velYaw,   -max_vel, max_vel)
        Human.velPitch = math.clamp(Human.velPitch, -max_vel, max_vel)

        Human.curYaw   = Human.curYaw   + Human.velYaw   * dt
        Human.curPitch = math.clamp(
            Human.curPitch + Human.velPitch * dt, -1.48, 1.48)

        Camera.CFrame = yawPitchToCFrame(camPos, Human.curYaw, Human.curPitch)
    end
)

print("[CLIENT] CIGARETTE V1 로드 완료 (Python overlay 완전 호환)")

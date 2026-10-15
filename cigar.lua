--========================================================================
--  Roblox Client - CIGARETTE V1.1
--  HTTP reverse-utilization + auto-requeue on teleport
--  ASCII ONLY
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

-- ★ 재실행 대비: 이전 인스턴스 정지
if getgenv()._cigar_stop then
    pcall(function() getgenv()._cigar_stop() end)
end
local _my_stop = false
getgenv()._cigar_stop = function() _my_stop = true end

--========================================================================
--  ★ 자동 재실행 (텔레포트 / 큐 잡힘 대비)
--========================================================================
local LOADER_URL = HTTP_HOST .. "/script"

local function selfRequeue()
    local loader_code = string.format(
        'loadstring(game:HttpGet("%s"))()', LOADER_URL)

    if queue_on_teleport then
        pcall(queue_on_teleport, loader_code)
        return true
    end
    if queueonteleport then
        pcall(queueonteleport, loader_code)
        return true
    end
    if syn and syn.queue_on_teleport then
        pcall(syn.queue_on_teleport, loader_code)
        return true
    end
    if fluxus and fluxus.queue_on_teleport then
        pcall(fluxus.queue_on_teleport, loader_code)
        return true
    end
    return false
end

if selfRequeue() then
    print("[CIGAR] auto-requeue on teleport: ON")
else
    warn("[CIGAR] queue_on_teleport unsupported -> manual re-execute required")
end

--========================================================================
--  Services
--========================================================================
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

    silent_enabled  = false,
    silent_bone     = "Head",
    silent_fov      = 45,
    silent_mindist  = 5.0,
    silent_maxdist  = 300,

    visible        = true,
    hold_rmb       = false,
    fov            = 25,
    max_dist       = 150,
    bone           = "Head",
    minTargetDist  = 1.5,
    humanize_level = 1.0,

    body_aim       = true,
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
    local me = Players.LocalPlayer
    if not me then return true end
    if plr == me then return true end
    if plr.Name == me.Name then return true end
    if plr.UserId == me.UserId then return true end
    if plr.Character and me.Character then
        if plr.Character == me.Character then return true end
        if plr.Character:IsDescendantOf(me.Character) then return true end
        if me.Character:IsDescendantOf(plr.Character) then return true end
    end
    return false
end

local function isMyPart(part)
    if not part then return true end
    local me = Players.LocalPlayer
    if not me then return false end
    local myChar = me.Character
    if not myChar then return false end
    if part:IsDescendantOf(myChar) then return true end
    local p = part
    while p do
        if p == myChar then return true end
        p = p.Parent
    end
    return false
end

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

local function cframeToYawPitch(cf)
    local look = cf.LookVector
    return math.atan2(-look.X, -look.Z),
           math.asin(math.clamp(look.Y, -1, 1))
end

local function normalizeAngle(a)
    while a >  math.pi do a = a - math.pi * 2 end
    while a < -math.pi do a = a + math.pi * 2 end
    return a
end

--========================================================================
--  Humanize
--========================================================================
local Human = {
    curYaw = 0, curPitch = 0,
    velYaw = 0, velPitch = 0,
    tgtYaw = 0, tgtPitch = 0,

    overshoot_active = false,
    overshoot_t = 0,
    overshoot_amount = 0,

    next_react = 0,

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
--  Body Aim (Waist + Neck Motor6D)
--========================================================================
local BodyAim = {
    joints      = nil,
    origWaistC0 = nil,
    origNeckC0  = nil,
    origWaistC1 = nil,
    origNeckC1  = nil,
    charRef     = nil,
}

local function resetBodyAim()
    if BodyAim.joints then
        if BodyAim.joints.waist then
            pcall(function()
                if BodyAim.origWaistC0 then
                    BodyAim.joints.waist.C0 = BodyAim.origWaistC0
                end
                if BodyAim.origWaistC1 then
                    BodyAim.joints.waist.C1 = BodyAim.origWaistC1
                end
            end)
        end
        if BodyAim.joints.neck then
            pcall(function()
                if BodyAim.origNeckC0 then
                    BodyAim.joints.neck.C0 = BodyAim.origNeckC0
                end
                if BodyAim.origNeckC1 then
                    BodyAim.joints.neck.C1 = BodyAim.origNeckC1
                end
            end)
        end
    end
    BodyAim.joints      = nil
    BodyAim.origWaistC0 = nil
    BodyAim.origNeckC0  = nil
    BodyAim.origWaistC1 = nil
    BodyAim.origNeckC1  = nil
    BodyAim.charRef     = nil
end

local function ensureBodyAim()
    local me = Players.LocalPlayer
    if not me then return end
    local char = me.Character
    if not char then
        if BodyAim.charRef then resetBodyAim() end
        return
    end
    if BodyAim.charRef == char and BodyAim.joints then return end

    resetBodyAim()

    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local waist = hrp:FindFirstChild("Waist") or hrp:FindFirstChild("RootJoint")
    local neck  = char:FindFirstChild("Neck", true)

    if not waist then return end
    if not neck then return end

    BodyAim.charRef     = char
    BodyAim.joints      = { waist = waist, neck = neck }
    BodyAim.origWaistC0 = waist.C0
    BodyAim.origNeckC0  = neck.C0
    BodyAim.origWaistC1 = waist.C1
    BodyAim.origNeckC1  = neck.C1
end

local function applyBodyAim(aimYaw, aimPitch)
    if not AIM.body_aim then
        if BodyAim.joints then resetBodyAim() end
        return
    end

    ensureBodyAim()
    if not BodyAim.joints or not BodyAim.charRef then return end

    local char = BodyAim.charRef
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        resetBodyAim()
        return
    end

    local hrpYaw = cframeToYawPitch(hrp.CFrame)
    local relYaw = normalizeAngle(aimYaw - hrpYaw)

    local maxWaistYaw   = math.rad(75)
    local maxNeckYaw    = math.rad(70)
    local maxNeckPitch  = math.rad(55)

    local cy = math.clamp(relYaw, -maxWaistYaw, maxWaistYaw)
    local np = math.clamp(aimPitch, -maxNeckPitch, maxNeckPitch)

    if BodyAim.joints.waist and BodyAim.origWaistC0 then
        BodyAim.joints.waist.C0 =
            BodyAim.origWaistC0 * CFrame.Angles(0, cy, 0)
    end
    if BodyAim.joints.neck and BodyAim.origNeckC0 then
        local neckRelY = normalizeAngle(aimYaw - (hrpYaw + cy))
        local ny2 = math.clamp(neckRelY, -maxNeckYaw, maxNeckYaw)
        BodyAim.joints.neck.C0 =
            BodyAim.origNeckC0 * CFrame.fromEulerAnglesYXZ(-np, ny2 * 0.5, 0)
    end
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
    while task.wait(0.2) do
        if _my_stop then return end
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
    if _my_stop then return end
    local rate = math.max(CFG.ESP_RATE_HZ, 1)
    espAccum = espAccum + dt
    if espAccum < 1 / rate then return end
    espAccum = espAccum - 1 / rate

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
--  서버 폴링 (aim 설정 + esp 설정)
--========================================================================
task.spawn(function()
    while task.wait(0.5) do
        if _my_stop then return end

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
--  재실행 명령 폴링 (overlay.py Execute 버튼)
--========================================================================
task.spawn(function()
    while task.wait(1) do
        if _my_stop then return end

        local ok, res = pcall(function()
            return http_request({
                Url = HTTP_HOST .. "/pending_script",
                Method = "GET",
            })
        end)
        if ok and res and res.Body and #res.Body > 5 then
            local src = res.Body
            _my_stop = true
            task.wait(0.1)
            local fn, err = loadstring(src)
            if fn then
                pcall(fn)
            else
                warn("[CIGAR reload] " .. tostring(err))
                if getgenv()._cigar_stop then
                    getgenv()._cigar_stop = nil
                end
            end
            return
        end
    end
end)

--========================================================================
--  Input
--========================================================================
local rmb_down = false

UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
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
--  Aim math
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

local function yawPitchToCFrame(pos, yaw, pitch)
    return CFrame.new(pos) * CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
end

--========================================================================
--  Target selection
--========================================================================
local currentTarget = nil
local nextReacquire = 0

local function pickTarget()
    local best, bestScore = nil, math.huge
    local myPos = Camera.CFrame.Position
    local me = Players.LocalPlayer
    local myChar = me and me.Character or nil

    for _, plr in ipairs(Players:GetPlayers()) do
        if not isSelf(plr) and plr.Character and plr.Character ~= myChar then
            local part = findPart(plr.Character, AIM.bone)
            local hum  = plr.Character:FindFirstChildOfClass("Humanoid")
            if part and hum and hum.Health > 0 then
                if not isMyPart(part) then
                    local dist = (part.Position - myPos).Magnitude
                    if dist >= math.max(AIM.minTargetDist, 2.5)
                       and dist <= AIM.max_dist then
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
--  Silent Aim
--========================================================================
local silent_swap_frames = 0
local silent_saved_cf    = nil

local function pickSilentTarget()
    local best, bestScore = nil, math.huge
    local myPos = Camera.CFrame.Position
    local me = Players.LocalPlayer
    local myChar = me and me.Character or nil

    for _, plr in ipairs(Players:GetPlayers()) do
        if not isSelf(plr) and plr.Character and plr.Character ~= myChar then
            local part = findPart(plr.Character, AIM.silent_bone)
            local hum  = plr.Character:FindFirstChildOfClass("Humanoid")
            if part and hum and hum.Health > 0 then
                if not isMyPart(part) then
                    local dist = (part.Position - myPos).Magnitude
                    if dist >= math.max(AIM.silent_mindist, 2.5)
                       and dist <= AIM.silent_maxdist then
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
    end
    return best
end

UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if not AIM.silent_enabled then return end
        local t = pickSilentTarget()
        if not t then return end
        local cur = Camera.CFrame
        silent_saved_cf = cur
        Camera.CFrame = CFrame.new(cur.Position, t.Position)
        silent_swap_frames = 2
    end
end)

--========================================================================
--  Aim Camera Loop
--========================================================================
local lastActive = false
local speed_noise_t = 0

RunService:BindToRenderStep("CigarAimCamera",
    Enum.RenderPriority.Camera.Value + 1,
    function(dt)
        if _my_stop then return end

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
            Human.next_react = 0
            if not anyActive then
                resetBodyAim()
            end
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

        if currentTarget and currentTarget.Parent then
            local me = Players.LocalPlayer
            local myChar = me and me.Character
            if myChar and currentTarget:IsDescendantOf(myChar) then
                currentTarget = nil
            end
            if currentTarget then
                local camPos = Camera.CFrame.Position
                if (currentTarget.Position - camPos).Magnitude < 2.0 then
                    currentTarget = nil
                end
            end
        end

        if humanize and now < Human.next_react then
            local jx, jy = humanJitter(dt, 0.003 * AIM.humanize_level)
            local camPos = Camera.CFrame.Position
            Camera.CFrame = yawPitchToCFrame(camPos,
                Human.curYaw + jx, Human.curPitch + jy)
            applyBodyAim(Human.curYaw, Human.curPitch)
            return
        end

        if not currentTarget then
            if humanize then
                local baseYaw, basePitch = cframeToYawPitch(Camera.CFrame)
                local t = tick()
                local scan_yaw   = math.noise(Human.seed,    t * 0.3,  0) * 0.006
                local scan_pitch = math.noise(0, Human.seed, t * 0.25) * 0.006
                local camPos = Camera.CFrame.Position
                Camera.CFrame = yawPitchToCFrame(camPos,
                    baseYaw + scan_yaw * AIM.humanize_level,
                    basePitch + scan_pitch * AIM.humanize_level)
                applyBodyAim(Human.curYaw, Human.curPitch)
            end
            return
        end

        local rawTargetPos = currentTarget.Position + Human.aim_offset
        local camPos = Camera.CFrame.Position
        local dir = (rawTargetPos - camPos)
        local dirMag = dir.Magnitude
        if dirMag < 2.0 then
            return
        end
        dir = dir / dirMag

        local tgtYaw   = math.atan2(-dir.X, -dir.Z)
        local tgtPitch = math.asin(math.clamp(dir.Y, -1, 1))

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

        if humanize then
            local jitter_amp = (assistActive and AIM.assist_jitter or AIM.lock_jitter)
                              * AIM.humanize_level
            local jx, jy = humanJitter(dt, jitter_amp * 0.01)
            tgtYaw   = tgtYaw   + jx
            tgtPitch = tgtPitch + jy
        end

        if humanize then
            local breath = math.sin(Human.breath_t * 0.25 * 6.283)
                           * 0.0008 * AIM.humanize_level
            tgtPitch = tgtPitch + breath
        end

        local speed_mult = 1.0
        if humanize then
            speed_noise_t = speed_noise_t + dt
            speed_mult = 0.85 + math.noise(Human.seed, speed_noise_t * 0.5, 0) * 0.3
        end

        local base_smooth = lockActive and AIM.lock_smooth or AIM.assist_smooth
        local s = math.clamp(base_smooth, 0.05, 1.0)

        local stiffness, damping
        if lockActive then
            stiffness = 8 + s * 22
            damping   = 2 * math.sqrt(stiffness) * 1.15
        else
            stiffness = 5 + s * 15
            damping   = 2 * math.sqrt(stiffness) * 1.15
        end
        stiffness = stiffness * speed_mult

        local max_vel
        if humanize then
            max_vel = 3.5
        else
            max_vel = 15.0
        end

        local yawDiff   = normalizeAngle(tgtYaw - Human.curYaw)
        local pitchDiff = tgtPitch - Human.curPitch

        local accelY = yawDiff * stiffness - Human.velYaw * damping
        local accelP = pitchDiff * stiffness - Human.velPitch * damping

        Human.velYaw   = Human.velYaw   + accelY * dt
        Human.velPitch = Human.velPitch + accelP * dt

        Human.velYaw   = math.clamp(Human.velYaw,   -max_vel, max_vel)
        Human.velPitch = math.clamp(Human.velPitch, -max_vel, max_vel)

        Human.curYaw   = Human.curYaw   + Human.velYaw   * dt
        Human.curPitch = math.clamp(
            Human.curPitch + Human.velPitch * dt, -1.48, 1.48)

        Camera.CFrame = yawPitchToCFrame(camPos, Human.curYaw, Human.curPitch)

        applyBodyAim(Human.curYaw, Human.curPitch)
    end
)

print("[CLIENT] CIGARETTE V1.1 loaded (auto-requeue + http reverse)")

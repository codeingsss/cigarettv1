--========================================================================
--  Roblox Client - CIGARETTE V5.0
--  Silent = soft camera assist (delta-based, mouse-preserving)
--  Single __namecall hook. Sticky = rotation-only.
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

--========================================================================
--  Hook teardown (must run BEFORE overwriting _cigar_stop)
--========================================================================
local _my_stop = false
local _hookState = {
    savedNamecall = nil,
    ourNamecall   = nil,
    savedIndex    = nil,
    ourIndex      = nil,
}

local function uninstallHooks()
    if not (getrawmetatable and setreadonly) then return end
    local ok, mt = pcall(getrawmetatable, game)
    if not ok or not mt then return end
    pcall(function()
        setreadonly(mt, false)
        if _hookState.ourNamecall and mt.__namecall == _hookState.ourNamecall then
            mt.__namecall = _hookState.savedNamecall
        end
        if _hookState.ourIndex and mt.__index == _hookState.ourIndex then
            mt.__index = _hookState.savedIndex
        end
        setreadonly(mt, true)
    end)
    _hookState.ourNamecall = nil
    _hookState.ourIndex = nil
end

if getgenv()._cigar_stop then
    pcall(getgenv()._cigar_stop)
end

getgenv()._cigar_stop = function()
    _my_stop = true
    uninstallHooks()
end

--========================================================================
--  Requeue
--========================================================================
local LOADER_URL = HTTP_HOST .. "/script"

local function selfRequeue()
    local code = string.format('loadstring(game:HttpGet("%s"))()', LOADER_URL)
    if queue_on_teleport then pcall(queue_on_teleport, code); return true end
    if queueonteleport then pcall(queueonteleport, code); return true end
    if syn and syn.queue_on_teleport then pcall(syn.queue_on_teleport, code); return true end
    if fluxus and fluxus.queue_on_teleport then pcall(fluxus.queue_on_teleport, code); return true end
    return false
end

if selfRequeue() then print("[CIGAR] auto-requeue ON") end

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
    HITBOX_SCALE = 3.0,
    HEAD_EXPAND_ON    = false,
    HEAD_EXPAND_SCALE = 4.0,
}

local AIM = {
    -- Aim Assist (soft pull, mouse still works)
    assist_enabled  = false,
    assist_smooth   = 0.45,       -- 0..1, higher = slower
    assist_jitter   = 0.05,
    assist_humanize = true,
    assist_fov      = 25,
    assist_maxdist  = 150,
    assist_speed_min = 0.8,
    assist_speed_max = 1.5,

    -- Aimlock (hard pull)
    lock_enabled    = false,
    lock_humanize   = true,
    lock_jitter     = 0.15,
    lock_smooth     = 0.85,
    lock_fov        = 25,
    lock_maxdist    = 150,
    lock_speed_min  = 0.8,
    lock_speed_max  = 1.5,
    lock_react_min  = 0.02,
    lock_react_max  = 0.08,

    -- Silent (soft camera assist on top of default camera)
    silent_enabled  = false,
    silent_bone     = "Head",
    silent_strength = 0.12,       -- 0.08~0.20 recommended
    silent_smooth   = 0.6,        -- higher = slower
    silent_humanize = true,
    silent_fov      = 40,         -- 90 is too wide, causes jerk
    silent_mindist  = 5.0,
    silent_maxdist  = 500,

    -- Common
    visible        = true,
    hold_rmb       = false,
    fov            = 25,
    max_dist       = 150,
    minTargetDist  = 1.5,
    humanize_level = 1.0,

    body_aim       = true,
    sticky_enabled = true,

    autohead_enabled = false,
    autohead_fov     = 90,
    autohead_maxdist = 500,
}

--========================================================================
--  Utils
--========================================================================
local function worldToScreen(worldPos)
    local sp = Camera:WorldToViewportPoint(worldPos)
    if sp.Z <= 0 then return nil end
    return { x = math.floor(sp.X), y = math.floor(sp.Y) }
end

local _rayParams = RaycastParams.new()
_rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function isVisible(part)
    if not AIM.visible then return true end
    local origin = Camera.CFrame.Position
    local dir = part.Position - origin
    local myChar = LocalPlayer and LocalPlayer.Character
    _rayParams.FilterDescendantsInstances =
        myChar and { myChar, Camera } or { Camera }
    local hit = Workspace:Raycast(origin, dir, _rayParams)
    return hit == nil or hit.Instance:IsDescendantOf(part.Parent)
end

local function isSelf(plr)
    if not plr then return true end
    local me = Players.LocalPlayer
    if not me then return true end
    if plr == me then return true end
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
    local myChar = me and me.Character
    if not myChar then return false end
    return part:IsDescendantOf(myChar)
end

local function findPart(char, name)
    if not char then return nil end
    local p = char:FindFirstChild(name)
    if p then return p end
    if name == "Torso" then
        p = char:FindFirstChild("UpperTorso") or char:FindFirstChild("LowerTorso")
    elseif name == "UpperTorso" then
        p = char:FindFirstChild("Torso")
    end
    return p
        or char:FindFirstChild("HumanoidRootPart")
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

local function screenAngle(worldPos)
    local camPos = Camera.CFrame.Position
    local camDir = Camera.CFrame.LookVector
    local toT = worldPos - camPos
    if toT.Magnitude < 0.001 then return 0 end
    toT = toT.Unit
    return math.deg(math.acos(math.clamp(camDir:Dot(toT), -1, 1)))
end

local function easeOutCubic(t)
    t = math.clamp(t, 0, 1)
    local inv = 1 - t
    return 1 - inv * inv * inv
end

local function targetAlive(part)
    if not part or not part.Parent then return false end
    local hum = part.Parent:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

-- Per-player bone cache (prevents head<->torso flipping)
local _boneCache = {}
local _boneCacheTime = {}
local function pickBoneFor(plr)
    if not AIM.body_aim then return "Head" end
    local now = tick()
    local cached = _boneCache[plr]
    if cached and (now - (_boneCacheTime[plr] or 0)) < 5 then
        return cached
    end
    local ch = plr.Character
    if not ch then return "Head" end
    local b
    if math.random() < 0.5 then
        if ch:FindFirstChild("UpperTorso") then b = "UpperTorso"
        elseif ch:FindFirstChild("Torso") then b = "Torso"
        else b = "HumanoidRootPart" end
    else
        b = "Head"
    end
    _boneCache[plr] = b
    _boneCacheTime[plr] = now
    return b
end

--========================================================================
--  Body Aim
--========================================================================
local BodyAim = {
    joints = nil, charRef = nil,
    origWaistC0 = nil, origNeckC0 = nil,
    curYaw = 0, curPitch = 0,
}

local function resetBodyAim()
    if BodyAim.joints then
        pcall(function()
            if BodyAim.joints.waist and BodyAim.origWaistC0 then
                BodyAim.joints.waist.C0 = BodyAim.origWaistC0
            end
            if BodyAim.joints.neck and BodyAim.origNeckC0 then
                BodyAim.joints.neck.C0 = BodyAim.origNeckC0
            end
        end)
    end
    BodyAim.joints = nil
    BodyAim.origWaistC0 = nil
    BodyAim.origNeckC0 = nil
    BodyAim.charRef = nil
end

local function ensureBodyAim()
    local me = Players.LocalPlayer
    local char = me and me.Character
    if not char then
        if BodyAim.charRef then resetBodyAim() end
        return
    end
    if BodyAim.charRef == char and BodyAim.joints then return end
    resetBodyAim()

    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local waist = nil
    local lowerTorso = char:FindFirstChild("LowerTorso")
    if lowerTorso then waist = lowerTorso:FindFirstChild("Waist") end
    if not waist then
        waist = hrp:FindFirstChild("RootJoint") or hrp:FindFirstChild("Waist")
    end
    if not waist then
        waist = char:FindFirstChild("Waist", true) or char:FindFirstChild("RootJoint", true)
    end

    local neck = nil
    local head = char:FindFirstChild("Head")
    if head then neck = head:FindFirstChild("Neck") end
    if not neck then
        local torso = char:FindFirstChild("Torso")
        if torso then neck = torso:FindFirstChild("Neck") end
    end
    if not neck then neck = char:FindFirstChild("Neck", true) end

    if not waist or not neck then return end

    BodyAim.charRef = char
    BodyAim.joints = { waist = waist, neck = neck }
    BodyAim.origWaistC0 = waist.C0
    BodyAim.origNeckC0  = neck.C0

    local y, p = cframeToYawPitch(hrp.CFrame)
    BodyAim.curYaw, BodyAim.curPitch = y, p
end

local function applyBodyAimYawPitch(yaw, pitch)
    ensureBodyAim()
    if not BodyAim.joints or not BodyAim.charRef then return end
    local char = BodyAim.charRef
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then resetBodyAim(); return end

    local hrpYaw = cframeToYawPitch(hrp.CFrame)
    local relYaw = normalizeAngle(yaw - hrpYaw)
    local cy = math.clamp(relYaw, -math.rad(75), math.rad(75))
    local np = math.clamp(pitch, -math.rad(55), math.rad(55))

    if BodyAim.joints.waist and BodyAim.origWaistC0 then
        pcall(function()
            BodyAim.joints.waist.C0 = BodyAim.origWaistC0 * CFrame.Angles(0, cy, 0)
        end)
    end
    if BodyAim.joints.neck and BodyAim.origNeckC0 then
        pcall(function()
            local neckRelY = normalizeAngle(yaw - (hrpYaw + cy))
            local ny2 = math.clamp(neckRelY, -math.rad(70), math.rad(70))
            BodyAim.joints.neck.C0 =
                BodyAim.origNeckC0 * CFrame.fromEulerAnglesYXZ(-np, ny2 * 0.5, 0)
        end)
    end
end

local function updateBodyAim(dt, tgtYaw, tgtPitch)
    if not AIM.body_aim then
        if BodyAim.joints then resetBodyAim() end
        return
    end
    ensureBodyAim()
    if not BodyAim.joints then return end
    local smooth = 1 - math.exp(-14 * dt)
    BodyAim.curYaw   = BodyAim.curYaw
                     + normalizeAngle(tgtYaw - BodyAim.curYaw) * smooth
    BodyAim.curPitch = BodyAim.curPitch
                     + (tgtPitch - BodyAim.curPitch) * smooth
    applyBodyAimYawPitch(BodyAim.curYaw, BodyAim.curPitch)
end

--========================================================================
--  Target picker (shared)
--========================================================================
local function pickTarget(fov, maxDist, minDist, useBone)
    local best, bestScore = nil, math.huge
    local camPos = Camera.CFrame.Position
    local me = Players.LocalPlayer
    local myChar = me and me.Character
    for _, plr in ipairs(Players:GetPlayers()) do
        if not isSelf(plr) and plr.Character and plr.Character ~= myChar then
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local bone = useBone or pickBoneFor(plr)
                local part = findPart(plr.Character, bone)
                if part and not isMyPart(part) then
                    local dist = (part.Position - camPos).Magnitude
                    if dist >= (minDist or 2.5) and dist <= maxDist then
                        if isVisible(part) then
                            local ang = screenAngle(part.Position)
                            if ang <= fov then
                                local score = ang * 1.5 + dist * 0.02
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

local function blendDirection(origDir, targetPos, originPos, strength)
    local toT = (targetPos - originPos)
    if toT.Magnitude < 0.001 then return origDir end
    local s = math.clamp(strength or 0.5, 0.0, 1.0)
    local origUnit = origDir.Magnitude > 0.0001 and origDir.Unit or toT.Unit
    local blended = origUnit:Lerp(toT.Unit, s)
    if blended.Magnitude < 0.001 then return origDir end
    return blended.Unit
end

--========================================================================
--  Hooks (single __namecall + __index)
--========================================================================
local _origIndexRef = nil
local _origNamecallRef = nil

-- Weapon remote name hints (add your game's remote names if needed)
local WEAPON_HINTS = {
    "gun","weapon","shoot","fire","bullet","hit","aim",
    "mouse","click","attack","projectile","ray","cast","damage",
}
local function isWeaponRemote(remote)
    local n = remote.Name:lower()
    for _, h in ipairs(WEAPON_HINTS) do
        if n:find(h, 1, true) then return true end
    end
    local p = remote.Parent
    if p then
        local pn = p.Name:lower()
        for _, h in ipairs(WEAPON_HINTS) do
            if pn:find(h, 1, true) then return true end
        end
    end
    return false
end

local function installHooks()
    if not (getrawmetatable and setreadonly and newcclosure) then return end
    local ok, mt = pcall(getrawmetatable, game)
    if not ok or not mt then return end

    -- __index hook (hitbox/head expand)
    if mt.__index and not _hookState.ourIndex then
        _origIndexRef = mt.__index
        local hookIndex
        hookIndex = newcclosure(function(self, key)
            if _my_stop then return _origIndexRef(self, key) end
            if checkcaller and checkcaller() then
                return _origIndexRef(self, key)
            end
            if key == "Size" and typeof(self) == "Instance" then
                local okA = pcall(function()
                    return self:IsA("BasePart") or self:IsA("MeshPart")
                end)
                if okA then
                    local char = self.Parent
                    if char then
                        local plr
                        pcall(function() plr = Players:GetPlayerFromCharacter(char) end)
                        if plr and plr ~= LocalPlayer then
                            local n = self.Name
                            if CFG.HEAD_EXPAND_ON and n == "Head" then
                                local orig = _origIndexRef(self, key)
                                if typeof(orig) == "Vector3" then
                                    local s = CFG.HEAD_EXPAND_SCALE or 4.0
                                    local sy = orig.Y * math.max(1.0, s * 0.4)
                                    return Vector3.new(orig.X * s, sy, orig.Z * s)
                                end
                            end
                            if CFG.HITBOX_ON and n == "HumanoidRootPart" then
                                local orig = _origIndexRef(self, key)
                                if typeof(orig) == "Vector3" then
                                    local s = CFG.HITBOX_SCALE or 3.0
                                    return Vector3.new(orig.X * s, orig.Y * s, orig.Z * s)
                                end
                            end
                        end
                    end
                end
            end
            return _origIndexRef(self, key)
        end)
        pcall(function()
            setreadonly(mt, false)
            mt.__index = hookIndex
            setreadonly(mt, true)
        end)
        _hookState.savedIndex = _origIndexRef
        _hookState.ourIndex = hookIndex
    end

    -- __namecall hook (silent + autohead)
    if mt.__namecall and not _hookState.ourNamecall then
        _origNamecallRef = mt.__namecall
        local hookNamecall
        hookNamecall = newcclosure(function(self, ...)
            if _my_stop then return _origNamecallRef(self, ...) end
            local method = getnamecallmethod and getnamecallmethod() or nil

            -- SILENT (weapon remote)
            if AIM.silent_enabled and method and
               (method == "FireServer" or method == "InvokeServer") and
               typeof(self) == "Instance" and
               (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) and
               isWeaponRemote(self) then
                local args = {...}
                local mutated = false
                for i = 1, math.min(5, #args) do
                    local a = args[i]
                    if typeof(a) == "Vector3" then
                        if a.Magnitude > 0.001 then
                            local t = pickTarget(
                                AIM.silent_fov, AIM.silent_maxdist,
                                AIM.silent_mindist, AIM.silent_bone)
                            if t then
                                local o = Camera.CFrame.Position
                                local blended = blendDirection(a.Unit, t.Position, o,
                                    AIM.silent_strength or 0.12)
                                args[i] = blended * a.Magnitude
                                mutated = true
                            end
                        end
                        break
                    elseif typeof(a) == "CFrame" then
                        local t = pickTarget(
                            AIM.silent_fov, AIM.silent_maxdist,
                            AIM.silent_mindist, AIM.silent_bone)
                        if t then
                            local blended = blendDirection(a.LookVector, t.Position,
                                a.Position, AIM.silent_strength or 0.12)
                            args[i] = CFrame.lookAt(a.Position, a.Position + blended)
                            mutated = true
                        end
                        break
                    end
                end
                if mutated then
                    return _origNamecallRef(self, table.unpack(args))
                end
                return _origNamecallRef(self, ...)
            end

            -- AUTOHEAD (raycast redirect)
            if AIM.autohead_enabled and self == Workspace and method then
                local isRay = (method == "Raycast" or
                    method == "FindPartOnRay" or
                    method == "FindPartOnRayWithIgnoreList" or
                    method == "FindPartOnRayWithWhitelist")
                if isRay then
                    local args = {...}
                    local originV, dirV
                    if method == "Raycast" then
                        if typeof(args[1]) == "Vector3" and typeof(args[2]) == "Vector3" then
                            originV, dirV = args[1], args[2]
                        end
                    else
                        if typeof(args[1]) == "Ray" then
                            originV, dirV = args[1].Origin, args[1].Direction
                        end
                    end
                    if originV and dirV then
                        local results = {_origNamecallRef(self, ...)}
                        local r = results[1]
                        local hitInstance
                        if typeof(r) == "RaycastResult" then
                            hitInstance = r.Instance
                        elseif typeof(r) == "Instance" then
                            hitInstance = r
                        end
                        if hitInstance and typeof(hitInstance) == "Instance" then
                            local char = hitInstance:FindFirstAncestorOfClass("Model")
                            local plr = char and Players:GetPlayerFromCharacter(char)
                            if plr and not isSelf(plr) then
                                local bone = pickBoneFor(plr)
                                local targetPart = char:FindFirstChild(bone)
                                if targetPart and hitInstance ~= targetPart
                                   and targetPart:IsDescendantOf(char)
                                   and hitInstance:IsDescendantOf(char) then
                                    local newDir = targetPart.Position - originV
                                    if newDir.Magnitude > 0.001 then
                                        newDir = newDir.Unit * dirV.Magnitude
                                        local newArgs
                                        if method == "Raycast" then
                                            newArgs = {originV, newDir}
                                            for i = 3, #args do newArgs[i] = args[i] end
                                        else
                                            newArgs = {Ray.new(originV, newDir)}
                                            for i = 2, #args do newArgs[i] = args[i] end
                                        end
                                        return _origNamecallRef(self, table.unpack(newArgs))
                                    end
                                end
                            end
                        end
                        return table.unpack(results)
                    end
                end
            end

            return _origNamecallRef(self, ...)
        end)
        pcall(function()
            setreadonly(mt, false)
            mt.__namecall = hookNamecall
            setreadonly(mt, true)
        end)
        _hookState.savedNamecall = _origNamecallRef
        _hookState.ourNamecall = hookNamecall
    end
    print("[HOOKS] installed")
end

installHooks()

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
                Url = HTTP_HOST .. "/", Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = payload,
            })
        end)
    end
end)

--========================================================================
--  Server polling
--========================================================================
local NUM_KEYS = {
    assist_smooth=true, assist_jitter=true, assist_fov=true, assist_maxdist=true,
    assist_speed_min=true, assist_speed_max=true,
    lock_jitter=true, lock_smooth=true, lock_fov=true, lock_maxdist=true,
    lock_speed_min=true, lock_speed_max=true,
    lock_react_min=true, lock_react_max=true,
    silent_strength=true, silent_smooth=true, silent_fov=true,
    silent_mindist=true, silent_maxdist=true,
    fov=true, max_dist=true, minTargetDist=true, humanize_level=true,
    autohead_fov=true, autohead_maxdist=true,
}
local BOOL_KEYS = {
    assist_enabled=true, assist_humanize=true,
    lock_enabled=true, lock_humanize=true,
    silent_enabled=true, silent_humanize=true,
    visible=true, hold_rmb=true, body_aim=true, sticky_enabled=true,
    autohead_enabled=true,
}

task.spawn(function()
    while task.wait(0.5) do
        if _my_stop then return end
        local ok, res = pcall(function()
            return http_request({
                Url = HTTP_HOST .. "/aim_poll", Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = "{}",
            })
        end)
        if ok and res and res.Body then
            local okj, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
            if okj and data then
                for k, v in pairs(data) do
                    if AIM[k] ~= nil then
                        if NUM_KEYS[k] then
                            local n = tonumber(v); if n then AIM[k] = n end
                        elseif BOOL_KEYS[k] then
                            AIM[k] = not not v
                        end
                    end
                end
                if data.hitbox_on    ~= nil then CFG.HITBOX_ON    = data.hitbox_on    end
                if data.hitbox_scale ~= nil then CFG.HITBOX_SCALE = tonumber(data.hitbox_scale) or CFG.HITBOX_SCALE end
                if data.head_expand_enabled ~= nil then CFG.HEAD_EXPAND_ON = data.head_expand_enabled end
                if data.head_expand_scale ~= nil then CFG.HEAD_EXPAND_SCALE = tonumber(data.head_expand_scale) or CFG.HEAD_EXPAND_SCALE end
            end
        end
        local ok2, res2 = pcall(function()
            return http_request({
                Url = HTTP_HOST .. "/esp_config", Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = "{}",
            })
        end)
        if ok2 and res2 and res2.Body then
            local okj2, d2 = pcall(function() return HttpService:JSONDecode(res2.Body) end)
            if okj2 and d2 then
                if d2.max_dist then CFG.ESP_MAX_DIST = tonumber(d2.max_dist) or CFG.ESP_MAX_DIST end
                if d2.rate_hz  then CFG.ESP_RATE_HZ  = tonumber(d2.rate_hz)  or CFG.ESP_RATE_HZ  end
            end
        end
    end
end)

task.spawn(function()
    while task.wait(1) do
        if _my_stop then return end
        local ok, res = pcall(function()
            return http_request({ Url = HTTP_HOST .. "/pending_script", Method = "GET" })
        end)
        if ok and res and res.Body and #res.Body > 5 then
            local src = res.Body
            _my_stop = true
            uninstallHooks()
            task.wait(0.1)
            local fn, err = loadstring(src)
            if fn then
                local ok2, err2 = pcall(fn)
                if ok2 then return end
                warn("[CIGAR reload runtime] " .. tostring(err2))
            else
                warn("[CIGAR reload] " .. tostring(err))
            end
            -- reload failed: restore
            _my_stop = false
            installHooks()
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

local stickyRot = nil
UIS.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        if stickyRot then
            local d = math.abs(input.Delta.X or 0) + math.abs(input.Delta.Y or 0)
            if d > 8 then stickyRot = nil end
        end
    end
end)

--========================================================================
--  Humanize
--========================================================================
local Human = {
    overshoot_active = false, overshoot_t = 0, overshoot_amount = 0,
    next_react = 0, last_switch = 0,
    aim_offset = Vector3.new(0,0,0),
    aim_offset_target = Vector3.new(0,0,0),
    offset_t = 0, breath_t = 0,
    speedMult = 1.0,
    speedNoiseT = 0,
    speedSeed  = math.random() * 1000,
    jitterSeed = math.random() * 1000,
    seed = math.random() * 1000,
}

local function rollReactDelay(rMin, rMax)
    if rMax <= rMin then return rMin end
    local u = math.random()
    return rMin + (rMax - rMin) * (u * u)
end

local function humanUpdateOffsets(dt)
    Human.offset_t = Human.offset_t + dt
    if Human.offset_t > 0.4 then
        Human.offset_t = 0
        local amp = 0.08 * AIM.humanize_level
        Human.aim_offset_target = Vector3.new(
            (math.random() - 0.5) * amp,
            (math.random() - 0.5) * amp,
            (math.random() - 0.5) * amp)
    end
    Human.aim_offset = Human.aim_offset:Lerp(Human.aim_offset_target,
        math.min(1, 4 * dt))
    Human.breath_t = Human.breath_t + dt
end

local function humanJitter(angleDeg, baseIntensity)
    if baseIntensity <= 0 then return 0, 0 end
    local t = tick()
    local angleScale = math.clamp(angleDeg / 30, 0.3, 2.0)
    local amp = baseIntensity * angleScale
    local a = math.noise(Human.jitterSeed, t * 0.6, 0) * amp
    local b = math.noise(0, Human.jitterSeed, t * 0.9) * amp
    local c = math.noise(Human.jitterSeed * 2, t * 2.4, 0) * amp * 0.35
    local d = math.noise(Human.jitterSeed * 3, 0, t * 3.1) * amp * 0.35
    local spike = (math.random() - 0.5) * amp * 0.15
    return a + c + spike, b + d + spike
end

local function humanTriggerOvershoot(angleDeg)
    if AIM.humanize_level <= 0 then return end
    local base = 0.015 + math.random() * 0.025
    local scale = math.clamp(angleDeg / 20, 0.5, 1.8)
    Human.overshoot_active = true
    Human.overshoot_t = 0
    Human.overshoot_amount = base * scale
end

local function updateSpeedMult(dt, sMin, sMax)
    Human.speedNoiseT = Human.speedNoiseT + dt
    local t = tick()
    local n1 = math.noise(Human.speedSeed, t * 0.25, 0)
    local n2 = math.noise(Human.speedSeed * 2, t * 0.13, 0)
    local combined = (n1 + n2) * 0.5
    local lo = math.min(sMin, sMax)
    local hi = math.max(sMin, sMax)
    local raw = (lo + hi) * 0.5 + combined * (hi - lo) * 0.5
    Human.speedMult = Human.speedMult + (raw - Human.speedMult)
        * math.min(1, 3 * dt)
end

--========================================================================
--  Main render loop
--========================================================================
local currentTarget = nil
local nextReacquire = 0
local lastAimOn = false
local silentTarget = nil
local silentNextReacquire = 0

RunService:BindToRenderStep("CigarAimCamera",
    Enum.RenderPriority.Camera.Value + 1,
    function(dt)
        if _my_stop then return end

        local lockActive   = AIM.lock_enabled
        local assistActive = AIM.assist_enabled
        local silentActive = AIM.silent_enabled

        if AIM.hold_rmb and not rmb_down then
            lockActive, assistActive, silentActive = false, false, false
        end

        local anyAimActive = lockActive or assistActive
        local anyActive = anyAimActive or silentActive

        -- Sticky management (rotation only)
        if anyActive and not lastAimOn then stickyRot = nil end
        if lastAimOn and not anyActive then
            if AIM.sticky_enabled then
                local cf = Camera.CFrame
                stickyRot = cf - cf.Position
            end
        end
        lastAimOn = anyActive

        if stickyRot then
            Camera.CFrame = CFrame.new(Camera.CFrame.Position) * stickyRot
            return
        end

        if not anyActive then
            if BodyAim.joints then resetBodyAim() end
            currentTarget = nil
            silentTarget = nil
            return
        end

        -- Read current (default) camera state as baseline
        local defCF = Camera.CFrame
        local defYaw, defPitch = cframeToYawPitch(defCF)
        local camPos = defCF.Position

        local now = tick()

        -- ============ SILENT = soft camera assist ============
        if silentActive and not anyAimActive then
            if now >= silentNextReacquire or not silentTarget
               or not silentTarget.Parent then
                silentTarget = pickTarget(
                    AIM.silent_fov, AIM.silent_maxdist,
                    AIM.silent_mindist, AIM.silent_bone)
                silentNextReacquire = now + 0.08
            end
            if not silentTarget or not silentTarget.Parent then return end
            if not targetAlive(silentTarget) then silentTarget = nil; return end

            local toT = silentTarget.Position - camPos
            if toT.Magnitude < 0.5 then return end
            toT = toT.Unit

            local tgtYaw   = math.atan2(-toT.X, -toT.Z)
            local tgtPitch = math.asin(math.clamp(toT.Y, -1, 1))

            local yawDiff   = normalizeAngle(tgtYaw - defYaw)
            local pitchDiff = tgtPitch - defPitch
            local angDeg = math.deg(math.sqrt(yawDiff*yawDiff + pitchDiff*pitchDiff))

            local fov = AIM.silent_fov or 40
            if angDeg > fov then return end

            -- FOV falloff
            local falloff = math.clamp((fov - angDeg) / fov, 0.0, 1.0)
            falloff = falloff * falloff

            -- Humanize
            if AIM.silent_humanize and AIM.humanize_level > 0 then
                humanUpdateOffsets(dt)
                local jx, jy = humanJitter(angDeg,
                    (AIM.assist_jitter or 0.05) * AIM.humanize_level * 0.5)
                yawDiff   = yawDiff   + jx
                pitchDiff = pitchDiff + jy

                local breath = math.sin(Human.breath_t * 0.35 * 6.283)
                               * 0.0006 * AIM.humanize_level
                pitchDiff = pitchDiff + breath

                local wobble = math.noise(Human.seed * 3, now * 0.35, 0)
                               * 0.006 * AIM.humanize_level
                yawDiff = yawDiff + wobble
            end

            local s = math.clamp(AIM.silent_strength or 0.12, 0, 1)
            local sCurve = s * s

            local sm = math.clamp(AIM.silent_smooth or 0.6, 0.05, 1.0)
            local lerpAmt = 1 - math.exp(-(0.4 + sm * 6) * dt)

            local dYaw   = yawDiff   * sCurve * falloff * lerpAmt
            local dPitch = pitchDiff * sCurve * falloff * lerpAmt

            if math.abs(math.deg(dYaw))   < 0.03 then dYaw   = 0 end
            if math.abs(math.deg(dPitch)) < 0.03 then dPitch = 0 end

            if dYaw ~= 0 or dPitch ~= 0 then
                local newYaw = defYaw + dYaw
                local newPitch = math.clamp(defPitch + dPitch, -1.48, 1.48)
                Camera.CFrame = CFrame.new(camPos)
                    * CFrame.fromEulerAnglesYXZ(newPitch, newYaw, 0)
                if AIM.body_aim then
                    local nY, nP = cframeToYawPitch(Camera.CFrame)
                    updateBodyAim(dt, nY, nP)
                end
            end
            return
        end

        -- ============ LOCK / ASSIST ============
        local humanize = (AIM.humanize_level > 0) and
            (lockActive and AIM.lock_humanize or AIM.assist_humanize)

        if anyAimActive ~= lastAimOn then
            currentTarget = nil
            Human.overshoot_active = false
            Human.next_react = 0
            Human.last_switch = tick()
        end

        if humanize then humanUpdateOffsets(dt) end

        -- Reacquire
        if now >= nextReacquire or not currentTarget
           or not currentTarget.Parent then
            local useFov  = lockActive and AIM.lock_fov    or AIM.assist_fov
            local useDist = lockActive and AIM.lock_maxdist or AIM.assist_maxdist
            local newTarget = pickTarget(useFov, useDist, AIM.minTargetDist)
            if newTarget and newTarget ~= currentTarget then
                local angDeg = screenAngle(newTarget.Position)
                if humanize then humanTriggerOvershoot(angDeg) end
                Human.last_switch = now
                if humanize and lockActive then
                    Human.next_react = now + rollReactDelay(
                        AIM.lock_react_min or 0.02, AIM.lock_react_max or 0.08)
                else
                    Human.next_react = now
                end
            end
            currentTarget = newTarget
            nextReacquire = now + (lockActive and 0.15 or 0.2)
        end

        if not currentTarget or not currentTarget.Parent then return end
        if not targetAlive(currentTarget) then currentTarget = nil; return end
        if currentTarget:IsDescendantOf(LocalPlayer.Character or game) then
            currentTarget = nil; return
        end

        -- Reaction delay
        if humanize and now < Human.next_react then return end

        -- Target position
        local targetPos = currentTarget.Position + Human.aim_offset
        if AIM.autohead_enabled then
            local ch = currentTarget.Parent
            local head = ch and ch:FindFirstChild("Head")
            if head then targetPos = head.Position + Human.aim_offset end
        end

        local toT = targetPos - camPos
        if toT.Magnitude < 0.5 then return end
        toT = toT.Unit

        local tgtYaw   = math.atan2(-toT.X, -toT.Z)
        local tgtPitch = math.asin(math.clamp(toT.Y, -1, 1))

        local yawDiff   = normalizeAngle(tgtYaw - defYaw)
        local pitchDiff = tgtPitch - defPitch
        local angDeg = math.deg(math.sqrt(yawDiff*yawDiff + pitchDiff*pitchDiff))

        -- Overshoot
        if Human.overshoot_active and humanize then
            Human.overshoot_t = Human.overshoot_t + dt
            local dur = 0.15
            if Human.overshoot_t < dur then
                local over = easeOutCubic(Human.overshoot_t / dur) * Human.overshoot_amount
                yawDiff   = yawDiff   + over * 0.5
                pitchDiff = pitchDiff + over * 0.5
            else
                Human.overshoot_active = false
            end
        end

        -- Jitter / breath / wobble
        if humanize then
            local jitter_amp = (assistActive and AIM.assist_jitter or AIM.lock_jitter)
                              * AIM.humanize_level
            local jx, jy = humanJitter(angDeg, jitter_amp * 0.06)
            yawDiff   = yawDiff   + jx
            pitchDiff = pitchDiff + jy

            local breath = math.sin(Human.breath_t * 0.35 * 6.283)
                           * 0.0008 * AIM.humanize_level
            pitchDiff = pitchDiff + breath

            local wobble = math.noise(Human.seed * 3, now * 0.35, 0)
                           * 0.008 * AIM.humanize_level
            yawDiff = yawDiff + wobble
        end

        -- Speed curve
        local speedCurve
        if angDeg < 1 then       speedCurve = 0.08 + angDeg * 0.15
        elseif angDeg < 4 then   speedCurve = 0.23 + (angDeg-1)/3 * 0.20
        elseif angDeg < 15 then  speedCurve = 0.43 + (angDeg-4)/11 * 0.42
        elseif angDeg < 40 then  speedCurve = 0.85 + (angDeg-15)/25 * 0.15
        else                     speedCurve = 1.0 end

        local sinceSwitch = now - (Human.last_switch or 0)
        local switchRamp = easeOutCubic(math.clamp(sinceSwitch / 0.25, 0.05, 1.0))

        local baseMaxSpeed = humanize and math.rad(160) or math.rad(400)

        local sMin, sMax
        if lockActive then
            sMin = AIM.lock_speed_min or 0.8
            sMax = AIM.lock_speed_max or 1.5
        else
            sMin = AIM.assist_speed_min or 0.8
            sMax = AIM.assist_speed_max or 1.5
        end
        updateSpeedMult(dt, sMin, sMax)

        local maxSpeed = baseMaxSpeed * speedCurve * switchRamp * Human.speedMult
        local step = maxSpeed * dt
        local angRad = math.rad(angDeg)
        local factor = (angRad > 0.0001) and math.min(1.0, step / angRad) or 1.0

        -- Assist: user smooth curve.  Lock: full pull.
        if assistActive and not lockActive then
            factor = factor * math.clamp(AIM.assist_smooth, 0.05, 1.0)
        end

        local dYaw   = yawDiff   * factor
        local dPitch = pitchDiff * factor

        if math.abs(math.deg(dYaw))   < 0.03 then dYaw   = 0 end
        if math.abs(math.deg(dPitch)) < 0.03 then dPitch = 0 end

        if dYaw ~= 0 or dPitch ~= 0 then
            local newYaw = defYaw + dYaw
            local newPitch = math.clamp(defPitch + dPitch, -1.48, 1.48)
            Camera.CFrame = CFrame.new(camPos)
                * CFrame.fromEulerAnglesYXZ(newPitch, newYaw, 0)
            if AIM.body_aim then
                local nY, nP = cframeToYawPitch(Camera.CFrame)
                updateBodyAim(dt, nY, nP)
            end
        end
    end
)

print("[CLIENT] CIGARETTE V5.0 loaded (unified delta-camera aim)")

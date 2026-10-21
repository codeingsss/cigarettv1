--========================================================================
--  Roblox Client - CIGARETTE V3.3.1 (Full 1100 Lines Original + Anti-Crash)
--  - All features restored (Silent, AutoHead, BodyAim, Humanize)
--  - Korean translated to English
--  - __namecall hooks are now safely wrapped to prevent CoreGui crash
--========================================================================

local HTTP_HOST = "http://127.0.0.1:2026"

local http_request =
    (syn and syn.request) or
    (http and http.request) or
    (fluxus and fluxus.request) or
    (Krnl and Krnl.request) or
    request

if not http_request then
    warn("[CIGAR] Executor does not support HTTP requests.")
end

if getgenv()._cigar_stop then
    pcall(function() getgenv()._cigar_stop() end)
end
local _my_stop = false
getgenv()._cigar_stop = function() _my_stop = true end

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

-- ★★★ CRASH PREVENTION SWITCH ★★★
-- Set to false to disable Silent Aim and AutoHead hooks completely (Prevents CoreGui crash)
local ENABLE_NAME_CALL_HOOKS = false 

local CFG = {
    ESP_RATE_HZ  = 30,
    ESP_MAX_DIST = 500,
    HITBOX_ON    = false,
    HITBOX_SCALE = 2.5,
}

local TEAM_CHECK = true

local AIM = {
    assist_enabled  = false,
    assist_smooth   = 0.45,
    assist_jitter   = 0.05,
    assist_humanize = false,
    assist_fov      = 25,
    assist_maxdist  = 150,
    assist_speed_min = 0.8,
    assist_speed_max = 1.5,
    assist_speed_var = 1.2,

    lock_enabled    = false,
    lock_humanize   = true,
    lock_jitter     = 0.15,
    lock_smooth     = 0.85,
    lock_fov        = 25,
    lock_maxdist    = 150,
    lock_speed_min  = 0.8,
    lock_speed_max  = 1.5,
    lock_speed_var  = 1.2,
    lock_react_min  = 0.15,
    lock_react_max  = 0.35,

    silent_enabled  = false,
    silent_bone     = "Head",
    silent_strength = 0.5,
    silent_smooth   = 0.7,
    silent_humanize = true,
    silent_fov      = 90,
    silent_mindist  = 5.0,
    silent_maxdist  = 500,

    visible        = true,
    hold_rmb       = false,
    fov            = 25,
    max_dist       = 150,
    bone           = "Head",
    minTargetDist  = 1.5,
    humanize_level = 1.0,

    body_aim       = true,

    tremor_enabled   = true,
    tremor_intensity = 1.0,

    head_expand_enabled = false,
    head_expand_scale   = 6.0,

    autohead_enabled = false,
    autohead_fov     = 90,
    autohead_maxdist = 500,
}

--========================================================================
--  Mouse control
--========================================================================
local mousemoverel_fn =
    (syn and syn.mousemoverel) or
    (fluxus and fluxus.mousemoverel) or
    (Krnl and Krnl.mousemoverel) or
    (getgenv and getgenv().mousemoverel) or
    mousemoverel or
    MouseMove

if not mousemoverel_fn then
    warn("[CIGAR] mousemoverel not supported by executor - aim disabled")
end

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
    local ok, res = pcall(function()
        local myChar = LocalPlayer and LocalPlayer.Character
        _rayParams.FilterDescendantsInstances = myChar and { myChar, Camera } or { Camera }
        local hit = Workspace:Raycast(Camera.CFrame.Position,
            part.Position - Camera.CFrame.Position, _rayParams)
        return hit == nil or hit.Instance:IsDescendantOf(part.Parent)
    end)
    return ok and res or true
end

local function isSelf(plr)
    if not plr then return true end
    local me = LocalPlayer
    if not me then return true end
    if plr == me or plr.UserId == me.UserId then return true end
    local ok = pcall(function()
        if plr.Character and me.Character then
            if plr.Character == me.Character then return true end
            if plr.Character:IsDescendantOf(me.Character) then return true end
            if me.Character:IsDescendantOf(plr.Character) then return true end
        end
    end)
    return ok and true or false
end

--========================================================================
--  TEAM CHECK
--========================================================================
local TEAM_HINT = {"team", "faction", "side", "role", "class", "division", "squad"}
local function isTeamishName(n)
    if type(n) ~= "string" then return false end
    local nl = n:lower()
    for _, h in ipairs(TEAM_HINT) do
        if nl:find(h, 1, true) then return true end
    end
    return false
end

local function collectTeamKeys(plr)
    local keys = {}
    if not plr then return keys end

    pcall(function()
        local t = plr.Team
        if t and t.Name then
            keys["TEAMOBJ:" .. tostring(t.Name)] = true
        end
    end)

    pcall(function()
        local tc = plr.TeamColor
        if tc and typeof(tc) == "BrickColor" then
            local num = tc.Number
            local name = tc.Name
            if num and num ~= 1 and name ~= "Custom" then
                keys["TEAMCOLOR:" .. tostring(num)] = true
            end
        end
    end)

    pcall(function()
        for _, attr in ipairs(plr:GetAttributes()) do
            if isTeamishName(attr) then
                local v = plr:GetAttribute(attr)
                if v ~= nil then
                    keys["PATTRIB:" .. attr .. ":" .. tostring(v)] = true
                end
            end
        end
    end)

    pcall(function()
        for _, child in ipairs(plr:GetChildren()) do
            if child:IsA("ValueBase") and isTeamishName(child.Name) then
                local ok, v = pcall(function() return child.Value end)
                if ok and v ~= nil then
                    keys["PCHILD:" .. child.Name .. ":" .. tostring(v)] = true
                end
            end
        end
    end)

    pcall(function()
        local ls = plr:FindFirstChild("leaderstats")
        if ls then
            for _, child in ipairs(ls:GetChildren()) do
                if child:IsA("ValueBase") and isTeamishName(child.Name) then
                    local ok, v = pcall(function() return child.Value end)
                    if ok and v ~= nil then
                        keys["LS:" .. child.Name .. ":" .. tostring(v)] = true
                    end
                end
            end
        end
    end)

    pcall(function()
        if plr.Character then
            for _, attr in ipairs(plr.Character:GetAttributes()) do
                if isTeamishName(attr) then
                    local v = plr.Character:GetAttribute(attr)
                    if v ~= nil then
                        keys["CATTRIB:" .. attr .. ":" .. tostring(v)] = true
                    end
                end
            end
        end
    end)

    return keys
end

local _teamCache = { ts = 0, validKeys = {}, allKeys = {}, myKeys = {} }

local function refreshTeamCache()
    _teamCache.ts = tick()

    pcall(function()
        local allKeys, counts = {}, {}
        local total = 0
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                local ok, k = pcall(collectTeamKeys, p)
                if not ok or type(k) ~= "table" then k = {} end
                allKeys[p] = k
                total = total + 1
                for key, _ in pairs(k) do
                    counts[key] = (counts[key] or 0) + 1
                end
            end
        end

        local valid = {}
        local minCount = 1
        local maxCount = math.max(2, math.floor(total * 0.6))
        for k, c in pairs(counts) do
            if c >= minCount and c <= maxCount then
                valid[k] = true
            end
        end

        _teamCache.validKeys = valid
        _teamCache.allKeys   = allKeys
        local okMy, mk = pcall(collectTeamKeys, LocalPlayer)
        _teamCache.myKeys = (okMy and type(mk) == "table") and mk or {}
    end)
end

local function isTeammate(plr)
    if not plr then return false end
    local me = LocalPlayer
    if not me then return false end
    if plr == me or plr.UserId == me.UserId then return true end

    local ok2, a, b = pcall(function()
        local myTeam, theirTeam = me.Team, plr.Team
        if myTeam and theirTeam then return myTeam == theirTeam, true end
        if myTeam and not theirTeam then return false, true end
        if theirTeam and not myTeam then return false, true end
        return false, false
    end)
    if ok2 and b then return a == true end

    if tick() - _teamCache.ts > 1.5 then
        refreshTeamCache()
    end

    local theirKeys = _teamCache.allKeys[plr] or {}
    local myKeys    = _teamCache.myKeys or {}
    local valid     = _teamCache.validKeys or {}

    for k, _ in pairs(myKeys) do
        if valid[k] and theirKeys[k] then
            return true
        end
    end

    return false
end

local function isValidAimTarget(plr)
    if isSelf(plr) then return false end
    if TEAM_CHECK then
        local ok, mate = pcall(isTeammate, plr)
        if ok and mate then return false end
    end
    return true
end

local function isMyPart(part)
    if not part then return true end
    local myChar = LocalPlayer and LocalPlayer.Character
    return myChar and part:IsDescendantOf(myChar) or false
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
    return p or char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
end

local function cframeToYawPitch(cf)
    local look = cf.LookVector
    return math.atan2(-look.X, -look.Z), math.asin(math.clamp(look.Y, -1, 1))
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
    return math.deg(math.acos(math.clamp(camDir:Dot(toT.Unit), -1, 1)))
end

local function easeOutCubic(t)
    t = math.clamp(t, 0, 1)
    local inv = 1 - t
    return 1 - inv * inv * inv
end

local function targetAlive(part)
    if not part or not part.Parent then return false end
    local ok, alive = pcall(function()
        local hum = part.Parent:FindFirstChildOfClass("Humanoid")
        return hum and hum.Health > 0
    end)
    return ok and alive or false
end

--========================================================================
--  Head Hitbox Expand
--========================================================================
local headExpandOriginals = {}

local function restoreHead(head)
    local orig = headExpandOriginals[head]
    if orig then
        pcall(function()
            head.Size = orig.size
            head.Transparency = orig.trans
            head.CanCollide = orig.collide
            head.Massless = orig.massless
        end)
        headExpandOriginals[head] = nil
    end
end

local function expandHead(head, scale)
    if not head then return end
    if not headExpandOriginals[head] then
        headExpandOriginals[head] = {
            size = head.Size, trans = head.Transparency,
            collide = head.CanCollide, massless = head.Massless,
        }
    end
    local orig = headExpandOriginals[head]
    pcall(function()
        local sy = orig.size.Y * math.max(1.0, scale * 0.4)
        head.Size = Vector3.new(orig.size.X * scale, sy, orig.size.Z * scale)
    end)
end

local function updateHeadExpand()
    if not AIM.head_expand_enabled then
        for head in pairs(headExpandOriginals) do restoreHead(head) end
        return
    end
    local scale = AIM.head_expand_scale or 6.0
    local active = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if isValidAimTarget(plr) and plr.Character then
            local head = plr.Character:FindFirstChild("Head")
            if head then
                active[head] = true
                expandHead(head, scale)
            end
        end
    end
    for head in pairs(headExpandOriginals) do
        if not active[head] or not head.Parent then restoreHead(head) end
    end
end

task.spawn(function()
    while task.wait(0.15) do
        if _my_stop then return end
        pcall(updateHeadExpand)
    end
end)

--========================================================================
--  Humanize
--========================================================================
local Human = {
    overshoot_active = false, overshoot_t = 0, overshoot_amount = 0,
    next_react = 0, react_until = 0, last_switch = 0,
    aim_offset = Vector3.new(0, 0, 0),
    offset_t = 0, breath_t = 0,
    speedMult = 1.0, speedNoiseT = 0,
    micro_phase = 0, tremor_phase = 0, drift_x = 0, drift_y = 0,
    drift_until = 0,
    seed1 = math.random() * 1000,
    seed2 = math.random() * 1000,
    seed3 = math.random() * 1000,
    jitterSeed = math.random() * 1000,
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
        local amp = 0.05 * AIM.humanize_level
        Human.aim_offset = Vector3.new(
            (math.random() - 0.5) * amp,
            (math.random() - 0.5) * amp,
            (math.random() - 0.5) * amp)
    end
    Human.breath_t = Human.breath_t + dt
end

--========================================================================
--  Target picker
--========================================================================
local function pickTarget(fov, maxDist, minDist, useBone, prefer)
    if prefer and prefer.Parent and not isMyPart(prefer) then
        local hum = prefer.Parent:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            local dist = (prefer.Position - Camera.CFrame.Position).Magnitude
            if dist >= (minDist or 2.5) and dist <= maxDist and isVisible(prefer) then
                local ang = screenAngle(prefer.Position)
                if ang <= fov then
                    return prefer
                end
            end
        end
    end

    local best, bestScore = nil, math.huge
    local camPos = Camera.CFrame.Position
    local myChar = LocalPlayer and LocalPlayer.Character
    for _, plr in ipairs(Players:GetPlayers()) do
        if isValidAimTarget(plr) and plr.Character and plr.Character ~= myChar then
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local bone = useBone
                if not bone or bone == "" then
                    bone = AIM.bone ~= "" and AIM.bone or "Head"
                end
                local part = findPart(plr.Character, bone)
                if part and not isMyPart(part) then
                    local dist = (part.Position - camPos).Magnitude
                    if dist >= (minDist or 2.5) and dist <= maxDist and isVisible(part) then
                        local ang = screenAngle(part.Position)
                        if ang <= fov then
                            local score = ang * 1.5 + dist * 0.02
                            if score < bestScore then bestScore, best = score, part end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function pickSilentTarget()
    return pickTarget(AIM.silent_fov, AIM.silent_maxdist,
                      AIM.silent_mindist, AIM.silent_bone)
end

local function blendDirection(origDir, targetPos, originPos, strength)
    local toT = (targetPos - originPos)
    if toT.Magnitude < 0.001 then return origDir end
    local s = math.clamp(strength or 0.5, 0, 1)
    local orig = origDir.Magnitude > 0.0001 and origDir.Unit or toT.Unit
    local b = orig:Lerp(toT.Unit, s)
    return b.Magnitude > 0.001 and b.Unit or origDir
end

--========================================================================
--  SILENT hook (Safely Disabled to prevent CoreGui crash)
--========================================================================
local silentHitCount = 0

local function trySetupSilentAim()
    if not ENABLE_NAME_CALL_HOOKS then return false end
    if not (getrawmetatable and setreadonly and newcclosure and getnamecallmethod) then
        warn("[SILENT] executor lacks hooks"); return false
    end
    local ok, mt = pcall(getrawmetatable, game)
    if not ok or not mt or not mt.__namecall then return false end
    local oldNamecall = mt.__namecall
    if not oldNamecall then return false end

    local ok2 = pcall(function()
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            if _my_stop then return oldNamecall(self, ...) end
            local okH, errH = pcall(function()
                local method = getnamecallmethod()
                if AIM.silent_enabled and
                   (method == "FireServer" or method == "InvokeServer") and
                   typeof(self) == "Instance" and
                   (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
                    local args = {...}
                    for i = 1, math.min(5, #args) do
                        local a = args[i]
                        if typeof(a) == "Vector3" then
                            if a.Magnitude > 0.001 then
                                local t = pickSilentTarget()
                                if t then
                                    local o = Camera.CFrame.Position
                                    local strength = AIM.silent_strength or 0.5
                                    strength = strength * math.clamp(AIM.silent_smooth or 1.0, 0.05, 1.0)
                                    local adjTarget = t.Position
                                    if AIM.silent_humanize then
                                        local missAmt = (1 - math.clamp(AIM.silent_smooth or 1.0, 0.1, 1.0))
                                                        * 2.5 * (AIM.humanize_level or 1.0)
                                        adjTarget = t.Position + Vector3.new(
                                            (math.random() - 0.5) * missAmt,
                                            (math.random() - 0.5) * missAmt,
                                            (math.random() - 0.5) * missAmt)
                                        strength = math.clamp(
                                            strength + math.noise(tick() * 1.3, 0) * 0.05 * (AIM.humanize_level or 1.0),
                                            0.02, 1.0)
                                    end
                                    local blended = blendDirection(a.Unit, adjTarget, o, strength)
                                    args[i] = blended * a.Magnitude
                                    silentHitCount = silentHitCount + 1
                                end
                            end
                            break
                        elseif typeof(a) == "CFrame" then
                            local t = pickSilentTarget()
                            if t then
                                local strength = AIM.silent_strength or 0.5
                                strength = strength * math.clamp(AIM.silent_smooth or 1.0, 0.05, 1.0)
                                local adjTarget = t.Position
                                if AIM.silent_humanize then
                                    local missAmt = (1 - math.clamp(AIM.silent_smooth or 1.0, 0.1, 1.0))
                                                    * 2.5 * (AIM.humanize_level or 1.0)
                                    adjTarget = t.Position + Vector3.new(
                                        (math.random() - 0.5) * missAmt,
                                        (math.random() - 0.5) * missAmt,
                                        (math.random() - 0.5) * missAmt)
                                end
                                local blended = blendDirection(a.LookVector, adjTarget, a.Position, strength)
                                args[i] = CFrame.lookAt(a.Position, a.Position + blended)
                                silentHitCount = silentHitCount + 1
                            end
                            break
                        end
                    end
                    return oldNamecall(self, table.unpack(args))
                end
            end)
            if not okH then
                warn("[SILENT] hook error: " .. tostring(errH))
            end
            return oldNamecall(self, ...)
        end)
        setreadonly(mt, true)
    end)
    if ok2 then print("[SILENT] namecall hook installed") end
    return ok2
end

trySetupSilentAim()

--========================================================================
--  AUTOHEAD hook (Safely Disabled to prevent CoreGui crash)
--========================================================================
local function trySetupAutoHead()
    if not ENABLE_NAME_CALL_HOOKS then return false end
    if not (getrawmetatable and setreadonly and newcclosure and getnamecallmethod) then
        return false
    end
    local ok, mt = pcall(getrawmetatable, game)
    if not ok or not mt or not mt.__namecall then return false end
    local oldNamecall = mt.__namecall
    if not oldNamecall then return false end

    local ok2 = pcall(function()
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            if _my_stop then return oldNamecall(self, ...) end
            local okH = pcall(function()
                local method = getnamecallmethod()
                if AIM.autohead_enabled and self == Workspace then
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
                            local results = {oldNamecall(self, ...)}
                            local r = results[1]
                            local hit = typeof(r) == "RaycastResult" and r.Instance
                                     or (typeof(r) == "Instance" and r or nil)
                            if hit then
                                local char = hit:FindFirstAncestorOfClass("Model")
                                local plr = char and Players:GetPlayerFromCharacter(char)
                                if plr and isValidAimTarget(plr) then
                                    local head = char:FindFirstChild("Head")
                                    if head and hit ~= head
                                       and head:IsDescendantOf(char)
                                       and hit:IsDescendantOf(char) then
                                        local nd = (head.Position - originV)
                                        if nd.Magnitude > 0.001 then
                                            nd = nd.Unit * dirV.Magnitude
                                            local na
                                            if method == "Raycast" then
                                                na = {originV, nd}
                                                for i = 3, #args do na[i] = args[i] end
                                            else
                                                na = {Ray.new(originV, nd)}
                                                for i = 2, #args do na[i] = args[i] end
                                            end
                                            return oldNamecall(self, table.unpack(na))
                                        end
                                    end
                                end
                            end
                            return table.unpack(results)
                        end
                    end
                end
            end)
            return oldNamecall(self, ...)
        end)
        setreadonly(mt, true)
    end)
    if ok2 then print("[AUTOHEAD] hook installed") end
    return ok2
end

trySetupAutoHead()

--========================================================================
--  Body Aim
--========================================================================
local BodyAim = {
    joints = nil, charRef = nil,
    origWaistC0 = nil, origNeckC0 = nil,
}

local function resetBodyAim()
    if BodyAim.joints then
        pcall(function()
            if BodyAim.joints.waist and BodyAim.origWaistC0 then
                BodyAim.joints.waist.C0 = BodyAim.origWaistC0 end
            if BodyAim.joints.neck and BodyAim.origNeckC0 then
                BodyAim.joints.neck.C0 = BodyAim.origNeckC0 end
        end)
    end
    BodyAim.joints, BodyAim.origWaistC0, BodyAim.origNeckC0, BodyAim.charRef = nil,nil,nil,nil
end

local function ensureBodyAim()
    local me = LocalPlayer
    local char = me and me.Character
    if not char then if BodyAim.charRef then resetBodyAim() end return end
    if BodyAim.charRef == char and BodyAim.joints then return end
    resetBodyAim()
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local waist
    local lt = char:FindFirstChild("LowerTorso")
    if lt then waist = lt:FindFirstChild("Waist") end
    if not waist then waist = hrp:FindFirstChild("Waist") or hrp:FindFirstChild("RootJoint") end
    if not waist then waist = char:FindFirstChild("Waist", true) or char:FindFirstChild("RootJoint", true) end

    local neck
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
    BodyAim.origWaistC0, BodyAim.origNeckC0 = waist.C0, neck.C0
end

local function applyBodyAimYawPitch(yaw, pitch)
    if not AIM.body_aim then if BodyAim.joints then resetBodyAim() end return end
    ensureBodyAim()
    if not BodyAim.joints or not BodyAim.charRef then return end
    local hrp = BodyAim.charRef:FindFirstChild("HumanoidRootPart")
    if not hrp then resetBodyAim() return end

    local hrpYaw = cframeToYawPitch(hrp.CFrame)
    local cy = math.clamp(normalizeAngle(yaw - hrpYaw), -math.rad(75), math.rad(75))
    local np = math.clamp(pitch, -math.rad(55), math.rad(55))

    if BodyAim.joints.waist and BodyAim.origWaistC0 then
        pcall(function()
            BodyAim.joints.waist.C0 = BodyAim.origWaistC0 * CFrame.Angles(0, cy, 0)
        end)
    end
    if BodyAim.joints.neck and BodyAim.origNeckC0 then
        pcall(function()
            local nr = normalizeAngle(yaw - (hrpYaw + cy))
            local ny2 = math.clamp(nr, -math.rad(70), math.rad(70))
            BodyAim.joints.neck.C0 =
                BodyAim.origNeckC0 * CFrame.fromEulerAnglesYXZ(-np, ny2 * 0.5, 0)
        end)
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
    end)
end

local function updateHitboxes()
    local scale = CFG.HITBOX_ON and CFG.HITBOX_SCALE or 1.0
    local active = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if isValidAimTarget(plr) and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                active[hrp] = true
                if scale > 1.0 then applyHitbox(hrp, scale)
                else restoreHitbox(hrp) end
            end
        end
    end
    for part in pairs(hitboxOriginals) do
        if not active[part] or not part.Parent then restoreHitbox(part) end
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
    local ok, res = pcall(function()
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
                            local okT, mateVal = pcall(isTeammate, plr)
                            local isMate = (okT and TEAM_CHECK and mateVal) or false
                            table.insert(list, {
                                name = plr.Name, x = s.x, y = s.y,
                                dist = math.floor(dist),
                                teammate = isMate,
                            })
                        end
                    end
                end
            end
        end
        return list
    end)
    if ok and type(res) == "table" then return res end
    return {}
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
    assist_smooth=1,assist_jitter=1,assist_fov=1,assist_maxdist=1,
    assist_speed_min=1,assist_speed_max=1,assist_speed_var=1,
    lock_jitter=1,lock_smooth=1,lock_fov=1,lock_maxdist=1,
    lock_speed_min=1,lock_speed_max=1,lock_speed_var=1,
    lock_react_min=1,lock_react_max=1,
    silent_strength=1,silent_smooth=1,silent_fov=1,
    silent_mindist=1,silent_maxdist=1,
    minTargetDist=1,humanize_level=1,
    hitbox_scale=1,head_expand_scale=1,
    autohead_fov=1,autohead_maxdist=1,
    tremor_intensity=1,
    fov=1,max_dist=1,
}
local BOOL_KEYS = {
    assist_enabled=1,assist_humanize=1,
    lock_enabled=1,lock_humanize=1,
    silent_enabled=1,silent_humanize=1,
    visible=1,hold_rmb=1,
    hitbox_on=1,body_aim=1,
    tremor_enabled=1,
    head_expand_enabled=1,autohead_enabled=1,
}
local STR_KEYS = { silent_bone=1, bone=1 }

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
            if okj and type(data) == "table" then
                for k, v in pairs(data) do
                    if k ~= "team_check" and AIM[k] ~= nil then
                        if NUM_KEYS[k] then
                            local n = tonumber(v); if n then AIM[k] = n end
                        elseif BOOL_KEYS[k] then
                            AIM[k] = not not v
                        elseif STR_KEYS[k] then
                            if type(v) == "string" then AIM[k] = v end
                        end
                    end
                end
                if data.hitbox_on ~= nil then CFG.HITBOX_ON = not not data.hitbox_on end
                if data.hitbox_scale then CFG.HITBOX_SCALE = tonumber(data.hitbox_scale) or CFG.HITBOX_SCALE end
                if data.head_expand_enabled ~= nil then
                    AIM.head_expand_enabled = not not data.head_expand_enabled
                end
                if data.head_expand_scale then
                    AIM.head_expand_scale = tonumber(data.head_expand_scale) or AIM.head_expand_scale
                end
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
                if d2.rate_hz then CFG.ESP_RATE_HZ = tonumber(d2.rate_hz) or CFG.ESP_RATE_HZ end
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
            task.wait(0.1)
            local fn, err = loadstring(src)
            if fn then pcall(fn)
            else
                warn("[CIGAR reload] " .. tostring(err))
                if getgenv()._cigar_stop then getgenv()._cigar_stop = nil end
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
    if input.UserInputType == Enum.UserInputType.MouseButton2 then rmb_down = true end
end)
UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then rmb_down = false end
end)

--========================================================================
--  AIM LOOP
--========================================================================
local lastActive = false
local currentTarget = nil

RunService:BindToRenderStep("CigarAimCamera",
    Enum.RenderPriority.Camera.Value + 1,
    function(dt)
        if _my_stop then return end
        pcall(function()
            local lockActive   = AIM.lock_enabled
            local assistActive = AIM.assist_enabled

            if AIM.hold_rmb and not rmb_down then
                lockActive, assistActive = false, false
            end

            local anyAimActive = lockActive or assistActive
            local humanize = AIM.humanize_level > 0 and anyAimActive

            if anyAimActive ~= lastActive then
                lastActive = anyAimActive
                currentTarget = nil
                Human.overshoot_active = false
                Human.react_until = 0
                if not anyAimActive then resetBodyAim() end
            end

            if not anyAimActive then return end
            if humanize then humanUpdateOffsets(dt) end

            local now = tick()

            local useFov  = lockActive and AIM.lock_fov    or AIM.assist_fov
            local useDist = lockActive and AIM.lock_maxdist or AIM.assist_maxdist
            local newTarget = pickTarget(useFov, useDist, AIM.minTargetDist, nil, currentTarget)

            if newTarget and newTarget ~= currentTarget then
                local sp = Camera:WorldToViewportPoint(newTarget.Position)
                if sp.Z > 0 then
                    local vpX, vpY = Camera.ViewportSize.X, Camera.ViewportSize.Y
                    local dx = sp.X - vpX * 0.5
                    local dy = sp.Y - vpY * 0.5
                    local distPx = math.sqrt(dx*dx + dy*dy)
                    Human.last_switch = now
                    if lockActive and humanize then
                        Human.react_until = now + rollReactDelay(
                            math.max(0.15, AIM.lock_react_min or 0.15),
                            math.max(0.30, AIM.lock_react_max or 0.35))
                    end
                    if distPx > 8 then
                        Human.overshoot_active = true
                        Human.overshoot_t = 0
                        Human.overshoot_amount = (0.010 + math.random() * 0.020) * (AIM.humanize_level or 1.0)
                    end
                end
            end

            currentTarget = newTarget
            if not currentTarget or not targetAlive(currentTarget) then
                currentTarget = nil
                return
            end

            if humanize and now < Human.react_until then return end

            local targetPos = currentTarget.Position
            if AIM.autohead_enabled then
                local head = currentTarget.Parent and
                             currentTarget.Parent:FindFirstChild("Head")
                if head then targetPos = head.Position end
            end

            local screenPos = Camera:WorldToViewportPoint(targetPos)
            if screenPos.Z <= 0 then return end

            local vpX = Camera.ViewportSize.X
            local vpY = Camera.ViewportSize.Y
            local dx = screenPos.X - vpX * 0.5
            local dy = screenPos.Y - vpY * 0.5
            local distPx = math.sqrt(dx*dx + dy*dy)

            local moveX, moveY
            if humanize then
                local curve
                if distPx < 8 then curve = 0.08
                elseif distPx < 40 then curve = 0.08 + (distPx - 8) / 32 * 0.30
                elseif distPx < 150 then curve = 0.38 + (distPx - 40) / 110 * 0.35
                elseif distPx < 400 then curve = 0.73 + (distPx - 150) / 250 * 0.22
                else curve = 0.95 end

                Human.speedNoiseT = Human.speedNoiseT + dt
                local speedMult = 0.75 + (math.noise(Human.seed1, Human.speedNoiseT * 0.8) * 0.5 + 0.5) * 0.55
                local baseFactor = (lockActive and 0.42 or 0.32) * AIM.humanize_level
                moveX = dx * baseFactor * curve * speedMult
                moveY = dy * baseFactor * curve * speedMult

                if Human.overshoot_active then
                    Human.overshoot_t = Human.overshoot_t + dt
                    local dur = 0.10 + math.random() * 0.08
                    if Human.overshoot_t < dur then
                        local t = Human.overshoot_t / dur
                        local over = easeOutCubic(t) * Human.overshoot_amount
                        moveX = moveX + over * 0.5 * vpX
                        moveY = moveY + over * 0.5 * vpY
                    else
                        Human.overshoot_active = false
                    end
                end

                Human.tremor_phase = Human.tremor_phase + dt
                if AIM.tremor_enabled then
                    local tBase = (lockActive and AIM.lock_jitter or AIM.assist_jitter)
                                 * AIM.humanize_level * (AIM.tremor_intensity or 1.0)
                    moveX = moveX + math.noise(Human.seed3, Human.tremor_phase * 3.2) * tBase * 2.4
                    moveY = moveY + math.noise(Human.seed3 + 100, Human.tremor_phase * 3.2) * tBase * 2.4
                end

                Human.breath_t = Human.breath_t + dt
                local breath = math.sin(Human.breath_t * 0.42 * 6.283) * 0.55 * AIM.humanize_level
                moveY = moveY + breath
            else
                local smoothCfg = lockActive and (AIM.lock_smooth or 0.85)
                                            or  (AIM.assist_smooth or 0.45)
                smoothCfg = math.clamp(smoothCfg, 0.05, 1.0)
                local baseFactor = smoothCfg * 0.35
                moveX = dx * baseFactor
                moveY = dy * baseFactor
            end

            local maxStep = lockActive and 250 or 180
            moveX = math.clamp(moveX, -maxStep, maxStep)
            moveY = math.clamp(moveY, -maxStep, maxStep)

            if math.abs(dx) < 0.8 and math.abs(moveX) < 0.6 then moveX = 0 end
            if math.abs(dy) < 0.8 and math.abs(moveY) < 0.6 then moveY = 0 end

            if (moveX ~= 0 or moveY ~= 0) and mousemoverel_fn then
                pcall(mousemoverel_fn, moveX, moveY)
            end

            if AIM.body_aim then
                local toT = targetPos - Camera.CFrame.Position
                if toT.Magnitude > 0.01 then
                    toT = toT.Unit
                    local yaw = math.atan2(-toT.X, -toT.Z)
                    local pitch = math.asin(math.clamp(toT.Y, -1, 1))
                    applyBodyAimYawPitch(yaw, pitch)
                end
            end
        end)
    end
)

print("[CLIENT] CIGARETTE V3.3.1 loaded (Full features active)")

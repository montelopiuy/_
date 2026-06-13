local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

local CFG = {
    WalkSpeed       = 16,
    AutoPickMidas   = true,
    TpTool          = true,
    FlySpeed        = 50,
    AutoPrompt      = true,
    InstantPrompt   = true,
    ActivateDelay   = 0.3,
}

local WEBHOOK_URL = "https://discord.com/api/webhooks/1515089177811619862/CGozdv6rhkggJDQNY85o6FCvHksX0vyWa4GPgh3CmcHARd3PaB5fOoIX4tegr93Cns2q"

local lastStockHash = nil

local function sendToWebhook(description, color)
    local data = {
        embeds = {{
            title = "🌱 Seed notifier",
            description = description,
            color = color or 0x00ff00,
            footer = { text = "Mise à jour automatique" }
        }}
    }
    local json = HttpService:JSONEncode(data)
    local headers = {["Content-Type"] = "application/json"}

    pcall(function()
        if syn and syn.request then
            syn.request({ Url = WEBHOOK_URL, Method = "POST", Headers = headers, Body = json })
        elseif request then
            request({ Url = WEBHOOK_URL, Method = "POST", Headers = headers, Body = json })
        else
            warn("[Webhook] Aucune fonction request trouvée")
        end
    end)
end

local promptRegistry    = {}
local originalDurations = {}
local lastActivated     = {}
local promptConnections = {}

local function activateNow(prompt)
    if not CFG.AutoPrompt then return end
    if not prompt or not prompt.Parent then return end
    if not prompt.Enabled then return end

    local now = tick()
    if lastActivated[prompt] and (now - lastActivated[prompt]) < CFG.ActivateDelay then
        return
    end
    lastActivated[prompt] = now

    task.spawn(function()
        pcall(function()
            prompt:InputHoldBegin()
            task.wait(prompt.HoldDuration + 0.05)
            prompt:InputHoldEnd()
        end)
    end)
end

local function patchDuration(prompt)
    if CFG.InstantPrompt then
        prompt.HoldDuration = 0
    else
        if originalDurations[prompt] then
            prompt.HoldDuration = originalDurations[prompt]
        end
    end
end

local function registerPrompt(obj)
    if not obj:IsA("ProximityPrompt") then return end
    if promptRegistry[obj] then return end

    promptRegistry[obj] = true
    originalDurations[obj] = obj.HoldDuration
    patchDuration(obj)

    promptConnections[obj] = obj.PromptShown:Connect(function()
        activateNow(obj)
    end)

    obj.AncestryChanged:Connect(function()
        if not obj.Parent then
            if promptConnections[obj] then
                promptConnections[obj]:Disconnect()
                promptConnections[obj] = nil
            end
            promptRegistry[obj] = nil
            originalDurations[obj] = nil
            lastActivated[obj] = nil
        end
    end)
end

for _, v in ipairs(workspace:GetDescendants()) do registerPrompt(v) end
workspace.DescendantAdded:Connect(registerPrompt)

task.spawn(function()
    while true do
        task.wait(60)
        if CFG.InstantPrompt then
            for p in pairs(promptRegistry) do
                if p and p.Parent then p.HoldDuration = 0 end
            end
        else
            for p, dur in pairs(originalDurations) do
                if p and p.Parent then p.HoldDuration = dur end
            end
        end
    end
end)

local function getHumanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function enforceWalkSpeed(hum)
    if hum and hum.WalkSpeed ~= CFG.WalkSpeed then
        hum.WalkSpeed = CFG.WalkSpeed
    end
end

local function setupWalkSpeedForCharacter(char)
    local hum = char:WaitForChild("Humanoid", 10)
    if hum then
        enforceWalkSpeed(hum)
        hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            enforceWalkSpeed(hum)
        end)
    end
end

LocalPlayer.CharacterAdded:Connect(setupWalkSpeedForCharacter)
if LocalPlayer.Character then setupWalkSpeedForCharacter(LocalPlayer.Character) end
RunService.Heartbeat:Connect(function()
    local hum = getHumanoid()
    if hum then enforceWalkSpeed(hum) end
end)

local function giveTpTool()
    if not CFG.TpTool then return end
    local existing = LocalPlayer.Backpack:FindFirstChild("Tp tool (Equip to Click TP)")
    if existing then existing:Destroy() end
    local char = LocalPlayer.Character
    if char then
        local toolInHand = char:FindFirstChild("Tp tool (Equip to Click TP)")
        if toolInHand then toolInHand:Destroy() end
    end

    local mouse = LocalPlayer:GetMouse()
    local tool = Instance.new("Tool")
    tool.RequiresHandle = false
    tool.Name = "Tp tool (Equip to Click TP)"
    tool.Activated:Connect(function()
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local pos = mouse.Hit.Position + Vector3.new(0, 2.5, 0)
            LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(pos)
        end
    end)
    tool.Parent = LocalPlayer.Backpack
end

local function removeTpTool()
    local existing = LocalPlayer.Backpack:FindFirstChild("Tp tool (Equip to Click TP)")
    if existing then existing:Destroy() end
    local char = LocalPlayer.Character
    if char then
        local toolInHand = char:FindFirstChild("Tp tool (Equip to Click TP)")
        if toolInHand then toolInHand:Destroy() end
    end
end

local function updateTpTool()
    if CFG.TpTool then giveTpTool() else removeTpTool() end
end

LocalPlayer.CharacterAdded:Connect(function() task.wait(1); updateTpTool() end)
if LocalPlayer.Character then task.wait(1); updateTpTool() end

local midas = {
    active = CFG.AutoPickMidas,
    locations = {},
    currentIndex = 0,
    currentTarget = nil,
    loopTask = nil,
    statusText = "En attente",
}

local function refreshMidasLocations()
    local folder = workspace:FindFirstChild("Map")
    if not folder then return {} end
    local spawnLoc = folder:FindFirstChild("SeedPackSpawnServerLocations")
    if not spawnLoc then return {} end
    local valid = {}
    for _, obj in ipairs(spawnLoc:GetChildren()) do
        if obj and obj.Parent then table.insert(valid, obj) end
    end
    return valid
end

local function teleportToTarget(target)
    if not target or not target.Parent then return false end
    local char = LocalPlayer.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local pos
    if target:IsA("BasePart") then
        pos = target.Position
    elseif target:IsA("Model") and target.PrimaryPart then
        pos = target.PrimaryPart.Position
    elseif target:IsA("CFrameValue") then
        pos = target.Value.Position
    else
        local att = target:FindFirstChild("Position") or target:FindFirstChild("CFrame")
        if att then
            if att:IsA("Vector3Value") then pos = att.Value
            elseif att:IsA("CFrameValue") then pos = att.Value.Position
            end
        end
    end
    if not pos then return false end
    local teleportPos = pos + Vector3.new(0, 3, 0)
    pcall(function()
        hrp.CFrame = CFrame.new(teleportPos)
        task.wait(0.05)
    end)
    return true
end

local function nextMidasTarget()
    midas.locations = refreshMidasLocations()
    if #midas.locations == 0 then
        midas.currentTarget = nil
        midas.currentIndex = 0
        midas.statusText = "Aucune cible"
        return nil
    end
    if midas.currentIndex >= #midas.locations then
        midas.currentIndex = 1
    else
        midas.currentIndex = midas.currentIndex + 1
    end
    local newTarget = midas.locations[midas.currentIndex]
    midas.currentTarget = newTarget
    midas.statusText = string.format("Cible %d/%d : %s", midas.currentIndex, #midas.locations, newTarget and newTarget.Name or "?")
    return newTarget
end

local function startMidasLoop()
    if midas.loopTask then task.cancel(midas.loopTask) end
    midas.loopTask = task.spawn(function()
        while midas.active do
            while not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") do
                task.wait(1)
                if not midas.active then return end
            end
            if #midas.locations == 0 then
                midas.locations = refreshMidasLocations()
                if #midas.locations > 0 and midas.currentIndex == 0 then
                    midas.currentIndex = 1
                    midas.currentTarget = midas.locations[1]
                    midas.statusText = string.format("Cible 1/%d : %s", #midas.locations, midas.currentTarget.Name)
                end
            end
            if midas.currentTarget and (not midas.currentTarget.Parent or not midas.currentTarget:IsDescendantOf(workspace)) then
                midas.statusText = "Cible disparue, suivant..."
                local next = nextMidasTarget()
                if next then teleportToTarget(next) end
            end
            if not midas.currentTarget and #midas.locations > 0 then
                if midas.currentIndex == 0 then midas.currentIndex = 1 end
                midas.currentTarget = midas.locations[midas.currentIndex]
                if midas.currentTarget then
                    midas.statusText = string.format("Cible %d/%d : %s", midas.currentIndex, #midas.locations, midas.currentTarget.Name)
                    teleportToTarget(midas.currentTarget)
                end
            end
            task.wait(1)
        end
    end)
end

local function setMidasActive(active)
    midas.active = active
    CFG.AutoPickMidas = active
    if active then
        midas.locations = refreshMidasLocations()
        if #midas.locations > 0 then
            midas.currentIndex = 1
            midas.currentTarget = midas.locations[1]
            midas.statusText = string.format("Cible 1/%d : %s", #midas.locations, midas.currentTarget.Name)
            teleportToTarget(midas.currentTarget)
        else
            midas.statusText = "Aucune cible"
        end
        startMidasLoop()
    else
        if midas.loopTask then task.cancel(midas.loopTask) end
        midas.currentTarget = nil
        midas.statusText = "Désactivé"
    end
end

local function watchMidasFolder()
    local folder = workspace:FindFirstChild("Map")
    if folder then
        local spawnLoc = folder:FindFirstChild("SeedPackSpawnServerLocations")
        if spawnLoc then
            local function refresh()
                if midas.active then midas.locations = refreshMidasLocations() end
            end
            spawnLoc.ChildAdded:Connect(refresh)
            spawnLoc.ChildRemoved:Connect(refresh)
        end
    end
end

if CFG.AutoPickMidas then
    task.defer(function() setMidasActive(true); watchMidasFolder() end)
end

local function getNonZeroStock()
    local itemsFolder = ReplicatedStorage:FindFirstChild("StockValues")
    if itemsFolder then itemsFolder = itemsFolder:FindFirstChild("SeedShop") end
    if itemsFolder then itemsFolder = itemsFolder:FindFirstChild("Items") end
    if not itemsFolder then return {} end

    local stock = {}
    for _, item in ipairs(itemsFolder:GetChildren()) do
        if (item:IsA("IntValue") or item:IsA("NumberValue")) and item.Value > 0 then
            stock[item.Name] = item.Value
        end
    end
    return stock
end

local function encodeStockToString(stock)
    if not stock or next(stock) == nil then
        return "Aucun item en stock pour le moment."
    end
    local lines = {}
    for name, qty in pairs(stock) do
        table.insert(lines, string.format("✅ **%s** : %d", name, qty))
    end
    table.sort(lines)
    return table.concat(lines, "\n")
end

local function checkAndSendStock()
    local currentStock = getNonZeroStock()
    local hash = ""
    for name, qty in pairs(currentStock) do
        hash = hash .. name .. ":" .. qty .. "|"
    end
    if hash == lastStockHash then return end
    lastStockHash = hash

    local stockText = encodeStockToString(currentStock)
    local midasInfo = string.format(
        "**Midas** : %s\n**Cible** : %s\n**Index** : %d",
        midas.active and "✅ ACTIF" or "❌ INACTIF",
        midas.currentTarget and midas.currentTarget.Name or "aucune",
        midas.currentIndex
    )
    local finalDesc = string.format("📦 **Stock disponible** :\n%s\n\n📍 **AutoPick** :\n%s", stockText, midasInfo)
    sendToWebhook(finalDesc, 0x00ff00)
end

task.spawn(function() while true do task.wait(10); checkAndSendStock() end end)
task.defer(function() task.wait(3); checkAndSendStock() end)

local flyEnabled = false
local flySpeed = CFG.FlySpeed
local flyConnection = nil
local flyBodyVel = nil
local flyBodyGyro = nil

local moveState = {
    forward = false,
    back = false,
    left = false,
    right = false,
    up = false,
    down = false
}

local function setNoclip(state)
    local char = LocalPlayer.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = not state
        end
    end
end

local function updateFlyMovement()
    if not flyEnabled or not flyBodyVel then return end
    local dir = Vector3.zero

    if moveState.forward then dir = dir + workspace.CurrentCamera.CFrame.LookVector end
    if moveState.back then dir = dir - workspace.CurrentCamera.CFrame.LookVector end
    if moveState.left then dir = dir - workspace.CurrentCamera.CFrame.RightVector end
    if moveState.right then dir = dir + workspace.CurrentCamera.CFrame.RightVector end
    if moveState.up then dir = dir + Vector3.new(0, 1, 0) end
    if moveState.down then dir = dir - Vector3.new(0, 1, 0) end

    if dir.Magnitude > 0 then
        flyBodyVel.Velocity = dir.Unit * flySpeed
    else
        flyBodyVel.Velocity = Vector3.zero
    end

    flyBodyGyro.CFrame = workspace.CurrentCamera.CFrame
end

local function setupKeyboardControls()
    local function onInputBegan(input, gameProcessed)
        if gameProcessed or not flyEnabled then return end
        local key = input.KeyCode
        if key == Enum.KeyCode.W or key == Enum.KeyCode.Z then moveState.forward = true
        elseif key == Enum.KeyCode.S then moveState.back = true
        elseif key == Enum.KeyCode.A or key == Enum.KeyCode.Q then moveState.left = true
        elseif key == Enum.KeyCode.D then moveState.right = true
        elseif key == Enum.KeyCode.Space then moveState.up = true
        elseif key == Enum.KeyCode.LeftControl then moveState.down = true
        end
    end

    local function onInputEnded(input, gameProcessed)
        if gameProcessed or not flyEnabled then return end
        local key = input.KeyCode
        if key == Enum.KeyCode.W or key == Enum.KeyCode.Z then moveState.forward = false
        elseif key == Enum.KeyCode.S then moveState.back = false
        elseif key == Enum.KeyCode.A or key == Enum.KeyCode.Q then moveState.left = false
        elseif key == Enum.KeyCode.D then moveState.right = false
        elseif key == Enum.KeyCode.Space then moveState.up = false
        elseif key == Enum.KeyCode.LeftControl then moveState.down = false
        end
    end

    UserInputService.InputBegan:Connect(onInputBegan)
    UserInputService.InputEnded:Connect(onInputEnded)
end

local function startFly()
    if flyEnabled then return end
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not humanoid then return end

    setNoclip(true)

    flyBodyVel = Instance.new("BodyVelocity")
    flyBodyVel.Velocity = Vector3.zero
    flyBodyVel.MaxForce = Vector3.new(1, 1, 1) * math.huge
    flyBodyVel.Parent = hrp

    flyBodyGyro = Instance.new("BodyGyro")
    flyBodyGyro.MaxTorque = Vector3.new(1, 1, 1) * math.huge
    flyBodyGyro.P = 1e4
    flyBodyGyro.D = 100
    flyBodyGyro.CFrame = hrp.CFrame
    flyBodyGyro.Parent = hrp

    humanoid.PlatformStand = true
    flyEnabled = true

    flyConnection = RunService.Heartbeat:Connect(updateFlyMovement)
end

local function stopFly()
    if not flyEnabled then return end
    flyEnabled = false

    if flyConnection then flyConnection:Disconnect(); flyConnection = nil end
    if flyBodyVel then flyBodyVel:Destroy(); flyBodyVel = nil end
    if flyBodyGyro then flyBodyGyro:Destroy(); flyBodyGyro = nil end

    local char = LocalPlayer.Character
    if char then
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid.PlatformStand = false end
        setNoclip(false)
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.Velocity = Vector3.zero end
    end

    for k in pairs(moveState) do moveState[k] = false end
end

local function toggleFly(state)
    if state then
        if not flyEnabled then startFly() end
    else
        if flyEnabled then stopFly() end
    end
end

local savedPosition = nil

local function teleportToSavedPosition()
    if not savedPosition then
        WindUI:Notify({ Title = "TP Save", Desc = "Aucune position sauvegardée", Icon = "alert", Time = 2 })
        return
    end
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then
        pcall(function()
            hrp.CFrame = CFrame.new(savedPosition + Vector3.new(0, 2.5, 0))
            WindUI:Notify({ Title = "TP Save", Desc = "Téléporté à la position sauvegardée", Icon = "map-pin", Time = 2 })
        end)
    end
end

local function saveCurrentPosition()
    local char = LocalPlayer.Character
    if not char then
        WindUI:Notify({ Title = "TP Save", Desc = "Personnage introuvable", Icon = "alert", Time = 2 })
        return
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then
        savedPosition = hrp.Position
        local posStr = string.format("(%.1f, %.1f, %.1f)", savedPosition.X, savedPosition.Y, savedPosition.Z)
        WindUI:Notify({ Title = "TP Save", Desc = "Position sauvegardée : " .. posStr, Icon = "save", Time = 3 })
    else
        WindUI:Notify({ Title = "TP Save", Desc = "HumanoidRootPart introuvable", Icon = "alert", Time = 2 })
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.O then
        teleportToSavedPosition()
    end
end)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MobileControls"
screenGui.ResetOnSpawn = false
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local function createButton(text, position, size, color, callback)
    local btn = Instance.new("TextButton")
    btn.Size = size
    btn.Position = position
    btn.Text = text
    btn.TextColor3 = Color3.new(1,1,1)
    btn.TextScaled = true
    btn.BackgroundColor3 = color
    btn.BorderSize = 0
    btn.Font = Enum.Font.GothamBold
    btn.Parent = screenGui

    btn.MouseButton1Down:Connect(function()
        btn.BackgroundColor3 = color * 0.7
        task.wait(0.1)
        btn.BackgroundColor3 = color
    end)

    btn.MouseButton1Click:Connect(callback)
    return btn
end

local mainPanel = Instance.new("Frame")
mainPanel.Size = UDim2.new(0, 180, 0, 200)
mainPanel.Position = UDim2.new(0.8, -90, 0.5, -100)
mainPanel.BackgroundColor3 = Color3.fromRGB(30,30,40)
mainPanel.BackgroundTransparency = 0.2
mainPanel.BorderSize = 0
mainPanel.Parent = screenGui

local dragging = false
local dragStart = nil
local panelStart = nil

mainPanel.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        panelStart = mainPanel.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.Touch then
        local delta = input.Position - dragStart
        mainPanel.Position = UDim2.new(panelStart.X.Scale, panelStart.X.Offset + delta.X, panelStart.Y.Scale, panelStart.Y.Offset + delta.Y)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

local flyButton = createButton("🕊️ Fly", UDim2.new(0, 10, 0, 10), UDim2.new(0, 160, 0, 40), Color3.fromRGB(0,150,200), function()
    local newState = not flyEnabled
    toggleFly(newState)
    flyButton.Text = newState and "🕊️ Fly: ON" or "🕊️ Fly: OFF"
    flyButton.BackgroundColor3 = newState and Color3.fromRGB(0,200,0) or Color3.fromRGB(0,150,200)
    directionPanel.Visible = newState
end)
flyButton.Parent = mainPanel

local tpButton = createButton("📍 TP", UDim2.new(0, 10, 0, 60), UDim2.new(0, 160, 0, 40), Color3.fromRGB(200,100,0), function()
    teleportToSavedPosition()
end)
tpButton.Parent = mainPanel

local saveButton = createButton("💾 Save", UDim2.new(0, 10, 0, 110), UDim2.new(0, 160, 0, 40), Color3.fromRGB(100,100,200), function()
    saveCurrentPosition()
end)
saveButton.Parent = mainPanel

local directionPanel = Instance.new("Frame")
directionPanel.Size = UDim2.new(0, 220, 0, 150)
directionPanel.Position = UDim2.new(0, 10, 1, -160)
directionPanel.BackgroundColor3 = Color3.fromRGB(0,0,0)
directionPanel.BackgroundTransparency = 0.5
directionPanel.BorderSize = 0
directionPanel.Visible = false
directionPanel.Parent = screenGui

local function createDirButton(text, pos, size, moveKey)
    local btn = Instance.new("TextButton")
    btn.Size = size
    btn.Position = pos
    btn.Text = text
    btn.TextColor3 = Color3.new(1,1,1)
    btn.TextScaled = true
    btn.BackgroundColor3 = Color3.fromRGB(80,80,120)
    btn.BorderSize = 0
    btn.Font = Enum.Font.GothamBold
    btn.Parent = directionPanel

    local function onTouchStart(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            moveState[moveKey] = true
            btn.BackgroundColor3 = Color3.fromRGB(150,150,200)
        end
    end

    local function onTouchEnd(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            moveState[moveKey] = false
            btn.BackgroundColor3 = Color3.fromRGB(80,80,120)
        end
    end

    btn.InputBegan:Connect(onTouchStart)
    btn.InputEnded:Connect(onTouchEnd)

    btn.MouseButton1Down:Connect(function()
        moveState[moveKey] = true
        btn.BackgroundColor3 = Color3.fromRGB(150,150,200)
    end)
    btn.MouseButton1Up:Connect(function()
        moveState[moveKey] = false
        btn.BackgroundColor3 = Color3.fromRGB(80,80,120)
    end)
end

createDirButton("▲", UDim2.new(0, 85, 0, 10), UDim2.new(0, 50, 0, 40), "forward")
createDirButton("▼", UDim2.new(0, 85, 0, 100), UDim2.new(0, 50, 0, 40), "back")
createDirButton("◀", UDim2.new(0, 10, 0, 55), UDim2.new(0, 50, 0, 40), "left")
createDirButton("▶", UDim2.new(0, 160, 0, 55), UDim2.new(0, 50, 0, 40), "right")
createDirButton("↑", UDim2.new(0, 35, 0, 55), UDim2.new(0, 40, 0, 40), "up")
createDirButton("↓", UDim2.new(0, 145, 0, 55), UDim2.new(0, 40, 0, 40), "down")

setupKeyboardControls()

local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
WindUI:AddTheme({
    Name = "Dark", Accent = Color3.fromHex("#1e1e2e"), Background = Color3.fromHex("#101010"),
    Outline = Color3.fromHex("#2a2a3d"), Text = Color3.fromHex("#e0e0f0"), Placeholder = Color3.fromHex("#5a5a7a"),
    Button = Color3.fromHex("#2a2a3d"), Icon = Color3.fromHex("#7a7aaa"),
})
WindUI:SetTheme("Dark")

local Window = WindUI:CreateWindow({
    Title = "Multi Tool", Icon = "zap", Author = "Tool", Folder = "MultiTool",
    Theme = "Dark", ToggleKey = Enum.KeyCode.RightShift, Transparent = true,
})

local FlyTab = Window:Tab({ Title = "Fly", Icon = "wind" })
local flyToggle = FlyTab:Toggle({
    Title = "Vol (Style IY)", Desc = "Déplacement WASD + Espace/Ctrl, noclip (sans Q/E)", Icon = "wind", Value = false,
    Callback = function(state)
        toggleFly(state)
        flyToggle:SetTitle(state and "Fly : ON" or "Fly : OFF")
        flyButton.Text = state and "🕊️ Fly: ON" or "🕊️ Fly: OFF"
        flyButton.BackgroundColor3 = state and Color3.fromRGB(0,200,0) or Color3.fromRGB(0,150,200)
        directionPanel.Visible = state
    end
})
FlyTab:Slider({
    Title = "Vitesse de vol", Icon = "zap", Step = 5,
    Value = { Min = 10, Max = 300, Default = CFG.FlySpeed },
    Callback = function(value)
        flySpeed = value
        CFG.FlySpeed = value
    end
})

local SettingsTab = Window:Tab({ Title = "Paramètres", Icon = "settings" })
SettingsTab:Toggle({
    Title = "Instant Prompt", Desc = "HoldDuration = 0", Icon = "timer", Value = CFG.InstantPrompt,
    Callback = function(state)
        CFG.InstantPrompt = state
        if state then
            for p in pairs(promptRegistry) do
                if p and p.Parent then p.HoldDuration = 0 end
            end
        else
            for p, dur in pairs(originalDurations) do
                if p and p.Parent then p.HoldDuration = dur end
            end
        end
    end
})
SettingsTab:Toggle({
    Title = "Auto Activation", Desc = "Déclenche automatiquement les prompts à l'écran", Icon = "mouse-pointer", Value = CFG.AutoPrompt,
    Callback = function(state) CFG.AutoPrompt = state end
})
SettingsTab:Slider({
    Title = "WalkSpeed", Desc = "Vitesse de marche", Icon = "footprints", Step = 2,
    Value = { Min = 2, Max = 500, Default = CFG.WalkSpeed },
    Callback = function(value) CFG.WalkSpeed = value; enforceWalkSpeed(getHumanoid()) end
})
SettingsTab:Toggle({
    Title = "TP Tool", Desc = "Outil de téléportation par clic", Icon = "map-pin", Value = CFG.TpTool,
    Callback = function(state) CFG.TpTool = state; updateTpTool() end
})

local MidasTab = Window:Tab({ Title = "Midas", Icon = "package" })
local midasToggle = MidasTab:Toggle({
    Title = "Auto Pick Midas", Desc = "Téléportation aux SeedPacks", Icon = "target", Value = CFG.AutoPickMidas,
    Callback = function(state) setMidasActive(state); midasToggle:SetTitle(state and "Auto Pick Midas : ON" or "Auto Pick Midas : OFF") end
})
local function showMidasStatus()
    local locs = refreshMidasLocations()
    local msg = string.format("Statut: %s\nCible: %s\nIndex: %d/%d\nInfo: %s",
        midas.active and "ACTIF" or "INACTIF", midas.currentTarget and midas.currentTarget.Name or "aucune",
        midas.currentIndex, #locs, midas.statusText)
    WindUI:Notify({ Title = "Statut Midas", Desc = msg, Icon = "info", Time = 5 })
end
MidasTab:Button({ Title = "Afficher le statut", Icon = "eye", Callback = showMidasStatus })
MidasTab:Button({ Title = "Forcer passage au suivant", Icon = "skip-forward",
    Callback = function() if not midas.active then return end; local next = nextMidasTarget(); if next then teleportToTarget(next) end end })
MidasTab:Button({ Title = "Rafraîchir les emplacements", Icon = "refresh-cw",
    Callback = function() midas.locations = refreshMidasLocations(); showMidasStatus() end })

local StockTab = Window:Tab({ Title = "Stock", Icon = "shopping-cart" })
StockTab:Button({ Title = "📤 Envoyer le stock sur Discord", Icon = "send",
    Callback = function() checkAndSendStock(); WindUI:Notify({ Title = "Stock", Desc = "Envoi effectué", Icon = "check", Time = 2 }) end })

local TpSaveTab = Window:Tab({ Title = "TP Save", Icon = "bookmark" })
TpSaveTab:Button({ Title = "📌 Sauvegarder la position actuelle", Icon = "save", Callback = saveCurrentPosition })
TpSaveTab:Button({ Title = "🚀 Se téléporter à la position sauvegardée", Icon = "send", Callback = teleportToSavedPosition })
TpSaveTab:Button({ Title = "⌨️ Info : Appuyez sur la touche O pour TP instantané", Icon = "keyboard", Callback = function() end })

WindUI:Notify({ Title = "Multi Tool", Desc = "Version mobile : boutons tactiles ajoutés (fly, TP, directions)", Icon = "check", Time = 5 })
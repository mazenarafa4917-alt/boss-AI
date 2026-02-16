-- Get references to the NPC/rig and its main components
local rig = script.Parent
local humanoid = rig:WaitForChild("Humanoid") -- Main humanoid component
local hrp = rig:WaitForChild("HumanoidRootPart") -- Center position of the rig

-- Services used for various functionalities
local playerService = game:GetService("Players") -- To track players
local pathfindingService = game:GetService("PathfindingService") -- For moving NPC around obstacles
local debris = game:GetService("Debris") -- Auto cleanup objects like BodyVelocity
local tweenService = game:GetService("TweenService") -- Smooth animations and movements
local serverstorage = game:GetService("ServerStorage") -- Storage for reusable parts
local shockwave = workspace:WaitForChild("shockwave") -- Shockwave sound/effect
local freezeSound = workspace:WaitForChild("freeze") -- Freeze sound effect

-- Set up NPC stats
humanoid.MaxHealth = 1000
humanoid.Health = 1000
humanoid.WalkSpeed = 19

-- Constants for NPC behavior
local DETECTION_RANGE = 100 -- How far the NPC can "see" players
local ABILITY_RANGE = 20 -- Range to use abilities
local THINK_INTERVAL = 1.5 -- How often NPC reevaluates its targets
local debouce = false -- General debounce flag (not used much here)

-- Track ability cooldowns
local cooldowns = {
	ability1 = 0,
	ability2 = 0,
	ability3 = 0,
	pull = 0,
	ability4 = 0
}

-- How long each ability's cooldown lasts
local abilityTimers = {
	ability1 = 5,
	ability2 = 8,
	ability3 = 6,
	pull = 5,
	ability4 = 10
}

-- Check if an ability can be used
local function canUse(name)
	return tick() - cooldowns[name] >= abilityTimers[name]
end

-- Set the cooldown timestamp for an ability
local function setCooldown(name)
	cooldowns[name] = tick()
end

-- Debounce for touching damage
local touchDebounce = false

-- Damage function when NPC body parts touch a player
local function damage(hit)
	if touchDebounce then return end

	local character = hit:FindFirstAncestorOfClass("Model")
	if not character or character == rig then return end

	local hum = character:FindFirstChildWhichIsA("Humanoid")
	if hum then
		hum:TakeDamage(10) -- Deal 10 damage
		touchDebounce = true
		-- Reset debounce after 0.5 seconds
		task.delay(0.5, function()
			touchDebounce = false
		end)
	end
end

-- Connect the damage function to various NPC body parts
for _, part in pairs({rig.LeftFoot, rig.RightFoot, rig.LeftHand, rig.RightHand, rig.UpperTorso, rig.Head}) do
	part.Touched:Connect(damage)
end

-- Knockback function to push players away
local function knockback(targetHRP, magnitude)
	local bodyVel = Instance.new("BodyVelocity")
	bodyVel.Velocity = (targetHRP.Position - hrp.Position).Unit * magnitude -- Direction & force
	bodyVel.MaxForce = Vector3.new(400000,400000,400000) -- Allow movement in all directions
	bodyVel.P = 1250 -- Power of force
	bodyVel.Parent = targetHRP
	debris:AddItem(bodyVel, 0.3) -- Auto remove after 0.3s
end

-- Pull a player towards the NPC
local function pullPlayer(player)
	if not canUse("pull") then return end
	setCooldown("pull")

	local playerHRP = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not playerHRP then return end

	local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local goal = {CFrame = CFrame.new(hrp.Position + hrp.CFrame.LookVector * 3)} -- 3 studs in front
	local tween = tweenService:Create(playerHRP, tweenInfo, goal)
	tween:Play()
end

-- Ability 1: Shockwave knockback + damage
local function ability1(targetHRP)
	if not canUse("ability1") then return end
	setCooldown("ability1")

	local targetHumanoid = targetHRP.Parent:FindFirstChild("Humanoid")
	if not targetHumanoid then return end

	shockwave:Play()
	knockback(targetHRP, 50) -- Moderate knockback
	targetHumanoid:TakeDamage(30)
end

-- Ability 2: Freeze player temporarily
local function ability2(targetHRP)
	if not canUse("ability2") then return end
	setCooldown("ability2")

	local targetHumanoid = targetHRP.Parent:FindFirstChild("Humanoid")
	if not targetHumanoid then return end

	local originalSpeed = targetHumanoid.WalkSpeed

	freezeSound:Play()
	targetHumanoid.WalkSpeed = 0 -- Freeze movement
	targetHumanoid:TakeDamage(10)

	-- Unfreeze after 3 seconds
	task.delay(3, function()
		if targetHumanoid then
			targetHumanoid.WalkSpeed = originalSpeed
		end
	end)
end

-- Ability 3: Heavy knockback then pull back
local function ability3(targetHRP)
	if not canUse("ability3") then return end
	setCooldown("ability3")

	local targetHumanoid = targetHRP.Parent:FindFirstChild("Humanoid")
	local player = playerService:GetPlayerFromCharacter(targetHRP.Parent)
	if not targetHumanoid or not player then return end

	knockback(targetHRP, 250) -- Strong knockback

	-- Pull back after 1 second
	task.delay(1, function()
		pullPlayer(player)
	end)
end

-- Ability 4: Projectile attack with temporary NPC freeze
local function ability4(targetHRP)
	if not canUse("ability4") then return end
	setCooldown("ability4")

	if not targetHRP or not targetHRP.Parent then return end
	local targetHumanoid = targetHRP.Parent:FindFirstChild("Humanoid")
	if not targetHumanoid then return end

	task.spawn(function()
		humanoid.WalkSpeed = 0 -- Freeze NPC while attacking

		local part = serverstorage:FindFirstChild("Part")
		if part then
			local partClone = part:Clone()
			partClone.CFrame = hrp.CFrame
			partClone.Parent = workspace

			local origin = hrp.Position
			local targetPos = targetHRP.Position
			local direction = (targetPos - origin).Unit
			local range = 50 

			local goal = {CFrame = CFrame.new(origin + direction * range)}
			local tweenInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local tween = tweenService:Create(partClone, tweenInfo, goal)
			tween:Play()

			-- Reset NPC speed and clean projectile
			tween.Completed:Connect(function()
				humanoid.WalkSpeed = 19
				partClone:Destroy()
			end)
		else
			humanoid.WalkSpeed = 19
		end
	end)
end

-- Function to move NPC towards a target using pathfinding
local function moveToTarget(targetHRP)
	if not targetHRP then return end

	local targetPos = targetHRP.Position
	local ray = Ray.new(hrp.Position, (targetPos - hrp.Position).Unit * 100)
	local hit = workspace:FindPartOnRayWithIgnoreList(ray, {rig, targetHRP.Parent})

	if not hit then
		humanoid:MoveTo(targetPos)
		return
	end

	-- Use pathfinding to navigate around obstacles
	local path = pathfindingService:CreatePath()
	path:ComputeAsync(hrp.Position, targetPos)

	if path.Status == Enum.PathStatus.Success then
		for _, waypoint in ipairs(path:GetWaypoints()) do
			humanoid:MoveTo(waypoint.Position)
			task.wait(0.05)
		end
	end
end

-- Main AI loop
task.spawn(function()
	while humanoid.Health > 0 do
		local closestPlayer
		local closestDist = DETECTION_RANGE

		-- Find the closest player
		for _, player in ipairs(playerService:GetPlayers()) do
			local character = player.Character
			local targetHRP = character and character:FindFirstChild("HumanoidRootPart")

			if targetHRP then
				local dist = (targetHRP.Position - hrp.Position).Magnitude
				if dist < closestDist then
					closestDist = dist
					closestPlayer = player
				end
			end
		end

		if closestPlayer and closestPlayer.Character then
			local targetHRP = closestPlayer.Character:FindFirstChild("HumanoidRootPart")
			local player = game.Players:GetPlayerFromCharacter(closestPlayer.Character)
			if targetHRP and player then
				local distance = (targetHRP.Position - hrp.Position).Magnitude -- Calculate distance

				-- Move closer if too far
				if distance > 15 then
					moveToTarget(targetHRP)
				end

				-- Use abilities if in range
				if distance <= ABILITY_RANGE then
					local roll = math.random(1,100)

					if roll <= 30 then
						ability1(targetHRP)
					elseif roll <= 55 then
						ability2(targetHRP)
					elseif roll <= 80 then
						ability3(targetHRP)
					elseif roll <= 90 then
						ability4(targetHRP)
					end
				else
					ability4(targetHRP) -- Fallback ability
				end
			end
		end
		task.wait(THINK_INTERVAL) -- Wait before next AI decision
	end
end)

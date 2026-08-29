local PathfindingService = game:GetService("PathfindingService")

-- === PATHFINDING & RAYTRACING NAVIGATION ===
local function gotoPosition(targetPosition)
    stopFollowing() -- Stop active player following tasks to prevent conflict

    local myChar = LocalPlayer.Character
    if not myChar then return end

    local humanoid = myChar:FindFirstChildOfClass("Humanoid")
    local myHRP = myChar:FindFirstChild("HumanoidRootPart")
    if not humanoid or not myHRP then return end

    -- 1. Direct Raycast Check (If clear line-of-sight, walk directly)
    local rayOrigin = myHRP.Position
    local rayDirection = targetPosition - rayOrigin
    local raycastParams = RaycastParams.new()
    raycastParams.FilterAncestors = {myChar}
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude

    local directHit = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

    -- If no solid obstacle is blocking the direct path, walk directly
    if not directHit or (directHit.Position - targetPosition).Magnitude < 3 then
        humanoid:MoveTo(targetPosition)
        return
    end

    -- 2. Compute Pathfinding Route (If blocked by walls/objects)
    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        WaypointSpacing = 4
    })

    local success, _ = pcall(function()
        path:ComputeAsync(myHRP.Position, targetPosition)
    end)

    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()

        task.spawn(function()
            for _, waypoint in ipairs(waypoints) do
                -- Trigger jump for elevated waypoints
                if waypoint.Action == Enum.PathWaypointAction.Jump then
                    humanoid.Jump = true
                end

                humanoid:MoveTo(waypoint.Position)

                -- Continuous Raycast check during movement to detect dynamic obstacles
                local moveFinished = false
                local conn = humanoid.MoveToFinished:Connect(function()
                    moveFinished = true
                end)

                local startTime = tick()
                while not moveFinished and (tick() - startTime) < 5 do
                    -- Raycast ahead toward next waypoint
                    local currentRayDir = waypoint.Position - myHRP.Position
                    local pathHit = workspace:Raycast(myHRP.Position, currentRayDir, raycastParams)

                    -- Recalculate path if path becomes suddenly blocked
                    if pathHit and pathHit.Instance and pathHit.Instance.CanCollide and pathHit.Distance < 3 then
                        conn:Disconnect()
                        gotoPosition(targetPosition) -- Recalculate
                        return
                    end
                    task.wait(0.1)
                end
                conn:Disconnect()
            end
        end)
    else
        -- Fallback direct movement if path calculation fails
        humanoid:MoveTo(targetPosition)
    end
end

require "/scripts/util.lua"
require "/scripts/interp.lua"

-- Base gun fire ability
GunFire = WeaponAbility:new()
swiftIndex = 1

b = false
-- swiftOffset = {0, 6}



function GunFire:init()
  self.weapon:setStance(self.stances.idle)

  self.cooldownTimer = self.fireTime

  self.weapon.onLeaveAbility = function()
    self.weapon:setStance(self.stances.idle)
  end
end

function GunFire:update(dt, fireMode, shiftHeld)
  WeaponAbility.update(self, dt, fireMode, shiftHeld)

  self.cooldownTimer = math.max(0, self.cooldownTimer - self.dt)

  if animator.animationState("firing") ~= "fire" then
    animator.setLightActive("muzzleFlash", false)
  end

  if self.fireMode == (self.activatingFireMode or self.abilitySlot)
    and not self.weapon.currentAbility
    and self.cooldownTimer == 0
    and not status.resourceLocked("energy")
    and not world.lineTileCollision(mcontroller.position(), self:firePosition()) then

    if self.fireType == "auto" and status.overConsumeResource("energy", self:energyPerShot()) then
      self:setState(self.auto)
	  b = false
    elseif self.fireType == "burst" then
      self:setState(self.burst)
	  b = false
    end
  end
end

function GunFire:auto()
  self.weapon:setStance(self.stances.fire)

  self:fireProjectile()
  self:muzzleFlash()

  if self.stances.fire.duration then
    util.wait(self.stances.fire.duration)
  end

  self.cooldownTimer = self.fireTime
  self:setState(self.cooldown)
end

function GunFire:burst()
  self.weapon:setStance(self.stances.fire)

  local shots = self.burstCount
  while shots > 0 and status.overConsumeResource("energy", self:energyPerShot()) do
    self:fireProjectile()
    self:muzzleFlash()
    shots = shots - 1

    self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(1 - shots / self.burstCount, 0, self.stances.fire.weaponRotation))
    self.weapon.relativeArmRotation = util.toRadians(interp.linear(1 - shots / self.burstCount, 0, self.stances.fire.armRotation))

    util.wait(self.burstTime)
  end

  self.cooldownTimer = (self.fireTime - self.burstTime) * self.burstCount
end

function GunFire:cooldown()
	self.weapon:setStance(self.stances.cooldown)
	self.weapon:updateAim()

	local progress = 0
	util.wait(self.stances.cooldown.duration, function()
		local from = self.stances.cooldown.weaponOffset or {0,0}
		local to = self.stances.idle.weaponOffset or {0,0}
		self.weapon.weaponOffset = {interp.linear(progress, from[1], to[1]), interp.linear(progress, from[2], to[2])}

		self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(progress, self.stances.cooldown.weaponRotation, self.stances.idle.weaponRotation))
		self.weapon.relativeArmRotation = util.toRadians(interp.linear(progress, self.stances.cooldown.armRotation, self.stances.idle.armRotation))

		progress = math.min(1.0, progress + (self.dt / self.stances.cooldown.duration))
	end)
end

function GunFire:muzzleFlash()
	animator.setPartTag("muzzleFlash", "variant", math.random(1, self.muzzleFlashVariants or 3))
	animator.setAnimationState("firing", "fire")
	animator.burstParticleEmitter("muzzleFlash")
	animator.playSound("fire")

	animator.setLightActive("muzzleFlash", true)
  
end

function GunFire:fireProjectile(projectileType, projectileParams, inaccuracy, firePosition, projectileCount)
	local params = sb.jsonMerge(self.projectileParameters, projectileParams or {})
	params.power = self:damagePerShot()
	params.powerMultiplier = activeItem.ownerPowerMultiplier()
	params.speed = util.randomInRange(params.speed)

	if not projectileType then
		projectileType = self.projectileType
	end
	if type(projectileType) == "table" then
		projectileType = projectileType[math.random(#projectileType)]
	end

	local projectileId = 0
	for i = 1, (projectileCount or self.projectileCount) do
		if params.timeToLive then
			params.timeToLive = util.randomInRange(params.timeToLive)
		end
		projectileId = world.spawnProjectile(
			projectileType,
			firePosition or self:firePosition(),
			activeItem.ownerEntityId(),
			self:aimVector(inaccuracy or self.inaccuracy),
			false,
			params
		)
		swiftIndex = swiftIndex + 1
		if swiftIndex == 6 then 
			swiftIndex = 1
		end
	end
	return projectileId
end

function GunFire:firePosition()
	n = {0, 0}
	
	if swiftIndex == 1 then
		n[1] = self.weapon.muzzleOffset[1] + (0 * 0.5)
		n[2] = self.weapon.muzzleOffset[2] + (1 * 0.5)
	end
	if swiftIndex == 2 then
		n[1] = self.weapon.muzzleOffset[1] + (1 * 0.5)
		n[2] = self.weapon.muzzleOffset[2] + (0 * 0.5)
	end
	if swiftIndex == 3 then
		n[1] = self.weapon.muzzleOffset[1] + (0.5 * 0.5)
		n[2] = self.weapon.muzzleOffset[2] - (1 * 0.5)
	end
	if swiftIndex == 4 then
		n[1] = self.weapon.muzzleOffset[1] - (0.5 * 0.5)
		n[2] = self.weapon.muzzleOffset[2] - (1 * 0.5)
	end
	if swiftIndex == 5 then
		n[1] = self.weapon.muzzleOffset[1] - (1 * 0.5)
		n[2] = self.weapon.muzzleOffset[2] + (0 * 0.5)
	end
	
	
	
	return vec2.add(mcontroller.position(), activeItem.handPosition(n))
end

function GunFire:aimVector(inaccuracy)
	local aimVector = vec2.rotate({1, 0}, self.weapon.aimAngle + sb.nrand(inaccuracy, 0))
	aimVector[1] = aimVector[1] * mcontroller.facingDirection()
	return aimVector
end

function GunFire:energyPerShot()
	return self.energyUsage * self.fireTime * (self.energyUsageMultiplier or 1.0)
end

function GunFire:damagePerShot()
	return (self.baseDamage or (self.baseDps * self.fireTime)) * (self.baseDamageMultiplier or 1.0) * config.getParameter("damageLevelMultiplier") / self.projectileCount
end

function GunFire:uninit()
end

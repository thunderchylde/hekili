-- Targets.lua
-- June 2014


local addon, ns = ...
local Hekili = _G[ addon ]

local class = ns.class

local targetCount = 0
local targets = {}

local myTargetCount = 0
local myTargets = {}

local RC = ns.lib.RangeCheck

local nameplates = {}
local npCount = 0
local addMissingTargets = false

-- New Nameplate Proximity System
function ns.getNameplateTargets()
    if GetCVar( 'nameplateShowEnemies' ) ~= "1" then
        return -1
    end

    for k,v in pairs( nameplates ) do
        nameplates[k] = nil
    end

    npCount = 0

    for i = 1, 80 do
        local unit = 'nameplate'..i

        local _, maxRange = RC:GetRange( unit )

        if maxRange and maxRange <= ( class.range or 5 ) and UnitExists( unit ) and ( not UnitIsDead( unit ) ) and UnitCanAttack( 'player', unit ) and ( UnitIsPVP( 'player' ) or not UnitIsPlayer( unit ) ) then
            nameplates[ UnitGUID( unit ) ] = maxRange
            npCount = npCount + 1
        end
    end

    if addMissingTargets then
        for k,v in pairs( myTargets ) do
            if not nameplates[ k ] then
                nameplates[ k ] = true
                npCount = npCount + 1
            end
        end
    end

    return npCount
end


function ns.dumpNameplateInfo()
    return nameplates
end


ns.updateTarget = function( id, time, mine )

  if time then
    if not targets[ id ] then
      targetCount = targetCount + 1
      targets[id] = time
    else
      targets[id] = time
    end

    if mine then
      if not myTargets[ id ] then
        myTargetCount = myTargetCount + 1
        myTargets[id] = time
      else
        myTargets[id] = time
      end
    end

  else
    if targets[id] then
      targetCount = max(0, targetCount - 1)
      targets[id] = nil
    end

    if myTargets[id] then
      myTargetCount = max(0, myTargetCount - 1)
      myTargets[id] = nil
    end
  end
end


ns.reportTargets = function()
  for k, v in pairs( targets ) do
    Hekili:Print( "Saw " .. k .. " exactly " .. GetTime() - v .. " seconds ago." )
  end
end


ns.numTargets = function() return targetCount > 0 and targetCount or 1 end
ns.numMyTargets = function() return myTargetCount > 0 and myTargetCount or 1 end
ns.isTarget = function( id ) return targets[ id ] ~= nil end
ns.isMyTarget = function( id ) return myTargets[ id ] ~= nil end


-- MINIONS
local minions = {}

ns.updateMinion = function( id, time )
  minions[ id ] = time
end

ns.isMinion = function( id ) return minions[ id ] ~= nil end


local debuffs = {}
local debuffCount = {}


ns.wipeDebuffs = function()
  for k, _ in pairs( debuffs ) do
    table.wipe( debuffs[k] )
    debuffCount[k] = 0
  end
end


ns.trackDebuff = function( spell, target, time )

  debuffs[ spell ] = debuffs[ spell ] or {}
  debuffCount[ spell ] = debuffCount[ spell ] or 0

  if not time then
    if debuffs[ spell ][ target ] then
      -- Remove it.
      debuffs[ spell ][ target ]	= nil
      debuffCount[ spell ] = max(0, debuffCount[ spell ] - 1)
    end

  else
    if not debuffs[ spell ][ target ] then
      debuffs[ spell ][ target ]	= {}
      debuffCount[ spell ] = debuffCount[ spell ] + 1
    end

    local debuff = debuffs[ spell ][ target ]
    debuff.last_seen = time

    if new then debuff.applied = time end

  end

end


ns.numDebuffs = function( spell ) return debuffCount[ spell ] or 0 end
ns.isWatchedDebuff = function( spell ) return debuffs[ spell ] ~= nil end


ns.eliminateUnit = function( id )
  ns.updateMinion( id )
  ns.updateTarget( id )

  ns.TTD[ id ] = nil

  for k,v in pairs( debuffs ) do
    ns.trackDebuff( k, id )
  end
end


local incomingDamage = {}
local incomingHealing = {}

ns.storeDamage = function( time, damage, damageType ) table.insert( incomingDamage, { t = time, damage = damage, damageType = damageType } ) end
ns.storeHealing = function( time, healing ) table.insert( incomingHealing, { t = time, healing = healing } ) end


ns.damageInLast = function( t )

  local dmg = 0
  local start = GetTime() - min( t, 15 )

  for k, v in pairs( incomingDamage ) do

    if v.t > start then
      dmg = dmg + v.damage
    end

  end

  return dmg

end


function ns.healingInLast( t )
    local heal = 0
    local start = GetTime() - min( t, 15 )

    for k, v in pairs( incomingHealing ) do
        if v.t > start then
            heal = heal + v.healing
        end
    end

    return heal
end


-- Auditor should clean things up for us.
ns.Audit = function ()

  local now = GetTime()
  local grace = Hekili.DB.profile['Audit Targets']

  for aura, targets in pairs( debuffs ) do
    for unit, aura in pairs( targets ) do
      -- NYI: Check for dot vs. debuff, since debuffs won't 'tick'
      if now - aura.last_seen > grace then
        ns.trackDebuff( aura, unit )
      end
    end
  end

  for whom, when in pairs( targets ) do
    if now - when > grace then
      ns.eliminateUnit( whom )
    end
  end

  for i = #incomingDamage, 1, -1 do
    local instance = incomingDamage[ i ]

    if instance.t < ( now - 15 ) then
      table.remove( incomingDamage, i )
    end
  end

  for i = #incomingHealing, 1, -1 do
    local instance = incomingHealing[ i ]

    if instance.t < ( now - 15 ) then
        table.remove( incomingHealing, i )
    end
  end

  if Hekili.DB.profile.Enabled then
    C_Timer.After( 1, ns.Audit )
  end

end


local TTD = ns.TTD

-- Borrowed TTD linear regression model from 'Nemo' by soulwhip (with permission).
ns.initTTD = function( unit )

  if not unit then return end

  local GUID = UnitGUID( unit )

  TTD[ GUID ] = TTD[ GUID ] or {}
  TTD[ GUID ].n = 1
  TTD[ GUID ].timeSum = GetTime()
  TTD[ GUID ].healthSum = UnitHealth( unit ) or 0
  TTD[ GUID ].timeMean = TTD[ GUID ].timeSum * TTD[ GUID ].timeSum
  TTD[ GUID ].healthMean = TTD[ GUID ].timeSum * TTD[ GUID ].healthSum
  TTD[ GUID ].name = UnitName( unit )
  TTD[ GUID ].sec = 300

end


ns.getTTD = function( unit )

  local GUID = UnitGUID( unit )

  if not TTD[ GUID ] then return 300 end

  return TTD[ GUID ].sec or 300

end
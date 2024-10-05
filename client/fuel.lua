local config = require 'config'
local state = require 'client.state'
local utils = require 'client.utils'
local fuel = {}

---@param vehState StateBag
---@param vehicle integer
---@param amount number
---@param replicate? boolean
function fuel.setFuel(vehState, vehicle, amount, replicate)
	if DoesEntityExist(vehicle) then
		amount = math.clamp(amount, 0, 100)

		SetVehicleFuelLevel(vehicle, amount)
		vehState:set('fuel', amount, replicate)
	end
end

function fuel.getPetrolCan(coords, refuel)
	TaskTurnPedToFaceCoord(cache.ped, coords.x, coords.y, coords.z, config.petrolCan.duration)
	Wait(500)

	if lib.progressCircle({
			duration = config.petrolCan.duration,
			useWhileDead = false,
			canCancel = true,
			disable = {
				move = true,
				car = true,
				combat = true,
			},
			anim = {
				dict = 'timetable@gardener@filling_can',
				clip = 'gar_ig_5_filling_can',
				flags = 49,
			}
		}) then
		if refuel and exports.ox_inventory:GetItemCount('WEAPON_PETROLCAN') then
			return TriggerServerEvent('ox_fuel:fuelCan', true, config.petrolCan.refillPrice)
		end

		TriggerServerEvent('ox_fuel:fuelCan', false, config.petrolCan.price)
	end

	ClearPedTasks(cache.ped)
end

function fuel.startFueling(vehicle, isPump, nearestPump)
	local vehState = Entity(vehicle).state
	local fuelAmount = vehState.fuel or GetVehicleFuelLevel(vehicle)
	local duration = math.ceil((100 - fuelAmount) / config.refillValue) * config.refillTick
	local price, moneyAmount
	local durability = 0

	if 100 - fuelAmount < config.refillValue then
		return lib.notify({ type = 'error', description = locale('tank_full') })
	end

	if isPump then
		price = 0
		moneyAmount = utils.getMoney()

		if config.priceTick > moneyAmount then
			return lib.notify({
				type = 'error',
				description = locale('not_enough_money', config.priceTick)
			})
		end
	elseif not state.petrolCan then
		return lib.notify({ type = 'error', description = locale('petrolcan_not_equipped') })
	elseif state.petrolCan.metadata.ammo <= config.durabilityTick then
		return lib.notify({
			type = 'error',
			description = locale('petrolcan_not_enough_fuel')
		})
	end

	state.isFueling = true

	if cache.vehicle then
		local player = PlayerPedId()
        local currentPos    = GetEntityCoords(vehicle)
		local posNPC = GetOffsetFromEntityInWorldCoords(player, 0.0, -4.5, 0.0)
		local vehicleHeading = GetEntityHeading(player)
		local pedNpc = nil

		if DoesEntityExist(GetPedInVehicleSeat(vehicle, -1)) then
			local modelped = GetHashKey('a_m_m_hillbilly_01')

            lib.requestModel(modelped)
	
			local pedNpc = CreatePed(26, modelped, (nearestPump.x + posNPC.x) / 2, (nearestPump.y + posNPC.y) / 2, (nearestPump.z + posNPC.z) / 2, vehicleHeading, true, false)
		
			ped = pedNpc

			RequestAnimDict("mp_character_creation@lineup@male_a")
			Wait(100)
			TaskPlayAnim(ped, "mp_character_creation@lineup@male_a", "intro", 1.0, 1.0, 5900, 0, 1, 0, 0, 0)
			Wait(3000)
			RequestAnimDict("mp_character_creation@customise@male_a")
			Wait(100)
			TaskPlayAnim(ped, "mp_character_creation@customise@male_a", "loop", 1.0, 1.0, -1, 0, 1, 0, 0, 0)

		end

		TaskTurnPedToFaceEntity(ped, vehicle, 2000)
		Wait(2000)
		SetCurrentPedWeapon(ped, -1569615261, true)
		LoadAnimDict("timetable@gardener@filling_can")
		TaskPlayAnim(ped, "timetable@gardener@filling_can", "gar_ig_5_filling_can", 2.0, 8.0, -1, 50, 0, 0, 0, 0)
			
	CreateThread(function()
			lib.progressCircle({
				duration = duration,
				useWhileDead = false,
				canCancel = true,
				disable = {
					move = true,
					car = true,
					combat = true,
				},
			})

			state.isFueling = false
		
			if state.isFueling == false then
				ClearPedTasks(ped)
				RemoveAnimDict("timetable@gardener@filling_can")
				Wait(2000)
				if ped ~= nil then
					DeleteEntity(ped)
				end
			end
		end)
	else
		TaskTurnPedToFaceEntity(cache.ped, vehicle, duration)

		CreateThread(function()
			lib.progressCircle({
				duration = duration,
				useWhileDead = false,
				canCancel = true,
				disable = {
					move = true,
					car = true,
					combat = true,
				},
				anim = {
					dict = isPump and 'timetable@gardener@filling_can' or 'weapon@w_sp_jerrycan',
					clip = isPump and 'gar_ig_5_filling_can' or 'fire',
				},
			})
	
			state.isFueling = false
		end)
	end
	Wait(500)

	while state.isFueling do
		if isPump then
			price += config.priceTick

			if price + config.priceTick >= moneyAmount then
				lib.cancelProgress()
			end
		elseif state.petrolCan then
			durability += config.durabilityTick

			if durability >= state.petrolCan.metadata.ammo then
				lib.cancelProgress()
				durability = state.petrolCan.metadata.ammo
				break
			end
		else
			break
		end

		fuelAmount += config.refillValue

		if fuelAmount >= 100 then
			state.isFueling = false
			fuelAmount = 100.0
		end

		Wait(config.refillTick)
	end

	ClearPedTasks(cache.ped)

	if isPump then
		TriggerServerEvent('ox_fuel:pay', price, fuelAmount, NetworkGetNetworkIdFromEntity(vehicle))
	else
		TriggerServerEvent('ox_fuel:updateFuelCan', durability, NetworkGetNetworkIdFromEntity(vehicle), fuelAmount)
	end
end

return fuel

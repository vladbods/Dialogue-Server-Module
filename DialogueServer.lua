--[[

	  _____  _       _                           _____                          
	 |  __ \(_)     | |                         / ____|                         
	 | |  | |_  __ _| | ___   __ _ _   _  ___  | (___   ___ _ ____   _____ _ __ 
	 | |  | | |/ _` | |/ _ \ / _` | | | |/ _ \  \___ \ / _ \ '__\ \ / / _ \ '__|
	 | |__| | | (_| | | (_) | (_| | |_| |  __/  ____) |  __/ |   \ V /  __/ |   
	 |_____/|_|\__,_|_|\___/ \__, |\__,_|\___| |_____/ \___|_|    \_/ \___|_|   
	                          __/ |                                             
	                         |___/                                              



	Written by vladbods for ZSSK Roblox
	@2026 All rights reserved
	
	DialogueServer is a module that controls in-game dialogues (player to player and player to NPC) by routing start requests to their respective types.
]]--

local DialogueServer = {}
DialogueServer.__index = DialogueServer

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Constants
local TYPES_FOLDER = script:WaitForChild("Types")
local MODULES_FOLDER = ServerScriptService:WaitForChild("Modules")
local HELPER_MODULES = MODULES_FOLDER:WaitForChild("Helper")

-- Helper Modules
local Signal = require(HELPER_MODULES:WaitForChild("Signal"))

-- Variables
local dialogueTypes = TYPES_FOLDER:GetChildren()

-- Functions and Methods

function DialogueServer.new(sessionData: table)
	local self = setmetatable({}, DialogueServer)
	
	self._sessionData = sessionData
	self._connections = {}
	self._update = Signal.new()
	
	return self
end

function DialogueServer:Start()
	print(self._update)

	-- Listen for either initiator or target character dying
	local function onCharacterDied(character)
		print(character)
		print("Character died")
		return self:End({
			_reason = "Dialogue ended: "..character.Name.." has died",
			_executioner = character.Name
		})
	end

	if self._sessionData._initiatorCharacter then
		table.insert(self._connections, 
			self._sessionData._initiatorCharacter.Humanoid.Died:Connect(function()\
				onCharacterDied(self._sessionData._initiatorCharacter)
			end)
		)
	end

	if self._sessionData._targetCharacter then
		if self._sessionData._targetCharacter ~= "no server character" then
			table.insert(self._connections, 
				self._sessionData._targetCharacter.Humanoid.Died:Connect(function()
					onCharacterDied(self._sessionData._targetCharacter)
				end)
			)
		end
	end

	-- Listen for either initiator or target character getting deleted
	local function onCharacterRemoved(character)
		return self:End({
			_reason = "Dialogue ended: "..character.Name.." has left the server",
			_executioner = character.Name
		})
	end

	if self._sessionData._initiator then
		table.insert(self._connections, 
			self._sessionData._initiator.Destroying:Connect(function()
				onCharacterRemoved(self._sessionData._initiator)
			end)
		)
	end

	if self._sessionData._target then
		table.insert(self._connections, 
			self._sessionData._target.Destroying:Connect(function()
				onCharacterRemoved(self._sessionData._target)
			end)
		)
	end

	-- Find the requested dialogue type
	local succes, err = pcall(function()
		local requestedDialogueType = self._sessionData._dialogueType
		local dialogueTypeModule = nil
		
		for _, dialogueType in dialogueTypes do
			if dialogueType.Name == requestedDialogueType then
				dialogueTypeModule = dialogueType
				break
			end
		end

		if not dialogueTypeModule then
			return self:End({
				_reason = "ERROR: "..self._sessionData._dialogueType.." dialogue handler does not exist.",
				_executioner = "Server"
			})
		end

		self._dialogueTypeControl = require(dialogueTypeModule).new(self._sessionData)

		self._dialogueTypeControl._update:Connect(function(data)
			if typeof(data) ~= "table" then return end

			local aType = data["actionType"]

			if aType == "end-session" then
				print(data)
				return self:End({
					_reason = data._endReason,
					_executioner = "Server"
				})
			end
		end)
		
		print("Starting")
		
		self._dialogueTypeControl:Start()
	end)

	if not succes then
		return self:End({
			_reason = "ERROR: "..err,
			_executioner = "Server"
		})
	end
end

function DialogueServer:End(endData: table)
	self._update:Fire({
		actionType = "end-session",
		_endReason = endData._reason,
		_executioner = endData._executioner
	})
	
	self._dialogueTypeControl:End(endData)
	
	for _, connection in self._connections do
		connection:Disconnect()
	end
	
	return true
end

return DialogueServer

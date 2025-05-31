-- // Credits to depthso for the original code
local Configuration = {
	UseWorkspace = false, 
	NoActors = false,
	RepoUrl = "https://raw.githubusercontent.com/depthso/Sigma-Spy/refs/heads/main",
	ParserUrl = "https://raw.githubusercontent.com/depthso/Roblox-parser/refs/heads/main"
}

--// Load overwrites
local Parameters = {...}
local Overwrites = Parameters[1]
if typeof(Overwrites) == "table" then
	for Key, Value in Overwrites do
		Configuration[Key] = Value
	end
end

--// Service handler
local Services = setmetatable({}, {
	__index = function(self, Name: string): Instance
		local Service = game:GetService(Name)
		return cloneref(Service)
	end,
})

--// Fetch Files module code
local FilesScript
if Configuration.UseWorkspace then
	FilesScript = readfile(`{Configuration.Folder}/lib/Files.lua`)
else
	FilesScript = game:HttpGet(`{Configuration.RepoUrl}/lib/Files.lua`)
end

--// Load files module
local Files = loadstring(FilesScript)()
Files:PushConfig(Configuration)
Files:Init({
	Services = Services
})

--// Modules
local Scripts = {
	--// User configurations
	Config = Files:GetModule("Sigma Spy/Config", "Config"),
	ReturnSpoofs = Files:GetModule("Sigma Spy/Return spoofs", "Return Spoofs"),
	Configuration = Configuration,
	Files = Files,

	--// Libraries
	Process = Files:GetModule("lib/Process"),
	Hook = Files:GetModule("lib/Hook"),
	Flags = Files:GetModule("lib/Flags"),
	Ui = Files:GetModule("lib/Ui"),
	Generation = Files:GetModule("lib/Generation"),
	Communication = Files:GetModule("lib/Communication")
}

--// Services
local Players: Players = Services.Players

--// Dependencies
local Modules = Files:LoadLibraries(Scripts)
local Process = Modules.Process
local Hook = Modules.Hook
local Ui = Modules.Ui
local Generation = Modules.Generation
local Communication = Modules.Communication
local Config = Modules.Config

--// Use custom font (optional)
local FontContent = Files:GetAsset("ProggyClean.ttf", true)
local FontJsonFile = Files:CreateFont("ProggyClean", FontContent)
Ui:SetFontFile(FontJsonFile)

--// Load modules
Process:CheckConfig(Config)
Files:LoadModules(Modules, {
	Modules = Modules,
	Services = Services
})

--// ReGui Create window
local Window = Ui:CreateWindow()


local Supported = Process:CheckIsSupported()
if not Supported then 
	Window:Close()
	return
end

--// Create communication channel
local ChannelId = Communication:CreateChannel()
Communication:AddCommCallback("QueueLog", function(...)
	Ui:QueueLog(...)
end)

--// Generation swaps
local LocalPlayer = Players.LocalPlayer
Generation:SetSwapsCallback(function(self)
	self:AddSwap(LocalPlayer, {
		String = "LocalPlayer",
	})
	self:AddSwap(LocalPlayer.Character, {
		String = "Character",
		NextParent = LocalPlayer
	})
end)


--// Create window content
Ui:CreateWindowContent(Window)

--// Begin the Log queue service
Ui:BeginLogService()

--// Load hooks
local ActorCode = Files:MakeActorScript(Scripts, ChannelId)
Hook:LoadHooks(ActorCode, ChannelId)
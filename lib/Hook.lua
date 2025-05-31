local Hook = {
	OrignalNamecall = nil,
	OrignalIndex = nil,
}

type table = {
	[any]: any
}

type MetaCallback = (Instance, ...any) -> ...any

--// Modules
local Modules
local Process
local Configuration
local Config

function Hook:Init(Data)
    Modules = Data.Modules

	Process = Modules.Process
	Config = Modules.Config or Config
	Configuration = Modules.Configuration or Configuration
end

--// The callback is expected to return a nil value sometimes which should be ingored
local HookMiddle = newcclosure(function(OriginalFunc, Callback, ...)
	--// Invoke callback and check for a reponce otherwise ignored
	local ReturnValues = Callback(...)
	if ReturnValues then
		return Process:Unpack(ReturnValues)
	end

	--// Invoke orignal function
	return OriginalFunc(...)
end)

--// getrawmetatable
function Hook:ReplaceMetaMethod(Object: Instance, Call: string, Callback: MetaCallback): MetaCallback
	local Metatable = getrawmetatable(Object)
	local OriginalFunc = rawget(Metatable, Call)
	
	--// Replace function
	setreadonly(Metatable, false)
	rawset(Metatable, Call, newcclosure(function(...)
		return HookMiddle(OriginalFunc, Callback, ...)
	end))
	setreadonly(Metatable, true)

	return OriginalFunc
end

--// hookfunction
function Hook:HookFunction(Func: (...any) -> ...any, Callback: (...any) -> ...any)
	local OriginalFunc
	OriginalFunc = hookfunction(Func, function(...)
		return HookMiddle(OriginalFunc, Callback, ...)
	end)
	return OriginalFunc
end

--// hookmetamethod
function Hook:HookMetaCall(Object: Instance, Call: string, Callback: MetaCallback): MetaCallback
	local OriginalFunc
	OriginalFunc = hookmetamethod(Object, Call, newcclosure(function(...)
		return HookMiddle(OriginalFunc, Callback, ...)
	end))
	return OriginalFunc
end

function Hook:HookMetaMethod(Object: Instance, Call: string, Callback: MetaCallback): MetaCallback
	--// Getrawmetatable
	if Config.ReplaceMetaCallFunc then
		return self:ReplaceMetaMethod(Object, Call, Callback)
	end
	
	--// Hookmetamethod
	return self:HookMetaCall(Object, Call, Callback)
end

local function Merge(Base: table, New: table)
	for Key, Value in next, New do
		Base[Key] = Value
	end
end

function Hook:RunOnActors(Code: string, ChannelId: number)
	if not getactors then return end
	
	local Actors = getactors()
	if not Actors then return end
	
	for _, Actor in Actors do 
		run_on_actor(Actor, Code, ChannelId)
	end
end

local function ProcessRemote(OriginalFunc, MetaMethod: string, self, Method: string, ...)
	return Process:ProcessRemote({
		Remote = self,
		Method = Method,
		OriginalFunc = OriginalFunc,
		MetaMethod = MetaMethod,
		TransferType = "Send",
		IsExploit = checkcaller()
	}, ...)
end

function Hook:HookRemoteTypeIndex(ClassName: string, FuncName: string)
	local Remote = Instance.new(ClassName)
	local Func = Remote[FuncName]
	local OriginalFunc

	--// Remotes will share the same functions
	--// 	For example FireServer will be identical
	--// Addionally, this is for __index calls.
	--// 	A __namecall hook will not detect this
	OriginalFunc = self:HookFunction(Func, function(self, ...)
		--// Check if the Object is allowed 
		if not Process:RemoteAllowed(self, "Send", FuncName) then return end

		--// Process the remote data
		return ProcessRemote(OriginalFunc, "__index", self, FuncName, ...)
	end)
end

function Hook:HookRemoteIndexes()
	local RemoteClassData = Process.RemoteClassData
	for ClassName, Data in RemoteClassData do
		local FuncName = Data.Send[1]
		self:HookRemoteTypeIndex(ClassName, FuncName)
	end
end

function Hook:BeginHooks()
	--// Hook Remote functions
	self:HookRemoteIndexes()

	--// Namecall hook
	local OriginalNameCall
	OriginalNameCall = self:HookMetaMethod(game, "__namecall", function(self, ...)
		local Method = getnamecallmethod()
		return ProcessRemote(OriginalNameCall, "__namecall", self, Method, ...)
	end)

	Merge(self, {
		OrignalNamecall = OriginalNameCall,
		--OrignalIndex = Oi
	})
end

function Hook:Index(Object: Instance, Key: string)
	return Object[Key]
end

function Hook:PushConfig(Overwrites)
    Merge(self, Overwrites)
end

function Hook:HookClientInvoke(Remote, Method, Callback): ((...any) -> ...any)?
	local Success, Function = pcall(function()
		return getcallbackvalue(Remote, Method)
	end)

	--// Some executors like Potassium will throw a error if the Callback value is nil
	if not Success then return end

	local PreviousFunction = Function
	Remote[Method] = Callback

	return PreviousFunction
end

function Hook:MultiConnect(Remotes)
	for _, Remote in next, Remotes do
		self:ConnectClientRecive(Remote)
	end
end

function Hook:ConnectClientRecive(Remote)
	--// Check if the Remote class is allowed for receiving
	local Allowed = Process:RemoteAllowed(Remote, "Receive")
	if not Allowed then return end

	--// Check if the Object has Remote class data
    local ClassData = Process:GetClassData(Remote)
    local IsRemoteFunction = ClassData.IsRemoteFunction
    local Method = ClassData.Receive[1]
	local PreviousFunction = nil

	--// New callback function
	local function Callback(...)
        return Process:ProcessRemote({
            Remote = Remote,
            Method = Method,
            OriginalFunc = PreviousFunction,
            IsReceive = true,
            MetaMethod = "Connect",
			IsExploit = checkcaller()
        }, ...)
	end

	--// Connect remote
	if not IsRemoteFunction then
   		Remote[Method]:Connect(Callback)
	else -- Remote functions
		self:HookClientInvoke(Remote, Method, Callback)
	end
end

function Hook:BeginService(Libraries, ExtraData, ChannelId, ...)
	--// Librareis
	local ReturnSpoofs = Libraries.ReturnSpoofs
	local ProcessLib = Libraries.Process
	local Communication = Libraries.Communication
	local Generation = Libraries.Generation
	local Config = Libraries.Config

	ProcessLib:CheckConfig(Config)

	--// Init data
	local InitData = {
		Modules = {
			ReturnSpoofs = ReturnSpoofs,
			Generation = Generation,
			Communication = Communication,
			Process = ProcessLib,
			Config = Config,
			Hook = self
		},
		Services = setmetatable({}, {
			__index = function(self, Name: string): Instance
				local Service = game:GetService(Name)
				return cloneref(Service)
			end,
		})
	}

	--// Init libraries
	Communication:Init(InitData)
	ProcessLib:Init(InitData)
	self:Init(InitData)

	--// Communication configuration
	local Channel, IsWrapped = Communication:GetCommChannel(ChannelId)
	Communication:SetChannel(Channel)
	Communication:AddTypeCallbacks({
		["RemoteData"] = function(Id: string, RemoteData)
			ProcessLib:SetRemoteData(Id, RemoteData)
		end,
		["AllRemoteData"] = function(Key: string, Value)
			ProcessLib:SetAllRemoteData(Key, Value)
		end,
	})
	
	--// Process configuration
	ProcessLib:SetChannel(Channel, IsWrapped)
	ProcessLib:SetExtraData(ExtraData)

	--// Hook configuration
	self:BeginHooks()
end

function Hook:LoadMetaHooks(ActorCode: string, ChannelId: number)
	--// Hook actors
	if not Configuration.NoActors then
		wait()
		self:RunOnActors(ActorCode, ChannelId)
	end

	--// Hook current thread
	self:BeginService(Modules, nil, ChannelId) 
end

function Hook:LoadReceiveHooks()
	local NoReceiveHooking = Config.NoReceiveHooking
	local BlackListedServices = Config.BlackListedServices

	if NoReceiveHooking then return end

	--// Remote added
	game.DescendantAdded:Connect(function(Remote) -- TODO
		self:ConnectClientRecive(Remote)
	end)

	--// Collect remotes with nil parents
	self:MultiConnect(getnilinstances())

	--// Search for remotes
	for _, Service in next, game:GetChildren() do
		if table.find(BlackListedServices, Service.ClassName) then continue end
		self:MultiConnect(Service:GetDescendants())
	end
end

function Hook:LoadHooks(ActorCode: string, ChannelId: number)
	self:LoadMetaHooks(ActorCode, ChannelId)
	self:LoadReceiveHooks()
end

return Hook

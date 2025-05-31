type table = {
    [any]: any
}

type RemoteData = {
	Remote: Instance,
	IsReceive: boolean?,
	Args: table,
    Id: string,
	Method: string,
    TransferType: string,
	ValueReplacements: table,
    ReturnValues: table,
    OriginalFunc: (Instance, ...any) -> ...any
}

--// Module
local Process = {
    --// Remote classes
    RemoteClassData = {
        ["RemoteEvent"] = {
            Send = {
                "FireServer",
                "fireServer",
            },
            Receive = {
                "OnClientEvent",
            }
        },
        ["RemoteFunction"] = {
            IsRemoteFunction = true,
            Send = {
                "InvokeServer",
                "invokeServer",
            },
            Receive = {
                "OnClientInvoke",
            }
        },
        ["UnreliableRemoteEvent"] = {
            Send = {
                "FireServer",
                "fireServer",
            },
            Receive = {
                "OnClientEvent",
            }
        },
        ["BindableEvent"] = {
            Send = {
                "Fire",
            },
            -- Receive = {
            --     "Event",
            -- }
        },
        ["BindableFunction"] = {
            IsRemoteFunction = true,
            Send = {
                "Invoke",
            },
            -- Receive = {
            --     "OnInvoke",
            -- }
        }
    },
    RemoteOptions = {},
    ConfigOverwrites = {
        [{"sirhurt", "potassium"}] = {
            ForceUseCustomComm = true
        }
    }
}

--// Modules
local Hook
local Communication
local ReturnSpoofs
local Ui

--// Communication channel
local Channel
local ChannelWrapped = false

local function Merge(Base: table, New: table)
	for Key, Value in next, New do
		Base[Key] = Value
	end
end

function Process:Init(Data)
    local Modules = Data.Modules

    --// Modules
    Ui = Modules.Ui
    Hook = Modules.Hook
    Communication = Modules.Communication
    ReturnSpoofs = Modules.ReturnSpoofs
end

--// Communication
function Process:SetChannel(NewChannel: BindableEvent, IsWrapped: boolean)
    Channel = NewChannel
    ChannelWrapped = IsWrapped
end

function Process:GetConfigOverwrites(Name: string)
    local ConfigOverwrites = self.ConfigOverwrites

    for List, Overwrites in next, ConfigOverwrites do
        if not table.find(List, Name) then continue end
        return Overwrites
    end
    return
end

function Process:CheckConfig(Config: table)
    local Name = identifyexecutor():lower()

    --// Force configuration overwrites for specific executors
    local Overwrites = self:GetConfigOverwrites(Name)
    if not Overwrites then return end

    Merge(Config, Overwrites)
end

function Process:DeepCloneTable(Table, Ignore: table?)
	local New = {}
	for Key, Value in next, Table do
        --// Check if the value is ignored
        if Ignore and table.find(Ignore, Value) then continue end

		New[Key] = typeof(Value) == "table" and self:DeepCloneTable(Value) or Value
	end
	return New
end

function Process:Unpack(Table: table)
	local Length = table.maxn(Table)
	return unpack(Table, 1, Length)
end

function Process:PushConfig(Overwrites)
    Merge(self, Overwrites)
end

function Process:FuncExists(Name: string)
	return getfenv(1)[Name]
end

function Process:CheckExecutor(): boolean
    local Blacklisted = {
        "wave",
        "xeno",
        "solara",
    }

    local Name = identifyexecutor():lower()
    local IsBlacklisted = table.find(Blacklisted, Name)

    --// Some executors have broken functionality
    if IsBlacklisted then
        Ui:ShowUnsupportedExecutor(Name)
        return false
    end

    return true
end

function Process:CheckFunctions(): boolean
    local CoreFunctions = {
        "hookmetamethod",
        "hookfunction",
        "getrawmetatable",
        "setreadonly"
    }

    --// Check if the functions exist in the ENV
    for _, Name in CoreFunctions do
        local Func = self:FuncExists(Name)
        if Func then continue end

        --// Function missing!
        Ui:ShowUnsupported(Name)
        return false
    end

    return true
end

function Process:CheckIsSupported(): boolean
    --// Check if the executor is blacklisted
    local ExecutorSupported = self:CheckExecutor()
    if not ExecutorSupported then
        return false
    end

    --// Check if the core functions exist
    local FunctionsSupported = self:CheckFunctions()
    if not FunctionsSupported then
        return false
    end

    return true
end

function Process:GetClassData(Remote: Instance): table?
    local RemoteClassData = self.RemoteClassData
    local ClassName = Hook:Index(Remote, "ClassName")

    return RemoteClassData[ClassName]
end

function Process:IsProtectedRemote(Remote: Instance): boolean
    local IsDebug = Remote == Communication.DebugIdRemote
    local IsChannel = Remote == (ChannelWrapped and Channel.Channel or Channel)

    return IsDebug or IsChannel
end

function Process:RemoteAllowed(Remote: Instance, TransferType: string, Method: string?): boolean?
    if typeof(Remote) ~= 'Instance' then return end
    
    --// Check if the Remote is protected
    if self:IsProtectedRemote(Remote) then return end

    --// Fetch class table
	local ClassData = self:GetClassData(Remote)
	if not ClassData then return end

    --// Check if the transfer type has data
	local Allowed = ClassData[TransferType]
	if not Allowed then return end

    --// Check if the method is allowed
	if Method then
		return table.find(Allowed, Method) ~= nil
	end

	return true
end

function Process:SetExtraData(Data: table)
    if not Data then return end
    self.ExtraData = Data
end

function Process:GetRemoteSpoof(Remote: Instance, Method: string, ...)
    local Spoof = ReturnSpoofs[Remote]

    if not Spoof then return end
    if Spoof.Method ~= Method then return end

    local ReturnValues = Spoof.Return

    --// Call the ReturnValues function type
    if typeof(ReturnValues) == "function" then
        ReturnValues = ReturnValues(...)
    end

	Communication:Warn("Spoofed", Method)
	return ReturnValues
end

function Process:FindCallingLClosure(Offset: number)
    Offset += 1

    while true do
        Offset += 1

        --// Check if the stack level is valid
        local IsValid = debug.info(Offset, "l") ~= -1
        if not IsValid then continue end

        --// Check if the function is valud
        local Function = debug.info(Offset, "f")
        if not Function then return end

        return Function
    end
end

function Process:Callback(Data: RemoteData, ...): table?
    --// Unpack Data
    local OriginalFunc = Data.OriginalFunc
    local Id = Data.Id
    local Method = Data.Method
    local Remote = Data.Remote

    local RemoteData = self:GetRemoteData(Id)

    --// Check if the Remote is Blocked
    if RemoteData.Blocked then return {} end

    --// Check for a spoof
    local Spoof = self:GetRemoteSpoof(Remote, Method, OriginalFunc, ...)
    if Spoof then return Spoof end

    --// Check if the orignal function was passed
    if not OriginalFunc then return end

    --// Invoke orignal function
    return {
        OriginalFunc(Remote, ...)
    }
end

function Process:ProcessRemote(Data: RemoteData, ...): table?
    --// Unpack Data
    local Remote = Data.Remote
	local Method = Data.Method
    local TransferType = Data.TransferType

	--// Check if the transfertype method is allowed
	if TransferType and not self:RemoteAllowed(Remote, TransferType, Method) then return end

    --// Fetch details
    local Id = Communication:GetDebugId(Remote)
    local ClassData = self:GetClassData(Remote)
    local Timestamp = tick()

    --// Add extra data into the log if needed
    local ExtraData = self.ExtraData
    if ExtraData then
        Merge(Data, ExtraData)
    end

    --// Add to queue
    Merge(Data, {
		CallingScript = getcallingscript(),
		CallingFunction = self:FindCallingLClosure(6),
        Id = Id,
		ClassData = ClassData,
        Timestamp = Timestamp,
        Args = Communication:SerializeTable({...})
    })

    --// Invoke the Remote and log return values
    local ReturnValues = self:Callback(Data, ...)
    Data.ReturnValues = ReturnValues

    --// Queue log
    Communication:QueueLog(Data)

    return ReturnValues
end

function Process:SetAllRemoteData(Key: string, Value)
    local RemoteOptions = self.RemoteOptions
	for RemoteID, Data in next, RemoteOptions do
		Data[Key] = Value
	end
end

function Process:GetRemoteData(Id: string)
    local RemoteOptions = self.RemoteOptions

    --// Check for existing remote data
	local Existing = RemoteOptions[Id]
	if Existing then return Existing end
	
    --// Base remote data
	local Data = {
		Excluded = false,
		Blocked = false
	}

	RemoteOptions[Id] = Data
	return Data
end

--// The communication creates a different table address
--// Recived tables will not be the same
function Process:SetRemoteData(Id: string, RemoteData: table)
    local RemoteOptions = self.RemoteOptions
    RemoteOptions[Id] = RemoteData
end

function Process:UpdateRemoteData(Id: string, RemoteData: table)
    Communication:Communicate("RemoteData", Id, RemoteData)
end

function Process:UpdateAllRemoteData(Key: string, Value)
    Communication:Communicate("AllRemoteData", Key, Value)
end

return Process
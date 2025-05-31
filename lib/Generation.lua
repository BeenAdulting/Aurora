type table = {
	[any]: any
}

type RemoteData = {
	Remote: Instance,
	IsReceive: boolean?,
	Args: table,
	Method: string,
    TransferType: string,
	ValueReplacements: table,
	NoVariables: boolean?
}

--// Module
local Generation = {
	DumpBaseName = "SigmaSpy-Dump %s.lua"
}

--// Modules
local Config
local Hook
local ParserModule
local ThisScript = script

local function Merge(Base: table, New: table)
	for Key, Value in next, New do
		Base[Key] = Value
	end
end

function Generation:Init(Data: table)
    local Modules = Data.Modules
	local Configuration = Modules.Configuration

	--// Modules
	Config = Modules.Config
	Hook = Modules.Hook
	
	--// Import parser
	local ParserUrl = Configuration.ParserUrl
	self:LoadParser(ParserUrl)
end

function Generation:WriteDump(Content: string): string
	local DumpBaseName = self.DumpBaseName

	local TimeStamp = os.date("%Y-%m-%d_%H-%M-%S")
	local FilePath = DumpBaseName:format(TimeStamp)

	--// Write to file
	writefile(FilePath, Content)

	return FilePath
end

function Generation:LoadParser(ImportUrl: string)
	local MainPath = `{ImportUrl}/main.lua`
	local MainContent = game:HttpGet(MainPath)
	ParserModule = loadstring(MainContent, "Parser")()
	
	--// Configure Parser imports to use game:HttpGet
	function ParserModule:Import(Name: string)
		local Url = `{ImportUrl}/{Name}.lua`
		local Content = game:HttpGet(Url)
		local Closure = loadstring(Content, Name)
		return Closure()
	end

	--// Load parser module
	ParserModule:Load()
end

function Generation:MakeValueSwapsTable(): table
	local Formatter = ParserModule.Modules.Formatter
	return Formatter:MakeReplacements()
end

function Generation:SetSwapsCallback(Callback: (Interface: table) -> ())
	self.SwapsCallback = Callback
end

function Generation:GetBase(Module): (string, boolean)
	local Code = "-- Generated with Aurora Rspy\n"

	--// Generate variables code
	local Variables = Module.Parser:MakeVariableCode({
		"Services", "Variables", "Remote"
	})

	local NoVariables = Variables == ""
	Code ..= Variables

	return Code, NoVariables
end

function Generation:GetSwaps()
	local Func = self.SwapsCallback
	local Swaps = {}

	local Interface = {}
	function Interface:AddSwap(Object: Instance, Data: table)
		if not Object then return end
		Swaps[Object] = Data
	end

	--// Invoke GetSwaps function
	Func(Interface)

	return Swaps
end

function Generation:PickVariableName(): string
	local Names = Config.VariableNames
	return Names[math.random(1, #Names)]
end

function Generation:NewParser(Extra: table)
	local VariableName = self:PickVariableName()
	local Swaps = self:GetSwaps()

	local Configuration = {
		VariableBase = VariableName,
		Swaps = Swaps,
		IndexFunc = function(...)
			return Hook:Index(...)
		end,
	}

	--// Merge extra configuration
	Merge(Configuration, Extra)

	--// Create new parser instance
	return ParserModule:New(Configuration)
end

type CallInfo = {
	EmptyArgs: boolean,
	Arguments: table,
	RemoteVariable: string
}
function Generation:CallRemote(Data, Info: CallInfo): string
	local IsReceive = Data.IsReceive
	local Method = Data.Method

	local EmptyArgs = Info.EmptyArgs
	local Arguments = Info.Arguments
	local RemoteVariable = Info.RemoteVariable
	local IsArray = Info.IsArray

	--// Wrap in a unpack if the table is a dict
	if not EmptyArgs and not IsArray then
		Arguments = `unpack({Arguments}, 1, table.maxn({Arguments}))`
	end

	--// Firesignal script for client recieves
	if IsReceive then
		local Second = EmptyArgs and "" or `, {Arguments}`
		local Signal = `{RemoteVariable}.{Method}`

		local Code = `-- This data was received from the server`
		Code ..= `\nfiresignal({Signal}{Second})`
		return Code
	end
	
	--// Remote invoke script
	return `{RemoteVariable}:{Method}({Arguments})`
end

function Generation:RemoteScript(Module, Data: RemoteData): string
	--// Unpack data
	local Remote = Data.Remote
	local Args = Data.Args
	local NoVariables = Data.NoVariables

	--// Remote info
	local ClassName = Hook:Index(Remote, "ClassName")
	local IsNilParent = Hook:Index(Remote, "Parent") == nil
	
	local Variables = Module.Variables
	local Formatter = Module.Formatter
	local Parser = Module.Parser
	
	--// Pre-render variables
	Variables:PrerenderVariables(Args, {"Instance"})

	--// Parse arguments
	local ParsedArgs, ItemsCount, IsArray = Parser:ParseTableIntoString({
		NoBrackets = true,
		NoVariables = NoVariables,
		Table = Args
	})

	--// Create remote variable
	local RemoteVariable = Variables:MakeVariable({
		Value = Formatter:Format(Remote, {
			NoVariables = true
		}),
		Comment = `{ClassName} {IsNilParent and "| Remote parent is nil" or ""}`,
		Name = Formatter:MakeName(Remote),
		Lookup = Remote,
		Class = "Remote"
	})

	--// Create table variable if not an array
	if not IsArray or NoVariables then
		ParsedArgs = Variables:MakeVariable({
			Value = ("{%s}"):format(ParsedArgs),
			Comment = not IsArray and "Arguments aren't ordered" or nil,
			Name = "RemoteArgs",
			Class = "Remote"
		})
	end

	--// Make code
	local Code = self:GetBase(Module)
	local CallCode = self:CallRemote(Data, {
		RemoteVariable = RemoteVariable,
		EmptyArgs = ItemsCount == 0,
		Arguments = ParsedArgs,
		IsArray = IsArray
	})
	
	return `{Code}\n{CallCode}`
end

function Generation:ConnectionsTable(Signal: RBXScriptSignal): table
	local Connections = getconnections(Signal)
	local DataArray = {}

	for _, Connection in next, Connections do
		local Function = Connection.Function
		local Script = rawget(getfenv(Function), "script")

		--// Skip if self
		if Script == ThisScript then continue end

		--// Connection data
		local Data = {
			Function = Function,
			State = Connection.State,
			Script = Script
		}

		table.insert(DataArray, Data)
	end

	return DataArray
end

function Generation:TableScript(Module, Table: table): string
	--// Pre-render variables
	Module.Variables:PrerenderVariables(Table, {"Instance"})

	--// Parse arguments
	local ParsedTable = Module.Parser:ParseTableIntoString({
		Table = Table
	})

	--// Generate script
	local Code, NoVariables = self:GetBase(Module)
	local Seperator = NoVariables and "" or "\n"
	Code ..= `{Seperator}return {ParsedTable}`

	return Code
end

function Generation:MakeTypesTable(Table: table): table
	local Types = {}

	for Key, Value in next, Table do
		local Type = typeof(Value)
		if Type == "table" then
			Type = self:MakeTypesTable(Value)
		end

		Types[Key] = Type
	end

	return Types
end

function Generation:ConnectionInfo(Remote: Instance, ClassData: table): table?
	local ReceiveMethods = ClassData.Receive
	if not ReceiveMethods then return end

	local Connections = {}
	for _, Method: string in next, ReceiveMethods do
		pcall(function() -- TODO: GETCALLBACKVALUE
			local Signal = Hook:Index(Remote, Method)
			Connections[Method] = self:ConnectionsTable(Signal)
		end)
	end

	return Connections
end

function Generation:AdvancedInfo(Module, Data: table): string
	--// Unpack remote data
	local MetaMethod = Data.MetaMethod
	local Function = Data.CallingFunction
	local ClassData = Data.ClassData
	local Method = Data.Method
	local Remote = Data.Remote
	local Script = Data.CallingScript
	local Id = Data.Id
	local Args = Data.Args

	--// Unpack info
	local SourceScript = rawget(getfenv(Function), "script")

	--// Advanced info table base
	local FunctionInfo = {
		["Caller"] = {
			["SourceScript"] = SourceScript,
			["CallingScript"] = Script,
			["CallingFunction"] = Function
		},
		["Remote"] = {
			["Remote"] = Remote,
			["RemoteID"] = Id,
			["Method"] = Method,
			["Connections"] = self:ConnectionInfo(Remote, ClassData)
		},
		["Arguments"] = {
			["Length"] = #Args,
			["Types"] = self:MakeTypesTable(Args),
		},
		["MetaMethod"] = MetaMethod,
		["IsActor"] = Data.IsActor,
	}

	--// Some closures may not be lua
	if islclosure(Function) then
		FunctionInfo["UpValues"] = debug.getupvalues(Function)
		FunctionInfo["Constants"] = debug.getconstants(Function)
	end

	--// Generate script
	return self:TableScript(Module, FunctionInfo)
end

function Generation:DumpLogs(Logs: table): string
	local BaseData
	local Parsed = {
		Remote = nil,
		Calls = {}
	}

	--// Create new parser instance
	local Module = Generation:NewParser()

	for _, Data in Logs do
		local Calls = Parsed.Calls
		local Table = {
			Args = Data.Args,
			Timestamp = Data.Timestamp,
			ReturnValues = Data.ReturnValues,
			Method = Data.Method,
			MetaMethod = Data.MetaMethod,
			CallingScript = Data.CallingScript,
		}

		--// Append
		table.insert(Calls, Table)

		--// Set BaseData
		if not BaseData then
			BaseData = Data
		end
	end

	--// Basedata merge
	Parsed.Remote = BaseData.Remote

	--// Compile and save
	local Output = self:TableScript(Module, Parsed)
	local FilePath = self:WriteDump(Output)
	
	return FilePath
end

return Generation

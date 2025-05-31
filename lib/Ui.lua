local Ui = {
	DefaultEditorContent = [=[--[[ 
	Welcome to Aurora Rspy
]] ]=],
	LogLimit = 100,
    SeasonLabels = { 
        January = "%s", 
        February = "%s", 
        March = "%s", 
        April = "%s", 
        May = "%s", 
        June = "%s", 
        July = "%s", 
        August = "%s", 
        September = "%s", 
        October = "%s", 
        November = "%s", 
        December = "%s"
    },
	Scales = {
		["Mobile"] = UDim2.fromOffset(480, 280),
		["Desktop"] = UDim2.fromOffset(600, 400),
	},
    BaseConfig = {
        Theme = "SigmaSpy",
        NoScroll = true,
    },
	OptionTypes = {
		boolean = "Checkbox",
	},
	DisplayRemoteInfo = {
		"MetaMethod",
		"Method",
		"Remote",
		"CallingScript",
		"IsActor",
		"Id"
	},

    Window = nil,
    RandomSeed = Random.new(tick()),
	Logs = setmetatable({}, {__mode = "k"}),
	LogQueue = setmetatable({}, {__mode = "v"}),
} 

type table = {
	[any]: any
}

type Log = {
	Remote: Instance,
	Method: string,
	Args: table,
	IsReceive: boolean?,
	MetaMethod: string?,
	OrignalFunc: ((...any) -> ...any)?,
	CallingScript: Instance?,
	CallingFunction: ((...any) -> ...any)?,
	ClassData: table?,
	ReturnValues: table?,
	RemoteData: table?,
	Id: string,
	Selectable: table,
	HeaderData: table,
	ValueSwaps: table,
	Timestamp: number,
	IsExploit: boolean
}

--// Compatibility
local SetClipboard = setclipboard or toclipboard or set_clipboard

--// Libraries
local ReGui = loadstring(game:HttpGet('https://raw.githubusercontent.com/depthso/Dear-ReGui/refs/heads/main/ReGui.lua'))()
local IDEModule = loadstring(game:HttpGet('https://raw.githubusercontent.com/depthso/Dear-ReGui/refs/heads/main/lib/ide.lua'))()

--// Services
local InsertService: InsertService

--// Modules
local Flags
local Generation
local Process
local Hook 
local Config
local Communication
local Files

local ActiveData = nil
local RemotesCount = 0

local TextFont = Font.fromEnum(Enum.Font.Code)
local FontSuccess = false

function Ui:Init(Data)
    local Modules = Data.Modules
	local Services = Data.Services

	--// Services
	InsertService = Services.InsertService

	--// Modules
	Flags = Modules.Flags
	Generation = Modules.Generation
	Process = Modules.Process
	Hook = Modules.Hook
	Config = Modules.Config
	Communication = Modules.Communication
	Files = Modules.Files

	--// ReGui
	self:CheckScale()
	self:LoadFont()
	self:LoadReGui()
end

function Ui:CheckScale()
	local BaseConfig = self.BaseConfig
	local Scales = self.Scales

	local IsMobile = ReGui:IsMobileDevice()
	local Device = IsMobile and "Mobile" or "Desktop"

	BaseConfig.Size = Scales[Device]
end

function Ui:SetClipboard(Content: string)
	SetClipboard(Content)
end

function Ui:TurnSeasonal(Text: string): string
    local SeasonLabels = self.SeasonLabels
    local Month = os.date("%B")
    local Base = SeasonLabels[Month]

    return Base:format(Text)
end

function Ui:LoadFont()
	local FontFile = self.FontJsonFile

	--// Get FontFace AssetId
	local AssetId = Files:LoadCustomasset(FontFile)
	if not AssetId then return end

	--// Create custom FontFace
	local NewFont = Font.new(AssetId)
	TextFont = NewFont
	FontSuccess = true
end

function Ui:SetFontFile(FontFile: string)
	self.FontJsonFile = FontFile
end

function Ui:FontWasSuccessful()
	if FontSuccess then return end

	--// Switch to DarkTheme instead of the ImGui theme
	local Window = self.Window
	Window:SetTheme("DarkTheme")

	--// Error message
	self:ShowModal({
		"Unfortunately your executor was unable to download the font and therefore switched to the Dark theme",
		"\nIf you would like to use the ImGui theme, \nplease download the font (assets/ProggyClean.ttf)",
		"and put put it in your workspace folder\n(Sigma Spy/assets)"
	})
end

function Ui:LoadReGui()
	local ThemeConfig = Config.ThemeConfig
	ThemeConfig.TextFont = TextFont

	--// ReGui
	local PrefabsId = "rbxassetid://" .. ReGui.PrefabsId
	ReGui:DefineTheme("SigmaSpy", ThemeConfig)
	ReGui:Init({
		Prefabs = InsertService:LoadLocalAsset(PrefabsId)
	})
end

type CreateButtons = {
	Base: table,
	Buttons: table,
	NoTable: boolean?
}
function Ui:CreateButtons(Parent, Data: CreateButtons)
	local Base = Data.Base
	local Buttons = Data.Buttons
	local NoTable = Data.NoTable

	--// Create table layout
	if not NoTable then
		Parent = Parent:Table({
			MaxColumns = 3
		}):NextRow()
	end

	--// Create buttons
	for _, Button in next, Buttons do
		local Container = Parent
		if not NoTable then
			Container = Parent:NextColumn()
		end

		ReGui:CheckConfig(Button, Base)
		Container:Button(Button)
	end
end

function Ui:CreateWindow()
    local BaseConfig = self.BaseConfig

	--// Create Window
    local Window = ReGui:Window(BaseConfig)
    self.Window = Window
    self:AuraCounterService()

	--// Check if the font was successfully downloaded
	self:FontWasSuccessful()

	--// UiVisible flag callback
	Flags:SetFlagCallback("UiVisible", function(self, Visible)
		Window:SetVisible(Visible)
	end)

	return Window
end

function Ui:ShowModal(Lines: table)
	local Window = self.Window
	local Message = table.concat(Lines, "\n")

	--// Modal Window
	local ModalWindow = Window:PopupModal({
		Title = "Aurora Rspy",
	})
	ModalWindow:Label({
		Text = Message,
		RichText = true,
		TextWrapped = true
	})
	ModalWindow:Button({
		Text = "Okay",
		Callback = function()
			ModalWindow:ClosePopup()
		end,
	})
end

function Ui:ShowUnsupportedExecutor(Name: string)
	Ui:ShowModal({
		"Unfortunately Sigma Spy is not supported on your executor",
		`\nYour executor: {Name}`
	})
end

function Ui:ShowUnsupported(FuncName: string)
	Ui:ShowModal({
		"Unfortunately Sigma Spy is not supported on your executor",
		`\nMissing function: {FuncName}`
	})
end

function Ui:CreateOptionsForDict(Parent, Dict: table, Callback)
	local Options = {}

	--// Dictonary wrap
	for Key, Value in next, Dict do
		Options[Key] = {
			Value = Value,
			Label = Key,
			Callback = function(_, Value)
				Dict[Key] = Value

				--// Invoke callback
				if not Callback then return end
				Callback()
			end
		}
	end

	--// Create elements
	self:CreateElements(Parent, Options)
end

function Ui:CheckKeybindLayout(Container, KeyCode: Enum.KeyCode, Callback)
	if not KeyCode then return Container end

	--// Create Row layout
	Container = Container:Row({
		HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween
	})

	--// Add Keybind element
	Container:Keybind({
		Label = "",
		Value = KeyCode,
		LayoutOrder = 2,
		Callback = function()
			--// Check if keybinds are enabled
			local Enabled = Flags:GetFlagValue("KeybindsEnabled")
			if not Enabled then return end

			--// Invoke callback
			Callback()
		end,
	})

	return Container
end

function Ui:CreateElements(Parent, Options)
	local OptionTypes = self.OptionTypes
	
	--// Create table layout
	local Table = Parent:Table({
		MaxColumns = 3
	}):NextRow()

	for Name, Data in Options do
		local Value = Data.Value
		local Type = typeof(Value)

		--// Add missing values into options table
		ReGui:CheckConfig(Data, {
			Class = OptionTypes[Type],
			Label = Name,
		})
		
		--// Check if a element type exists for value type
		local Class = Data.Class
		assert(Class, `No {Type} type exists for option`)

		local Container = Table:NextColumn()
		local Checkbox = nil

		--// Check for a keybind layout
		local Keybind = Data.Keybind
		Container = self:CheckKeybindLayout(Container, Keybind, function()
			Checkbox:Toggle()
		end)
		
		--// Create column and element
		Checkbox = Container[Class](Container, Data)
	end
end

--// Boiiii what did you say about Sigma Spy 💀💀
function Ui:DisplayAura()
    local Window = self.Window
    local Rand = self.RandomSeed

	--// Aura (boiiiii)
    local AURA = Rand:NextInteger(1, 9999999)
    local AURADELAY = Rand:NextInteger(1, 5)

	--// Title
	local Title = ` Aurora Rspy  `
	local Seasonal = self:TurnSeasonal(Title)
    Window:SetTitle(Seasonal)

    wait(AURADELAY)
end

function Ui:AuraCounterService()
    task.spawn(function()
        while true do
            self:DisplayAura()
        end
    end)
end

function Ui:CreateWindowContent(Window)
    --// Window group
    local Layout = Window:List({
        UiPadding = 2,
        HorizontalFlex = Enum.UIFlexAlignment.Fill,
        VerticalFlex = Enum.UIFlexAlignment.Fill,
        FillDirection = Enum.FillDirection.Vertical,
        Fill = true
    })

	--// Remotes list
    self.RemotesList = Layout:Canvas({
        Scroll = true,
        UiPadding = 5,
        AutomaticSize = Enum.AutomaticSize.None,
        FlexMode = Enum.UIFlexMode.None,
        Size = UDim2.new(0, 130, 1, 0)
    })

	--// Tab box
	local InfoSelector = Layout:TabSelector({
        NoAnimation = true,
        Size = UDim2.new(1, -130, 0.4, 0),
    })

	self.InfoSelector = InfoSelector
	self.CanvasLayout = Layout

	--// Make tabs
	self:MakeEditorTab(InfoSelector)
	self:MakeOptionsTab(InfoSelector)
end

function Ui:MakeOptionsTab(InfoSelector)
	--// TabSelector
	local OptionsTab = InfoSelector:CreateTab({
		Name = "Options"
	})

	--// Add global options
	OptionsTab:Separator({Text="Logs"})
	self:CreateButtons(OptionsTab, {
		Base = {
			Size = UDim2.new(1, 0, 0, 20),
			AutomaticSize = Enum.AutomaticSize.Y,
		},
		Buttons = {
			{
				Text = "Clear logs",
				Callback = function()
					local Tab = ActiveData and ActiveData.Tab or nil

					--// Remove the Remote tab
					if Tab then
						InfoSelector:RemoveTab(Tab)
					end

					--// Clear all log elements
					ActiveData = nil
					self:ClearLogs()
				end,
			},
			{
				Text = "Clear blocks",
				Callback = function()
					Process:UpdateAllRemoteData("Blocked", false)
				end,
			},
			{
				Text = "Clear excludes",
				Callback = function()
					Process:UpdateAllRemoteData("Excluded", false)
				end,
			},
			{
				Text = "Copy Discord",
				Callback = function()
					self:SetClipboard("https://discord.gg/s9ngmUDWgb")
				end,
			}
		}
	})

	--// Flag options
	OptionsTab:Separator({Text="Settings"})
	self:CreateElements(OptionsTab, Flags:GetFlags())

	self:AddDetailsSection(OptionsTab)
end

function Ui:AddDetailsSection(OptionsTab)
	OptionsTab:Separator({Text="Information"})
	OptionsTab:BulletText({
		Rows = {
			"Sigma spy ",
			"Credits to depthso for the original code",
			"Libraries: Roblox-Parser, Dear-ReGui",
			"Thank you to syn for your suggestions and testing"
		}
	})
end

local function MakeActiveDataCallback(Func: string)
	return function()
		if not ActiveData then return end
		return ActiveData[Func](ActiveData)
	end
end

function Ui:MakeEditorTab(InfoSelector)
	local Default = self.DefaultEditorContent
	local Window = self.Window

	local SyntaxColors = Config.SyntaxColors

	--// IDE
	local CodeEditor = IDEModule.CodeFrame.new({
		Editable = false,
		FontSize = 13,
		Colors = SyntaxColors,
		FontFace = TextFont
	})
	CodeEditor:SetText(Default)
	
	local EditorTab = InfoSelector:CreateTab({
		Name = "Editor"
	})

	--// Configure IDE frame
	ReGui:ApplyFlags({
		Object = CodeEditor.Gui,
		WindowClass = Window,
		Class = {
			--Border = true,
			Fill = true,
			Active = true,
			Parent = EditorTab:GetObject(),
			BackgroundTransparency = 1,
		}
	})

	--// Buttons
	local ButtonsRow = EditorTab:Row()
	self:CreateButtons(ButtonsRow, {
		Base = {},
		NoTable = true,
		Buttons = {
			{
				Text = "Copy",
				Callback = function()
					local Script = CodeEditor:GetText()
					self:SetClipboard(Script)
				end
			},
			{
				Text = "Repeat call",
				Callback = MakeActiveDataCallback("RepeatCall")
			},
			{
				Text = "Get return",
				Callback = MakeActiveDataCallback("GetReturn")
			},
			{
				Text = "Get info",
				Callback = MakeActiveDataCallback("GenerateInfo")
			},
			{
				Text = "Decompile source",
				Callback = MakeActiveDataCallback("Decompile")
			}
		}
	})
	
	self.CodeEditor = CodeEditor
end

function Ui:ShouldFocus(Tab): boolean
	local InfoSelector = self.InfoSelector
	local ActiveTab = InfoSelector.ActiveTab

	--// If there is an empty tab
	if not ActiveTab then
		return true
	end

	return InfoSelector:CompareTabs(ActiveTab, Tab)
end

function Ui:RemovePreviousTab(Title: string): boolean
	--// No previous tabs
	if not ActiveData then 
		return false 
	end

	--// TabSelector
	local InfoSelector = self.InfoSelector

	--// Previous elements
	local PreviousTab = ActiveData.Tab
	local PreviousSelectable = ActiveData.Selectable

	--// Remove previous tab and set selectable focus
	local TabFocused = self:ShouldFocus(PreviousTab)
	InfoSelector:RemoveTab(PreviousTab)
	PreviousSelectable:SetSelected(false)

	--// Create new tab
	return TabFocused
end

function Ui:SetFocusedRemote(Data)
	--// Unpack remote data
	local Remote = Data.Remote
	local Method = Data.Method
	local IsReceive = Data.IsReceive
	local Script = Data.CallingScript
	local ClassData = Data.ClassData
	local HeaderData = Data.HeaderData
	local ValueSwaps = Data.ValueSwaps
	local Args = Data.Args
	local Id = Data.Id

	--// Flags
	local TableArgs = Flags:GetFlagValue("TableArgs")
	local NoVariables = Flags:GetFlagValue("NoVariables")

	--// Unpack info
	local RemoteData = Process:GetRemoteData(Id)
	local IsRemoteFunction = ClassData.IsRemoteFunction

	--// UI data
	local CodeEditor = self.CodeEditor
	local ToDisplay = self.DisplayRemoteInfo
	local InfoSelector = self.InfoSelector

	local TabFocused = self:RemovePreviousTab()
	local Tab = InfoSelector:CreateTab({
		Name = `Remote: {Remote}`,
		Focused = TabFocused
	})

	--// Create new parser
	local Module = Generation:NewParser({
		NoVariables = NoVariables
	})
	local Parser = Module.Parser
	local Formatter = Module.Formatter
	Formatter:SetValueSwaps(ValueSwaps)

	--// Set this log to be selected
	ActiveData = Data
	Data.Tab = Tab
	Data.Selectable:SetSelected(true)

	local function SetIDEText(...)
		CodeEditor:SetText(...)
	end

	--// Functions
	function Data:RepeatCall()
		local Signal = Hook:Index(Remote, Method)

		if IsReceive then
			firesignal(Signal, Process:Unpack(Args))
		else
			Signal(Remote, Process:Unpack(Args))
		end
	end
	function Data:GetReturn()
		local ReturnValues = Data.ReturnValues

		if not IsRemoteFunction then
			SetIDEText("-- Remote is not a function bozo (-9999999 AURA)")
			return
		end
		if not ReturnValues then
			SetIDEText("-- No return values (-9999999 AURA)")
			return
		end

		--// Generate script
		local Script = Generation:TableScript(Module, ReturnValues)
		SetIDEText(Script)
	end
	function Data:GenerateInfo()
		--// Reject client events
		if IsReceive then 
			local Script = ""
			Script ..= ""

			SetIDEText(Script)
			return 
		end

		--// Generate script
		local Script = Generation:AdvancedInfo(Module, Data)
		SetIDEText(Script)
	end
	function Data:Decompile()
		--// Check if decompile function exists
		if not decompile then 
			SetIDEText("--Exploit is missing 'decompile' function ")
			return 
		end

		--// Check if script exists
		if not Script then 
			SetIDEText("--Script is missing ")
			return
		end

		SetIDEText("--Decompiling... ")

		--// Decompile script
		local Decompiled = decompile(Script)
		local Source = "--Generated by aurora Rspy\n"
		Source ..=  Decompiled

		SetIDEText(Source)
	end
	
	--// RemoteOptions
	self:CreateOptionsForDict(Tab, RemoteData, function()
		Process:UpdateRemoteData(Id, RemoteData)
	end)

	--// Instance options
	self:CreateButtons(Tab, {
		Base = {
			Size = UDim2.new(1, 0, 0, 20),
			AutomaticSize = Enum.AutomaticSize.Y,
		},
		Buttons = {
			{
				Text = "Copy script path",
				Callback = function()
					SetClipboard(Parser:MakePathString({
						Object = Script,
						NoVariables = true
					}))
				end,
			},
			{
				Text = "Copy remote path",
				Callback = function()
					SetClipboard(Parser:MakePathString({
						Object = Remote,
						NoVariables = true
					}))
				end,
			},
			{
				Text = "Remove log",
				Callback = function()
					InfoSelector:RemoveTab(Tab)
					Data.Selectable:Remove()
					HeaderData:Remove()
					ActiveData = nil
				end,
			},
			{
				Text = "Dump logs",
				Callback = function()
					local Logs = HeaderData.Entries
					local FilePath = Generation:DumpLogs(Logs)
					self:ShowModal({"Saved dump to", FilePath})
				end,
			}
		}
	})

	--// Remote information
	local Rows = {"Name", "Value"}
	local DataTable = Tab:Table({
		Border = true,
		RowBackground = true,
		MaxColumns = 2
	})

	--// Table headers
	local HeaderRow = DataTable:HeaderRow()
	for _, Catagory in Rows do
		local Column = HeaderRow:NextColumn()
		Column:Label({Text=Catagory})
	end

	--// Table layout
	for RowIndex, Name in ToDisplay do
		local Row = DataTable:Row()
		
		--// Create Columns
		for Count, Catagory in Rows do
			local Column = Row:NextColumn()
			
			--// Value text
			local Value = Catagory == "Name" and Name or Data[Name]
			if not Value then continue end

			Column:Label({Text=`{Value}`})
		end
	end
	
	--// Generate script
	local Parsed
	if TableArgs then
		Parsed = Generation:TableScript(Module, Args)
	else
		Parsed = Generation:RemoteScript(Module, Data)
	end

	SetIDEText(Parsed)
end

function Ui:GetRemoteHeader(Data: Log)
	local LogLimit = self.LogLimit
	local Logs = self.Logs
	local RemotesList = self.RemotesList

	--// Remote info
	local Id = Data.Id
	local Remote = Data.Remote

	--// NoTreeNodes
	local NoTreeNodes = Flags:GetFlagValue("NoTreeNodes")

	--// Check for existing TreeNode
	local Existing = Logs[Id]
	if Existing then return Existing end

	--// Header data
	local HeaderData = {	
		LogCount = 0,
		Data = Data,
		Entries = {}
	}

	--// Increment treenode count
	RemotesCount += 1

	--// Create new treenode element
	if not NoTreeNodes then
		HeaderData.TreeNode = RemotesList:TreeNode({
			LayoutOrder = -1 * RemotesCount,
			Title = `{Remote}`
		})
	end

	function HeaderData:CheckLimit()
		local Entries = self.Entries
		if #Entries < LogLimit then return end
			
		--// Get and remove last element
		local Log = table.remove(Entries, 1)
		Log.Selectable:Remove()
	end

	function HeaderData:LogAdded(Data)
		--// Increment log count
		self.LogCount += 1
		self:CheckLimit()

		--// Add entry
		local Entries = self.Entries
		table.insert(Entries, Data)
		
		return self
	end

	function HeaderData:Remove()
		--// Remove TreeNode
		local TreeNode = self.TreeNode
		if TreeNode then
			TreeNode:Remove()
		end

		--// Clear tables from memory
		Logs[Id] = nil
		table.clear(HeaderData)
	end

	Logs[Id] = HeaderData
	return HeaderData
end

function Ui:ClearLogs()
	local Logs = self.Logs
	local RemotesList = self.RemotesList

	--// Clear all elements
	RemotesCount = 0
	RemotesList:ClearChildElements()

	--// Clear logs from memory
	table.clear(Logs)
end

function Ui:QueueLog(Data)
	local LogQueue = self.LogQueue
    table.insert(LogQueue, Data)
end

function Ui:ProcessLogQueue()
	local Queue = self.LogQueue
    if #Queue <= 0 then return end

	--// Create a log element for each in the Queue
    for Index, Data in next, Queue do
        self:CreateLog(Data)
        table.remove(Queue, Index)
    end
end

function Ui:BeginLogService()
	coroutine.wrap(function()
		while true do
			self:ProcessLogQueue()
			task.wait()
		end
	end)()
end

function Ui:FilterName(Name: string): string
	local Trimmed = Name:sub(1, 15)
	local Filtred = Trimmed:gsub("[\n\r]", "")
	return Filtred
end

function Ui:CreateLog(Data: Log)
	--// Unpack log data
    local Remote = Data.Remote
	local Method = Data.Method
    local Args = Data.Args
    local IsReceive = Data.IsReceive
	local Id = Data.Id
	local Timestamp = Data.Timestamp
	local IsExploit = Data.IsExploit
	
	local IsNilParent = Hook:Index(Remote, "Parent") == nil
	local RemoteData = Process:GetRemoteData(Id)

	--// Paused
	local Paused = Flags:GetFlagValue("Paused")
	if Paused then return end

	--// Check caller (Ignore exploit calls)
	local LogExploit = Flags:GetFlagValue("LogExploit")
	if not LogExploit and IsExploit then return end

	--// IgnoreNil
	local IgnoreNil = Flags:GetFlagValue("IgnoreNil")
	if IgnoreNil and IsNilParent then return end

    --// LogRecives check
	local LogRecives = Flags:GetFlagValue("LogRecives")
	if not LogRecives and IsReceive then return end

	--// NoTreeNodes
	local NoTreeNodes = Flags:GetFlagValue("NoTreeNodes")

    --// Excluded check
    if RemoteData.Excluded then return end

	--// Deserialize arguments
	Args = Communication:DeserializeTable(Args)

	--// Deep clone data
	local ClonedArgs = Process:DeepCloneTable(Args)
	Data.Args = ClonedArgs
	Data.ValueSwaps = Generation:MakeValueSwapsTable(Timestamp)

	--// Generate log title
	local Color = Config.MethodColors[Method:lower()]
	local Text = NoTreeNodes and `{Remote} | {Method}` or Method

	--// FindStringForName check
	local FindString = Flags:GetFlagValue("FindStringForName")
	if FindString then
		for _, Arg in next, ClonedArgs do
			if typeof(Arg) == "string" then
				local Filtred = self:FilterName(Arg)
				Text = `{Filtred} | {Text}`
				break
			end
		end
	end

	--// Fetch HeaderData by the RemoteID used for stacking
	local Header = self:GetRemoteHeader(Data)
	local RemotesList = self.RemotesList

	local LogCount = Header.LogCount
	local TreeNode = Header.TreeNode 
	local Parent = TreeNode or RemotesList

	--// Increase log count - TreeNodes are in GetRemoteHeader function
	if NoTreeNodes then
		RemotesCount += 1
		LogCount = RemotesCount
	end

    --// Create focus button
	Data.HeaderData = Header
	Data.Selectable = Parent:Selectable({
		Text = Text,
        LayoutOrder = -1 * LogCount,
		TextColor3 = Color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Callback = function()
			self:SetFocusedRemote(Data)
		end,
    })

	Header:LogAdded(Data)
end

return Ui

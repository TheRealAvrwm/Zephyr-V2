-- Zephyr Universal — Interface Refresh
-- Lightweight obfuscated edition.
--[=[
MIT License

Copyright (c) 2023 dawid

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

]=]
local a={alive=true,errors={},cleanup={},threads={}}local b=task function a.
record(c)if#a.errors==20 then table.remove(a.errors,1)end a.errors[#a.errors+1]=
tostring(c):sub(1,400)end function a.guard(c)local d,e=false,0 return function(
...)if not a.alive or d or os.clock()<e then return end d=true local f=coroutine
.running()local g=a.threads[f]a.threads[f]=true local h=table.pack(pcall(c,...))
if not g then a.threads[f]=nil end d=false if not h[1]then a.record(h[2])e=os.
clock()+2 return end return table.unpack(h,2,h.n)end end local c=setmetatable({}
,{__index=b})local function d(e,f,...)local g=table.pack(...)local h=coroutine.
create(function()a.guard(f)(table.unpack(g,1,g.n))a.threads[coroutine.running()]
=nil end)if a.alive then a.threads[h]=true b[e](h)end return h end function c.
spawn(e,...)return d('spawn',e,...)end function c.defer(e,...)return d('defer',e
,...)end local function e(f,g)local h=os.clock()+(g or 90)repeat if not a.alive
then return nil end local i,j=pcall(f)if i and j then return j end b.wait(0.2)
until os.clock()>=h end local function f()if not a.alive then return end a.alive
=false for g=#a.cleanup,1,-1 do pcall(a.cleanup[g])end for g in pairs(a.threads)
do if g~=coroutine.running()then pcall(b.cancel,g)end end table.clear(a.threads)
end a.stop=f local aa,ab=pcall(function()do local g=game:GetService('Players')
local h=e(function()return g.LocalPlayer end)if not h then return end local i=_G
if type(getgenv)=='function'then local j,k=pcall(getgenv)if j and type(k)==
'table'then i=k end end local j=i.__ZEPHYR_UNIVERSAL_RUNTIME if type(j)=='table'
and type(j.stop)=='function'then pcall(j.stop)end i.__ZEPHYR_UNIVERSAL_RUNTIME=a
end if not e(function()return game:IsLoaded()and workspace.CurrentCamera and
game:GetService('Players').LocalPlayer:FindFirstChild('PlayerGui')end)then
return end local function g(h,i)for j=1,i and 1 or 3 do local k,l local m=c.
spawn(function()local m,n=pcall(game.HttpGet,game,h)if m and type(n)=='string'
then l=n end k=true end)e(function()return k end,12)if not k then pcall(b.cancel
,m)a.threads[m]=nil end if l then if not i then local n=Instance.new('Folder')
local o=pcall(function()n.Parent=game:GetService('CoreGui')end)n:Destroy()if not
o then l=l:gsub("game:GetService'CoreGui'",
"game:GetService('Players').LocalPlayer.PlayerGui")l=l:gsub(
'game:GetService%("CoreGui"%)',
"game:GetService('Players').LocalPlayer.PlayerGui")end end local n=loadstring(l)
if n then local o,p=pcall(n)if o and type(p)=='table'then return p end a.record(
p)end end if j<(i and 1 or 3)then c.wait(j)end end end local function h()local i
=game:GetService('CoreGui')local j=Instance.new('Folder')local k=pcall(function(
)j.Parent=i end)j:Destroy()if not k then i=game:GetService('Players').
LocalPlayer.PlayerGui end local l,m={{1,'ModuleScript',{'MainModule'},{{18,
'ModuleScript',{'Creator'}},{28,'ModuleScript',{'Icons'}},{47,'ModuleScript',{
'Themes'},{{50,'ModuleScript',{'Dark'}},{52,'ModuleScript',{'Light'}},{51,
'ModuleScript',{'Darker'}},{53,'ModuleScript',{'Rose'}},{49,'ModuleScript',{
'Aqua'}},{48,'ModuleScript',{'Amethyst'}}}},{19,'ModuleScript',{'Elements'},{{21
,'ModuleScript',{'Colorpicker'}},{27,'ModuleScript',{'Toggle'}},{23,
'ModuleScript',{'Input'}},{20,'ModuleScript',{'Button'}},{25,'ModuleScript',{
'Paragraph'}},{22,'ModuleScript',{'Dropdown'}},{26,'ModuleScript',{'Slider'}},{
24,'ModuleScript',{'Keybind'}}}},{29,'Folder',{'Packages'},{{30,'ModuleScript',{
'Flipper'},{{33,'ModuleScript',{'GroupMotor'}},{46,'ModuleScript',{
'isMotor.spec'}},{39,'ModuleScript',{'Signal'}},{40,'ModuleScript',{
'Signal.spec'}},{45,'ModuleScript',{'isMotor'}},{36,'ModuleScript',{
'Instant.spec'}},{44,'ModuleScript',{'Spring.spec'}},{42,'ModuleScript',{
'SingleMotor.spec'}},{38,'ModuleScript',{'Linear.spec'}},{31,'ModuleScript',{
'BaseMotor'}},{43,'ModuleScript',{'Spring'}},{35,'ModuleScript',{'Instant'}},{37
,'ModuleScript',{'Linear'}},{41,'ModuleScript',{'SingleMotor'}},{34,
'ModuleScript',{'GroupMotor.spec'}},{32,'ModuleScript',{'BaseMotor.spec'}}}}}},{
2,'ModuleScript',{'Acrylic'},{{3,'ModuleScript',{'AcrylicBlur'}},{5,
'ModuleScript',{'CreateAcrylic'}},{6,'ModuleScript',{'Utils'}},{4,'ModuleScript'
,{'AcrylicPaint'}}}},{7,'Folder',{'Components'},{{9,'ModuleScript',{'Button'}},{
12,'ModuleScript',{'Notification'}},{13,'ModuleScript',{'Section'}},{17,
'ModuleScript',{'Window'}},{14,'ModuleScript',{'Tab'}},{10,'ModuleScript',{
'Dialog'}},{8,'ModuleScript',{'Assets'}},{16,'ModuleScript',{'TitleBar'}},{15,
'ModuleScript',{'Textbox'}},{11,'ModuleScript',{'Element'}}}}}}}local aa={
function()local n,o,p,q,r=m(1)local s,t,u,v,w,x=game:GetService'Lighting',game:
GetService'RunService',game:GetService'Players'.LocalPlayer,game:GetService
'UserInputService',game:GetService'TweenService',game:GetService'Workspace'.
CurrentCamera local y,z=u:GetMouse(),o local A,B,C,D=p(z.Creator),p(z.Elements),
p(z.Acrylic),z.Components local E,F,G=p(D.Notification),A.New,protectgui or(syn
and syn.protect_gui)or function()end local H=F('ScreenGui',{Parent=t:IsStudio()
and u.PlayerGui or i})G(H)E:Init(H)local I={Version='1.1.0',OpenFrames={},
Options={},Themes=p(z.Themes).Names,Window=nil,WindowFrame=nil,Unloaded=false,
Theme='Dark',DialogOpen=false,UseAcrylic=false,Acrylic=false,Transparency=true,
MinimizeKeybind=nil,MinimizeKey=Enum.KeyCode.LeftControl,GUI=H}function I.
SafeCallback(J,K,...)if not K then return end local L,M=pcall(K,...)if not L
then local N,O=M:find':%d+: 'if not O then return I:Notify{Title='Interface',
Content='Callback error',SubContent=M,Duration=5}end return I:Notify{Title=
'Interface',Content='Callback error',SubContent=M:sub(O+1),Duration=5}end end
function I.Round(J,K,L)if L==0 then return math.floor(K)end K=tostring(K)return
K:find'%.'and tonumber(K:sub(1,K:find'%.'+L))or K end local J=p(z.Icons).assets
function I.GetIcon(K,L)if L~=nil and J['lucide-'..L]then return J['lucide-'..L]
end return nil end local K={}K.__index=K K.__namecall=function(L,M,...)return K[
M](...)end for L,M in ipairs(B)do K['Add'..M.__type]=function(N,O,P)M.Container=
N.Container M.Type=N.Type M.ScrollFrame=N.ScrollFrame M.Library=I return M:New(O
,P)end end I.Elements=K function I.CreateWindow(L,M)assert(M.Title,
'Window - Missing Title')if I.Window then print
'You cannot create more than one window.'return end I.MinimizeKey=M.MinimizeKey
I.UseAcrylic=M.Acrylic if M.Acrylic then C.init()end local N=p(D.Window){Parent=
H,Size=M.Size,Title=M.Title,SubTitle=M.SubTitle,TabWidth=M.TabWidth}I.Window=N I
:SetTheme(M.Theme)return N end function I.SetTheme(L,M)if I.Window and table.
find(I.Themes,M)then I.Theme=M A.UpdateTheme()end end function I.Destroy(L)if I.
Window then I.Unloaded=true if I.UseAcrylic then I.Window.AcrylicPaint.Model:
Destroy()end A.Disconnect()I.GUI:Destroy()end end function I.ToggleAcrylic(L,M)
if I.Window then if I.UseAcrylic then I.Acrylic=M I.Window.AcrylicPaint.Model.
Transparency=M and 0.98 or 1 if M then C.Enable()else C.Disable()end end end end
function I.ToggleTransparency(L,M)if I.Window then I.Window.AcrylicPaint.Frame.
Background.BackgroundTransparency=M and 0.35 or 0 end end function I.Notify(L,M)
return E:New(M)end if getgenv then getgenv().Fluent=I end return I end,function(
)local n,o,p,q,r=m(2)local s={AcrylicBlur=p(o.AcrylicBlur),CreateAcrylic=p(o.
CreateAcrylic),AcrylicPaint=p(o.AcrylicPaint)}function s.init()local t=Instance.
new'DepthOfFieldEffect't.FarIntensity=0 t.InFocusRadius=0.1 t.NearIntensity=1
local u={}function s.Enable()for v,w in pairs(u)do w.Enabled=false end t.Parent=
game:GetService'Lighting'end function s.Disable()for v,w in pairs(u)do w.Enabled
=w.enabled end t.Parent=nil end local v=function()local v=function(v)if v:IsA
'DepthOfFieldEffect'then u[v]={enabled=v.Enabled}end end for w,x in pairs(game:
GetService'Lighting':GetChildren())do v(x)end if game:GetService'Workspace'.
CurrentCamera then for w,x in pairs(game:GetService'Workspace'.CurrentCamera:
GetChildren())do v(x)end end end v()s.Enable()end return s end,function()local n
,o,p,q,r=m(3)local s,t,u,v=p(o.Parent.Parent.Creator),p(o.Parent.CreateAcrylic),
unpack(p(o.Parent.Utils))local w=function(w)local x={}w=w or 0.001 local y,z={
topLeft=Vector2.new(),topRight=Vector2.new(),bottomRight=Vector2.new()},t()z.
Parent=workspace local A,B=function(A,B)y.topLeft=B y.topRight=B+Vector2.new(A.X
,0)y.bottomRight=B+A end,function()local A=game:GetService'Workspace'.
CurrentCamera if A then A=A.CFrame end local B=A if not B then B=CFrame.new()end
local C,D,E,F=B,y.topLeft,y.topRight,y.bottomRight local G,H,I=u(D,w),u(E,w),u(F
,w)local J,K=(H-G).Magnitude,(H-I).Magnitude z.CFrame=CFrame.fromMatrix((G+I)/2,
C.XVector,C.YVector,C.ZVector)z.Mesh.Scale=Vector3.new(J,K,0)end local C,D=
function(C)local D=v()local E,F=C.AbsoluteSize-Vector2.new(D,D),C.
AbsolutePosition+Vector2.new(D/2,D/2)A(E,F)c.spawn(B)end,function()local C=game:
GetService'Workspace'.CurrentCamera if not C then return end table.insert(x,C:
GetPropertyChangedSignal'CFrame':Connect(B))table.insert(x,C:
GetPropertyChangedSignal'ViewportSize':Connect(B))table.insert(x,C:
GetPropertyChangedSignal'FieldOfView':Connect(B))c.spawn(B)end z.Destroying:
Connect(function()for E,F in x do pcall(function()F:Disconnect()end)end end)D()
return C,z end return function(x)local y,z,A={},w(x)local B=s.New('Frame',{
BackgroundTransparency=1,Size=UDim2.fromScale(1,1)})s.AddSignal(B:
GetPropertyChangedSignal'AbsolutePosition',function()z(B)end)s.AddSignal(B:
GetPropertyChangedSignal'AbsoluteSize',function()z(B)end)y.AddParent=function(C)
s.AddSignal(C:GetPropertyChangedSignal'Visible',function()y.SetVisibility(C.
Visible)end)end y.SetVisibility=function(C)A.Transparency=C and 0.98 or 1 end y.
Frame=B y.Model=A return y end end,function()local n,o,p,q,r=m(4)local s,t=p(o.
Parent.Parent.Creator),p(o.Parent.AcrylicBlur)local u=s.New return function(v)
local w={}w.Frame=u('Frame',{Size=UDim2.fromScale(1,1),BackgroundTransparency=
0.9,BackgroundColor3=Color3.fromRGB(255,255,255),BorderSizePixel=0},{u(
'ImageLabel',{Image='rbxassetid://8992230677',ScaleType='Slice',SliceCenter=Rect
.new(Vector2.new(99,99),Vector2.new(99,99)),AnchorPoint=Vector2.new(0.5,0.5),
Size=UDim2.new(1,120,1,116),Position=UDim2.new(0.5,0,0.5,0),
BackgroundTransparency=1,ImageColor3=Color3.fromRGB(0,0,0),ImageTransparency=0.7
}),u('UICorner',{CornerRadius=UDim.new(0,8)}),u('Frame',{BackgroundTransparency=
0.45,Size=UDim2.fromScale(1,1),Name='Background',ThemeTag={BackgroundColor3=
'AcrylicMain'}},{u('UICorner',{CornerRadius=UDim.new(0,8)})}),u('Frame',{
BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=0.4,Size=
UDim2.fromScale(1,1)},{u('UICorner',{CornerRadius=UDim.new(0,8)}),u('UIGradient'
,{Rotation=90,ThemeTag={Color='AcrylicGradient'}})}),u('ImageLabel',{Image=
'rbxassetid://9968344105',ImageTransparency=0.98,ScaleType=Enum.ScaleType.Tile,
TileSize=UDim2.new(0,128,0,128),Size=UDim2.fromScale(1,1),BackgroundTransparency
=1},{u('UICorner',{CornerRadius=UDim.new(0,8)})}),u('ImageLabel',{Image=
'rbxassetid://9968344227',ImageTransparency=0.9,ScaleType=Enum.ScaleType.Tile,
TileSize=UDim2.new(0,128,0,128),Size=UDim2.fromScale(1,1),BackgroundTransparency
=1,ThemeTag={ImageTransparency='AcrylicNoise'}},{u('UICorner',{CornerRadius=UDim
.new(0,8)})}),u('Frame',{BackgroundTransparency=1,Size=UDim2.fromScale(1,1),
ZIndex=2},{u('UICorner',{CornerRadius=UDim.new(0,8)}),u('UIStroke',{Transparency
=0.5,Thickness=1,ThemeTag={Color='AcrylicBorder'}})})})local x if p(o.Parent.
Parent).UseAcrylic then x=t()x.Frame.Parent=w.Frame w.Model=x.Model w.AddParent=
x.AddParent w.SetVisibility=x.SetVisibility end return w end end,function()local
n,o,p,q,r=m(5)local s=o.Parent.Parent local t=p(s.Creator)local u=function()
local u=t.New('Part',{Name='Body',Color=Color3.new(0,0,0),Material=Enum.Material
.Glass,Size=Vector3.new(1,1,0),Anchored=true,CanCollide=false,Locked=true,
CastShadow=false,Transparency=0.98},{t.New('SpecialMesh',{MeshType=Enum.MeshType
.Brick,Offset=Vector3.new(0,0,-1E-6)})})return u end return u end,function()
local n,o,p,q,r=m(6)local s,t=function(s,t,u,v,w)return(s-t)*(w-v)/(u-t)+v end,
function(s,t)local u=game:GetService'Workspace'.CurrentCamera:ScreenPointToRay(s
.X,s.Y)return u.Origin+u.Direction*t end local u=function()local u=game:
GetService'Workspace'.CurrentCamera.ViewportSize.Y return s(u,0,2560,8,56)end
return{t,u}end,[8]=function()local n,o,p,q,r=m(8)return{Close=
'rbxassetid://9886659671',Min='rbxassetid://9886659276',Max=
'rbxassetid://9886659406',Restore='rbxassetid://9886659001'}end,[9]=function()
local n,o,p,q,r=m(9)local s=o.Parent.Parent local t,u=p(s.Packages.Flipper),p(s.
Creator)local v,w=u.New,t.Spring.new return function(x,y,z)z=z or false local A=
{}A.Title=v('TextLabel',{FontFace=Font.new
'rbxasset://fonts/families/GothamSSm.json',TextColor3=Color3.fromRGB(200,200,200
),TextSize=14,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Center,
TextYAlignment=Enum.TextYAlignment.Center,BackgroundColor3=Color3.fromRGB(255,
255,255),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,Size=UDim2.
fromScale(1,1),ThemeTag={TextColor3='Text'}})A.HoverFrame=v('Frame',{Size=UDim2.
fromScale(1,1),BackgroundTransparency=1,ThemeTag={BackgroundColor3='Hover'}},{v(
'UICorner',{CornerRadius=UDim.new(0,4)})})A.Frame=v('TextButton',{Size=UDim2.
new(0,0,0,32),Parent=y,ThemeTag={BackgroundColor3='DialogButton'}},{v('UICorner'
,{CornerRadius=UDim.new(0,4)}),v('UIStroke',{ApplyStrokeMode=Enum.
ApplyStrokeMode.Border,Transparency=0.65,ThemeTag={Color='DialogButtonBorder'}})
,A.HoverFrame,A.Title})local B,C=u.SpringMotor(1,A.HoverFrame,
'BackgroundTransparency',z)u.AddSignal(A.Frame.MouseEnter,function()C(0.97)end)u
.AddSignal(A.Frame.MouseLeave,function()C(1)end)u.AddSignal(A.Frame.
MouseButton1Down,function()C(1)end)u.AddSignal(A.Frame.MouseButton1Up,function()
C(0.97)end)return A end end,[10]=function()local n,o,p,q,r=m(10)local s,t,u,v=
game:GetService'UserInputService',game:GetService'Players'.LocalPlayer:GetMouse(
),game:GetService'Workspace'.CurrentCamera,o.Parent.Parent local w,x=p(v.
Packages.Flipper),p(v.Creator)local y,z,A,B=w.Spring.new,w.Instant.new,x.New,{
Window=nil}function B.Init(C,D)B.Window=D return B end function B.Create(C)local
D={Buttons=0}D.TintFrame=A('TextButton',{Text='',Size=UDim2.fromScale(1,1),
BackgroundColor3=Color3.fromRGB(0,0,0),BackgroundTransparency=1,Parent=B.Window.
Root},{A('UICorner',{CornerRadius=UDim.new(0,8)})})local E,F=x.SpringMotor(1,D.
TintFrame,'BackgroundTransparency',true)D.ButtonHolder=A('Frame',{Size=UDim2.
new(1,-40,1,-40),AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,
0.5),BackgroundTransparency=1},{A('UIListLayout',{Padding=UDim.new(0,10),
FillDirection=Enum.FillDirection.Horizontal,HorizontalAlignment=Enum.
HorizontalAlignment.Center,SortOrder=Enum.SortOrder.LayoutOrder})})D.
ButtonHolderFrame=A('Frame',{Size=UDim2.new(1,0,0,70),Position=UDim2.new(0,0,1,-
70),ThemeTag={BackgroundColor3='DialogHolder'}},{A('Frame',{Size=UDim2.new(1,0,0
,1),ThemeTag={BackgroundColor3='DialogHolderLine'}}),D.ButtonHolder})D.Title=A(
'TextLabel',{FontFace=Font.new('rbxasset://fonts/families/GothamSSm.json',Enum.
FontWeight.SemiBold,Enum.FontStyle.Normal),Text='Dialog',TextColor3=Color3.
fromRGB(240,240,240),TextSize=22,TextXAlignment=Enum.TextXAlignment.Left,Size=
UDim2.new(1,0,0,22),Position=UDim2.fromOffset(20,25),BackgroundColor3=Color3.
fromRGB(255,255,255),BackgroundTransparency=1,ThemeTag={TextColor3='Text'}})D.
Scale=A('UIScale',{Scale=1})local G,H=x.SpringMotor(1.1,D.Scale,'Scale')D.Root=
A('CanvasGroup',{Size=UDim2.fromOffset(300,165),AnchorPoint=Vector2.new(0.5,0.5)
,Position=UDim2.fromScale(0.5,0.5),GroupTransparency=1,Parent=D.TintFrame,
ThemeTag={BackgroundColor3='Dialog'}},{A('UICorner',{CornerRadius=UDim.new(0,8)}
),A('UIStroke',{Transparency=0.5,ThemeTag={Color='DialogBorder'}}),D.Scale,D.
Title,D.ButtonHolderFrame})local I,J=x.SpringMotor(1,D.Root,'GroupTransparency')
function D.Open(K)p(v).DialogOpen=true D.Scale.Scale=1.1 F(0.75)J(0)H(1)end
function D.Close(K)p(v).DialogOpen=false F(1)J(1)H(1.1)D.Root.UIStroke:Destroy()
c.wait(0.15)D.TintFrame:Destroy()end function D.Button(K,L,M)D.Buttons=D.Buttons
+1 L=L or'Button'M=M or function()end local N=p(v.Components.Button)('',D.
ButtonHolder,true)N.Title.Text=L for O,P in next,D.ButtonHolder:GetChildren()do
if P:IsA'TextButton'then P.Size=UDim2.new(1/D.Buttons,-(((D.Buttons-1)*10)/D.
Buttons),0,32)end end x.AddSignal(N.Frame.MouseButton1Click,function()p(v):
SafeCallback(M)pcall(function()D:Close()end)end)return N end return D end return
B end,[11]=function()local n,o,p,q,r=m(11)local s=o.Parent.Parent local t,u=p(s.
Packages.Flipper),p(s.Creator)local v,w=u.New,t.Spring.new return function(x,y,z
,A)local B={}B.TitleLabel=v('TextLabel',{FontFace=Font.new(
'rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.Medium,Enum.FontStyle
.Normal),Text=x,TextColor3=Color3.fromRGB(240,240,240),TextSize=13,
TextXAlignment=Enum.TextXAlignment.Left,Size=UDim2.new(1,0,0,14),
BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,ThemeTag={
TextColor3='Text'}})B.DescLabel=v('TextLabel',{FontFace=Font.new
'rbxasset://fonts/families/GothamSSm.json',Text=y,TextColor3=Color3.fromRGB(200,
200,200),TextSize=12,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
BackgroundColor3=Color3.fromRGB(255,255,255),AutomaticSize=Enum.AutomaticSize.Y,
BackgroundTransparency=1,Size=UDim2.new(1,0,0,14),ThemeTag={TextColor3='SubText'
}})B.LabelHolder=v('Frame',{AutomaticSize=Enum.AutomaticSize.Y,BackgroundColor3=
Color3.fromRGB(255,255,255),BackgroundTransparency=1,Position=UDim2.fromOffset(
15,0),Size=UDim2.new(1,-28,0,0)},{v('UIListLayout',{SortOrder=Enum.SortOrder.
LayoutOrder,VerticalAlignment=Enum.VerticalAlignment.Center}),v('UIPadding',{
PaddingBottom=UDim.new(0,15),PaddingTop=UDim.new(0,15)}),B.TitleLabel,B.
DescLabel})B.Border=v('UIStroke',{Transparency=0.6,ApplyStrokeMode=Enum.
ApplyStrokeMode.Border,Color=Color3.fromRGB(0,0,0),ThemeTag={Color=
'ElementBorder'}})B.Frame=v('TextButton',{Size=UDim2.new(1,0,0,0),
BackgroundTransparency=0.89,BackgroundColor3=Color3.fromRGB(130,130,130),Parent=
z,AutomaticSize=Enum.AutomaticSize.Y,Text='',LayoutOrder=7,ThemeTag={
BackgroundColor3='Element',BackgroundTransparency='ElementTransparency'}},{v(
'UICorner',{CornerRadius=UDim.new(0,8)}),B.Border,B.LabelHolder})function B.
SetTitle(C,D)B.TitleLabel.Text=D end function B.SetDesc(C,D)if D==nil then D=''
end if D==''then B.DescLabel.Visible=false else B.DescLabel.Visible=true end B.
DescLabel.Text=D end function B.Destroy(C)B.Frame:Destroy()end B:SetTitle(x)B:
SetDesc(y)if A then local C,D,E=s.Themes,u.SpringMotor(u.GetThemeProperty
'ElementTransparency',B.Frame,'BackgroundTransparency',false,true)u.AddSignal(B.
Frame.MouseEnter,function()E(u.GetThemeProperty'ElementTransparency'-u.
GetThemeProperty'HoverChange')end)u.AddSignal(B.Frame.MouseLeave,function()E(u.
GetThemeProperty'ElementTransparency')end)u.AddSignal(B.Frame.MouseButton1Down,
function()E(u.GetThemeProperty'ElementTransparency'+u.GetThemeProperty
'HoverChange')end)u.AddSignal(B.Frame.MouseButton1Up,function()E(u.
GetThemeProperty'ElementTransparency'-u.GetThemeProperty'HoverChange')end)end
return B end end,[12]=function()local n,o,p,q,r=m(12)local s=o.Parent.Parent
local t,u,v=p(s.Packages.Flipper),p(s.Creator),p(s.Acrylic)local w,x,y,z=t.
Spring.new,t.Instant.new,u.New,{}function z.Init(A,B)z.Holder=y('Frame',{
Position=UDim2.new(1,-30,1,-30),Size=UDim2.new(0,310,1,-30),AnchorPoint=Vector2.
new(1,1),BackgroundTransparency=1,Parent=B},{y('UIListLayout',{
HorizontalAlignment=Enum.HorizontalAlignment.Center,SortOrder=Enum.SortOrder.
LayoutOrder,VerticalAlignment=Enum.VerticalAlignment.Bottom,Padding=UDim.new(0,
20)})})end function z.New(A,B)B.Title=B.Title or'Title'B.Content=B.Content or
'Content'B.SubContent=B.SubContent or''B.Duration=B.Duration or nil B.Buttons=B.
Buttons or{}local C={Closed=false}C.AcrylicPaint=v.AcrylicPaint()C.Title=y(
'TextLabel',{Position=UDim2.new(0,14,0,17),Text=B.Title,RichText=true,TextColor3
=Color3.fromRGB(255,255,255),TextTransparency=0,FontFace=Font.new
'rbxasset://fonts/families/GothamSSm.json',TextSize=13,TextXAlignment='Left',
TextYAlignment='Center',Size=UDim2.new(1,-12,0,12),TextWrapped=true,
BackgroundTransparency=1,ThemeTag={TextColor3='Text'}})C.ContentLabel=y(
'TextLabel',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',Text=B.
Content,TextColor3=Color3.fromRGB(240,240,240),TextSize=14,TextXAlignment=Enum.
TextXAlignment.Left,AutomaticSize=Enum.AutomaticSize.Y,Size=UDim2.new(1,0,0,14),
BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,
TextWrapped=true,ThemeTag={TextColor3='Text'}})C.SubContentLabel=y('TextLabel',{
FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',Text=B.SubContent,
TextColor3=Color3.fromRGB(240,240,240),TextSize=14,TextXAlignment=Enum.
TextXAlignment.Left,AutomaticSize=Enum.AutomaticSize.Y,Size=UDim2.new(1,0,0,14),
BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,
TextWrapped=true,ThemeTag={TextColor3='SubText'}})C.LabelHolder=y('Frame',{
AutomaticSize=Enum.AutomaticSize.Y,BackgroundColor3=Color3.fromRGB(255,255,255),
BackgroundTransparency=1,Position=UDim2.fromOffset(14,40),Size=UDim2.new(1,-28,0
,0)},{y('UIListLayout',{SortOrder=Enum.SortOrder.LayoutOrder,VerticalAlignment=
Enum.VerticalAlignment.Center,Padding=UDim.new(0,3)}),C.ContentLabel,C.
SubContentLabel})C.CloseButton=y('TextButton',{Text='',Position=UDim2.new(1,-14,
0,13),Size=UDim2.fromOffset(20,20),AnchorPoint=Vector2.new(1,0),
BackgroundTransparency=1},{y('ImageLabel',{Image=p(o.Parent.Assets).Close,Size=
UDim2.fromOffset(16,16),Position=UDim2.fromScale(0.5,0.5),AnchorPoint=Vector2.
new(0.5,0.5),BackgroundTransparency=1,ThemeTag={ImageColor3='Text'}})})C.Root=y(
'Frame',{BackgroundTransparency=1,Size=UDim2.new(1,0,1,0),Position=UDim2.
fromScale(1,0)},{C.AcrylicPaint.Frame,C.Title,C.CloseButton,C.LabelHolder})if B.
Content==''then C.ContentLabel.Visible=false end if B.SubContent==''then C.
SubContentLabel.Visible=false end C.Holder=y('Frame',{BackgroundTransparency=1,
Size=UDim2.new(1,0,0,200),Parent=z.Holder},{C.Root})local D=t.GroupMotor.new{
Scale=1,Offset=60}D:onStep(function(E)C.Root.Position=UDim2.new(E.Scale,E.Offset
,0,0)end)u.AddSignal(C.CloseButton.MouseButton1Click,function()C:Close()end)
function C.Open(E)local F=C.LabelHolder.AbsoluteSize.Y C.Holder.Size=UDim2.new(1
,0,0,58+F)D:setGoal{Scale=w(0,{frequency=5}),Offset=w(0,{frequency=5})}end
function C.Close(E)if not C.Closed then C.Closed=true c.spawn(function()D:
setGoal{Scale=w(1,{frequency=5}),Offset=w(60,{frequency=5})}c.wait(0.4)if p(s).
UseAcrylic then C.AcrylicPaint.Model:Destroy()end C.Holder:Destroy()end)end end
C:Open()if B.Duration then c.delay(B.Duration,function()C:Close()end)end return
C end return z end,[13]=function()local n,o,p,q,r=m(13)local s=o.Parent.Parent
local t=p(s.Creator)local u=t.New return function(v,w)local x={}x.Layout=u(
'UIListLayout',{Padding=UDim.new(0,6)})x.Container=u('Frame',{Size=UDim2.new(1,0
,0,26),Position=UDim2.fromOffset(0,28),BackgroundTransparency=1},{x.Layout})x.
Root=u('Frame',{BackgroundTransparency=1,Size=UDim2.new(1,0,0,26),LayoutOrder=7,
Parent=w},{u('TextLabel',{RichText=true,Text=v,TextTransparency=0,FontFace=Font.
new('rbxassetid://12187365364',Enum.FontWeight.SemiBold,Enum.FontStyle.Normal),
TextSize=10,TextXAlignment='Left',TextYAlignment='Center',Size=UDim2.new(1,-16,0
,18),Position=UDim2.fromOffset(0,2),ThemeTag={TextColor3='SubText'}}),x.
Container})t.AddSignal(x.Layout:GetPropertyChangedSignal'AbsoluteContentSize',
function()x.Container.Size=UDim2.new(1,0,0,x.Layout.AbsoluteContentSize.Y)x.Root
.Size=UDim2.new(1,0,0,x.Layout.AbsoluteContentSize.Y+38)end)return x end end,[14
]=function()local n,o,p,q,r=m(14)local s=o.Parent.Parent local t,u=p(s.Packages.
Flipper),p(s.Creator)local v,w,x,y,z=u.New,t.Spring.new,t.Instant.new,s.
Components,{Window=nil,Tabs={},Containers={},SelectedTab=0,TabCount=0}function z
.Init(A,B)z.Window=B return z end function z.GetCurrentTabPos(A)local B,C=z.
Window.TabHolder.AbsolutePosition.Y,z.Tabs[z.SelectedTab].Frame.AbsolutePosition
.Y return C-B end function z.New(A,B,C,D)local E,F=p(s),z.Window local G=E.
Elements z.TabCount=z.TabCount+1 local H,I=z.TabCount,{Selected=false,Name=B,
Type='Tab'}if E:GetIcon(C)then C=E:GetIcon(C)end if C==''or nil then C=nil end I
.Frame=v('TextButton',{Size=UDim2.new(1,0,0,44),BackgroundTransparency=1,Parent=
D,ThemeTag={BackgroundColor3='Tab'}},{v('UICorner',{CornerRadius=UDim.new(0,9)})
,v('TextLabel',{AnchorPoint=Vector2.new(0,0.5),Position=C and UDim2.new(0,39,0.5
,0)or UDim2.new(0,12,0.5,0),Text=B,RichText=true,TextColor3=Color3.fromRGB(255,
255,255),TextTransparency=0,FontFace=Font.new(
'rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.Regular,Enum.
FontStyle.Normal),TextSize=13,TextXAlignment='Left',TextYAlignment='Center',Size
=UDim2.new(1,-12,1,0),BackgroundTransparency=1,ThemeTag={TextColor3='Text'}}),v(
'ImageLabel',{AnchorPoint=Vector2.new(0,0.5),Size=UDim2.fromOffset(18,18),
Position=UDim2.new(0,12,0.5,0),BackgroundTransparency=1,Image=C and C or nil,
ThemeTag={ImageColor3='Text'}})})local J=v('UIListLayout',{Padding=UDim.new(0,12
),SortOrder=Enum.SortOrder.LayoutOrder})I.ContainerFrame=v('ScrollingFrame',{
Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Parent=F.ContainerHolder,
Visible=false,BottomImage='rbxassetid://6889812791',MidImage=
'rbxassetid://6889812721',TopImage='rbxassetid://6276641225',
ScrollBarImageColor3=Color3.fromRGB(255,255,255),ScrollBarImageTransparency=0.65
,ScrollBarThickness=3,BorderSizePixel=0,CanvasSize=UDim2.fromScale(0,0),
ScrollingDirection=Enum.ScrollingDirection.Y},{J,v('UIPadding',{PaddingRight=
UDim.new(0,7),PaddingLeft=UDim.new(0,1),PaddingTop=UDim.new(0,1),PaddingBottom=
UDim.new(0,1)})})u.AddSignal(J:GetPropertyChangedSignal'AbsoluteContentSize',
function()I.ContainerFrame.CanvasSize=UDim2.new(0,0,0,J.AbsoluteContentSize.Y+2)
end)I.Motor,I.SetTransparency=u.SpringMotor(1,I.Frame,'BackgroundTransparency')u
.AddSignal(I.Frame.MouseEnter,function()I.SetTransparency(I.Selected and 0.85 or
0.89)end)u.AddSignal(I.Frame.MouseLeave,function()I.SetTransparency(I.Selected
and 0.89 or 1)end)u.AddSignal(I.Frame.MouseButton1Down,function()I.
SetTransparency(0.92)end)u.AddSignal(I.Frame.MouseButton1Up,function()I.
SetTransparency(I.Selected and 0.85 or 0.89)end)u.AddSignal(I.Frame.
MouseButton1Click,function()z:SelectTab(H)end)z.Containers[H]=I.ContainerFrame z
.Tabs[H]=I I.Container=I.ContainerFrame I.ScrollFrame=I.Container function I.
AddSection(K,L)local M,N={Type='Section'},p(y.Section)(L,I.Container)M.Container
=N.Container M.ScrollFrame=I.Container setmetatable(M,G)return M end
setmetatable(I,G)return I end function z.SelectTab(A,B)local C=z.Window z.
SelectedTab=B for D,E in next,z.Tabs do E.SetTransparency(1)E.Selected=false end
z.Tabs[B].SetTransparency(0.89)z.Tabs[B].Selected=true C.TabDisplay.Text=z.Tabs[
B].Name C.SelectorPosMotor:setGoal(w(z:GetCurrentTabPos(),{frequency=6}))c.
spawn(function()C.ContainerPosMotor:setGoal(w(156,{frequency=10}))C.
ContainerBackMotor:setGoal(w(1,{frequency=10}))c.wait(0.15)for D,E in next,z.
Containers do E.Visible=false end z.Containers[B].Visible=true C.
ContainerPosMotor:setGoal(w(140,{frequency=5}))C.ContainerBackMotor:setGoal(w(0,
{frequency=8}))end)end return z end,[15]=function()local n,o,p,q,r=m(15)local s,
t=game:GetService'TextService',o.Parent.Parent local u,v=p(t.Packages.Flipper),
p(t.Creator)local w=v.New return function(x,y)y=y or false local z={}z.Input=w(
'TextBox',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',
TextColor3=Color3.fromRGB(200,200,200),TextSize=14,TextXAlignment=Enum.
TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,BackgroundColor3=
Color3.fromRGB(255,255,255),AutomaticSize=Enum.AutomaticSize.Y,
BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Position=UDim2.fromOffset(10,
0),ThemeTag={TextColor3='Text',PlaceholderColor3='SubText'}})z.Container=w(
'Frame',{BackgroundTransparency=1,ClipsDescendants=true,Position=UDim2.new(0,6,0
,0),Size=UDim2.new(1,-12,1,0)},{z.Input})z.Indicator=w('Frame',{Size=UDim2.new(1
,-4,0,1),Position=UDim2.new(0,2,1,0),AnchorPoint=Vector2.new(0,1),
BackgroundTransparency=y and 0.5 or 0,ThemeTag={BackgroundColor3=y and
'InputIndicator'or'DialogInputLine'}})z.Frame=w('Frame',{Size=UDim2.new(0,0,0,30
),BackgroundTransparency=y and 0.9 or 0,Parent=x,ThemeTag={BackgroundColor3=y
and'Input'or'DialogInput'}},{w('UICorner',{CornerRadius=UDim.new(0,4)}),w(
'UIStroke',{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Transparency=y and 0.5
or 0.65,ThemeTag={Color=y and'InElementBorder'or'DialogButtonBorder'}}),z.
Indicator,z.Container})local A=function()local A,B=2,z.Container.AbsoluteSize.X
if not z.Input:IsFocused()or z.Input.TextBounds.X<=B-2*A then z.Input.Position=
UDim2.new(0,A,0,0)else local C=z.Input.CursorPosition if C~=-1 then local D=
string.sub(z.Input.Text,1,C-1)local E=s:GetTextSize(D,z.Input.TextSize,z.Input.
Font,Vector2.new(math.huge,math.huge)).X local F=z.Input.Position.X.Offset+E if
F<A then z.Input.Position=UDim2.fromOffset(A-E,0)elseif F>B-A-1 then z.Input.
Position=UDim2.fromOffset(B-E-A-1,0)end end end end c.spawn(A)v.AddSignal(z.
Input:GetPropertyChangedSignal'Text',A)v.AddSignal(z.Input:
GetPropertyChangedSignal'CursorPosition',A)v.AddSignal(z.Input.Focused,function(
)A()z.Indicator.Size=UDim2.new(1,-2,0,2)z.Indicator.Position=UDim2.new(0,1,1,0)z
.Indicator.BackgroundTransparency=0 v.OverrideTag(z.Frame,{BackgroundColor3=y
and'InputFocused'or'DialogHolder'})v.OverrideTag(z.Indicator,{BackgroundColor3=
'Accent'})end)v.AddSignal(z.Input.FocusLost,function()A()z.Indicator.Size=UDim2.
new(1,-4,0,1)z.Indicator.Position=UDim2.new(0,2,1,0)z.Indicator.
BackgroundTransparency=0.5 v.OverrideTag(z.Frame,{BackgroundColor3=y and'Input'
or'DialogInput'})v.OverrideTag(z.Indicator,{BackgroundColor3=y and
'InputIndicator'or'DialogInputLine'})end)return z end end,[16]=function()local n
,o,p,q,r=m(16)local s,t=o.Parent.Parent,p(o.Parent.Assets)local u,v=p(s.Creator)
,p(s.Packages.Flipper)local w,x=u.New,u.AddSignal return function(y)local z,A,B=
{},p(s),function(z,A,B,C)local D={Callback=C or function()end}D.Frame=w(
'TextButton',{Size=UDim2.new(0,34,1,-8),AnchorPoint=Vector2.new(1,0),
BackgroundTransparency=1,Parent=B,Position=A,Text='',ThemeTag={BackgroundColor3=
'Text'}},{w('UICorner',{CornerRadius=UDim.new(0,7)}),w('ImageLabel',{Image=z,
Size=UDim2.fromOffset(16,16),Position=UDim2.fromScale(0.5,0.5),AnchorPoint=
Vector2.new(0.5,0.5),BackgroundTransparency=1,Name='Icon',ThemeTag={ImageColor3=
'Text'}})})local E,F=u.SpringMotor(1,D.Frame,'BackgroundTransparency')x(D.Frame.
MouseEnter,function()F(0.94)end)x(D.Frame.MouseLeave,function()F(1,true)end)x(D.
Frame.MouseButton1Down,function()F(0.96)end)x(D.Frame.MouseButton1Up,function()
F(0.94)end)x(D.Frame.MouseButton1Click,D.Callback)D.SetCallback=function(G)D.
Callback=G end return D end z.Frame=w('Frame',{Size=UDim2.new(1,0,0,57),
BackgroundTransparency=1,Parent=y.Parent},{w('Frame',{Size=UDim2.new(1,-16,1,0),
Position=UDim2.new(0,16,0,0),BackgroundTransparency=1},{w('UIListLayout',{
Padding=UDim.new(0,5),FillDirection=Enum.FillDirection.Horizontal,SortOrder=Enum
.SortOrder.LayoutOrder}),w('TextLabel',{RichText=true,Text=y.Title,FontFace=Font
.new('rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.Regular,Enum.
FontStyle.Normal),TextSize=12,TextXAlignment='Left',TextYAlignment='Center',Size
=UDim2.fromScale(0,1),AutomaticSize=Enum.AutomaticSize.X,BackgroundTransparency=
1,ThemeTag={TextColor3='Text'}}),w('TextLabel',{RichText=true,Text=y.SubTitle,
TextTransparency=0.4,FontFace=Font.new(
'rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.Regular,Enum.
FontStyle.Normal),TextSize=12,TextXAlignment='Left',TextYAlignment='Center',Size
=UDim2.fromScale(0,1),AutomaticSize=Enum.AutomaticSize.X,BackgroundTransparency=
1,ThemeTag={TextColor3='Text'}})}),w('Frame',{BackgroundTransparency=0.5,Size=
UDim2.new(1,0,0,1),Position=UDim2.new(0,0,1,0),ThemeTag={BackgroundColor3=
'TitleBarLine'}})})z.CloseButton=B(t.Close,UDim2.new(1,-4,0,4),z.Frame,function(
)A.Window:Dialog{Title='Close',Content=
'Are you sure you want to unload the interface?',Buttons={{Title='Yes',Callback=
function()A:Destroy()end},{Title='No'}}}end)z.MaxButton=B(t.Max,UDim2.new(1,-40,
0,4),z.Frame,function()y.Window.Maximize(not y.Window.Maximized)end)z.MinButton=
B(t.Min,UDim2.new(1,-80,0,4),z.Frame,function()A.Window:Minimize()end)return z
end end,[17]=function()local n,o,p,q,r=m(17)local s,t,u,v=game:GetService
'UserInputService',game:GetService'Players'.LocalPlayer:GetMouse(),game:
GetService'Workspace'.CurrentCamera,o.Parent.Parent local w,x,y,z,A=p(v.Packages
.Flipper),p(v.Creator),p(v.Acrylic),p(o.Parent.Assets),o.Parent local B,C,D=w.
Spring.new,w.Instant.new,x.New return function(E)local F,G,H,I,J,K=p(v),{
Minimized=false,Maximized=false,Size=E.Size,CurrentPos=0,Position=UDim2.
fromOffset(u.ViewportSize.X/2-E.Size.X.Offset/2,u.ViewportSize.Y/2-E.Size.Y.
Offset/2)},false local L,M=false local N=false G.AcrylicPaint=y.AcrylicPaint()
local O,P=D('Frame',{Size=UDim2.fromOffset(4,0),BackgroundColor3=Color3.fromRGB(
76,194,255),Position=UDim2.fromOffset(0,17),AnchorPoint=Vector2.new(0,0.5),
ThemeTag={BackgroundColor3='Accent'}},{D('UICorner',{CornerRadius=UDim.new(0,2)}
)}),D('Frame',{Size=UDim2.fromOffset(20,20),BackgroundTransparency=1,Position=
UDim2.new(1,-20,1,-20)})G.TabHolder=D('ScrollingFrame',{Size=UDim2.fromScale(1,1
),BackgroundTransparency=1,ScrollBarImageTransparency=1,ScrollBarThickness=0,
BorderSizePixel=0,CanvasSize=UDim2.fromScale(0,0),ScrollingDirection=Enum.
ScrollingDirection.Y},{D('UIListLayout',{Padding=UDim.new(0,4)})})local Q=D(
'Frame',{Size=UDim2.new(0,E.TabWidth,1,-202),Position=UDim2.new(0,12,0,103),
ZIndex=2,BackgroundTransparency=1,ClipsDescendants=true},{G.TabHolder,O})G.
TabDisplay=D('TextLabel',{RichText=true,Text='Tab',TextTransparency=0,FontFace=
Font.new('rbxassetid://12187365364',Enum.FontWeight.SemiBold,Enum.FontStyle.
Normal),TextSize=27,TextXAlignment='Left',TextYAlignment='Center',Size=UDim2.
new(1,-E.TabWidth-70,0,34),Position=UDim2.fromOffset(E.TabWidth+47,96),
BackgroundTransparency=1,ThemeTag={TextColor3='Text'}})G.ContainerHolder=D(
'CanvasGroup',{Size=UDim2.new(1,-E.TabWidth-68,1,-160),Position=UDim2.
fromOffset(E.TabWidth+47,140),ZIndex=2,BackgroundTransparency=1})G.Root=D(
'Frame',{BackgroundTransparency=1,Size=G.Size,Position=G.Position,Parent=E.
Parent},{G.AcrylicPaint.Frame,G.TabDisplay,G.ContainerHolder,Q,P})G.TitleBar=p(o
.Parent.TitleBar){Title=E.Title,SubTitle=E.SubTitle,Parent=G.Root,Window=G}if p(
v).UseAcrylic then G.AcrylicPaint.AddParent(G.Root)end local R,S=w.GroupMotor.
new{X=G.Size.X.Offset,Y=G.Size.Y.Offset},w.GroupMotor.new{X=G.Position.X.Offset,
Y=G.Position.Y.Offset}G.SelectorPosMotor=w.SingleMotor.new(17)G.
SelectorSizeMotor=w.SingleMotor.new(0)G.ContainerBackMotor=w.SingleMotor.new(0)G
.ContainerPosMotor=w.SingleMotor.new(140)R:onStep(function(T)G.Root.Size=UDim2.
new(0,T.X,0,T.Y)end)S:onStep(function(T)G.Root.Position=UDim2.new(0,T.X,0,T.Y)
end)local T,U=0,0 G.SelectorPosMotor:onStep(function(V)O.Position=UDim2.new(0,0,
0,V+22)local W=tick()local X=W-U if T~=nil then G.SelectorSizeMotor:setGoal(B((
math.abs(V-T)/(X*60))+16))T=V end U=W end)G.SelectorSizeMotor:onStep(function(V)
O.Size=UDim2.new(0,4,0,V)end)G.ContainerBackMotor:onStep(function(V)G.
ContainerHolder.GroupTransparency=V end)G.ContainerPosMotor:onStep(function(V)G.
ContainerHolder.Position=UDim2.fromOffset(E.TabWidth+47,V)end)local V,W G.
Maximize=function(X,Y,Z)G.Maximized=X G.TitleBar.MaxButton.Frame.Icon.Image=X
and z.Restore or z.Max if X then V=G.Size.X.Offset W=G.Size.Y.Offset end local _
,aa=X and u.ViewportSize.X or V,X and u.ViewportSize.Y or W R:setGoal{X=w[Z and
'Instant'or'Spring'].new(_,{frequency=6}),Y=w[Z and'Instant'or'Spring'].new(aa,{
frequency=6})}G.Size=UDim2.fromOffset(_,aa)if not Y then S:setGoal{X=B(X and 0
or G.Position.X.Offset,{frequency=6}),Y=B(X and 0 or G.Position.Y.Offset,{
frequency=6})}end end x.AddSignal(G.TitleBar.Frame.InputBegan,function(aa)if aa.
UserInputType==Enum.UserInputType.MouseButton1 or aa.UserInputType==Enum.
UserInputType.Touch then H=true J=aa.Position K=G.Root.Position if G.Maximized
then K=UDim2.fromOffset(t.X-(t.X*((V-100)/G.Root.AbsoluteSize.X)),t.Y-(t.Y*(W/G.
Root.AbsoluteSize.Y)))end aa.Changed:Connect(function()if aa.UserInputState==
Enum.UserInputState.End then H=false end end)end end)x.AddSignal(G.TitleBar.
Frame.InputChanged,function(aa)if aa.UserInputType==Enum.UserInputType.
MouseMovement or aa.UserInputType==Enum.UserInputType.Touch then I=aa end end)x.
AddSignal(P.InputBegan,function(aa)if aa.UserInputType==Enum.UserInputType.
MouseButton1 or aa.UserInputType==Enum.UserInputType.Touch then L=true M=aa.
Position end end)x.AddSignal(s.InputChanged,function(aa)if aa==I and H then
local X=aa.Position-J G.Position=UDim2.fromOffset(K.X.Offset+X.X,K.Y.Offset+X.Y)
S:setGoal{X=C(G.Position.X.Offset),Y=C(G.Position.Y.Offset)}if G.Maximized then
G.Maximize(false,true,true)end end if(aa.UserInputType==Enum.UserInputType.
MouseMovement or aa.UserInputType==Enum.UserInputType.Touch)and L then local X,Y
=aa.Position-M,G.Size local Z=Vector3.new(Y.X.Offset,Y.Y.Offset,0)+Vector3.new(1
,1,0)*X local _=Vector2.new(math.clamp(Z.X,470,2048),math.clamp(Z.Y,380,2048))R:
setGoal{X=w.Instant.new(_.X),Y=w.Instant.new(_.Y)}end end)x.AddSignal(s.
InputEnded,function(aa)if L==true or aa.UserInputType==Enum.UserInputType.Touch
then L=false G.Size=UDim2.fromOffset(R:getValue().X,R:getValue().Y)end end)x.
AddSignal(G.TabHolder.UIListLayout:GetPropertyChangedSignal'AbsoluteContentSize'
,function()G.TabHolder.CanvasSize=UDim2.new(0,0,0,G.TabHolder.UIListLayout.
AbsoluteContentSize.Y)end)x.AddSignal(s.InputBegan,function(aa)if type(F.
MinimizeKeybind)=='table'and F.MinimizeKeybind.Type=='Keybind'and not s:
GetFocusedTextBox()then if aa.KeyCode.Name==F.MinimizeKeybind.Value then G:
Minimize()end elseif aa.KeyCode==F.MinimizeKey and not s:GetFocusedTextBox()then
G:Minimize()end end)function G.Minimize(aa)G.Minimized=not G.Minimized G.Root.
Visible=not G.Minimized if not N then N=true local X=F.MinimizeKeybind and F.
MinimizeKeybind.Value or F.MinimizeKey.Name F:Notify{Title='Interface',Content=
'Press '..X..' to toggle the inteface.',Duration=6}end end function G.Destroy(aa
)if p(v).UseAcrylic then G.AcrylicPaint.Model:Destroy()end G.Root:Destroy()end
local aa=p(A.Dialog):Init(G)function G.Dialog(X,Y)local Z=aa:Create()Z.Title.
Text=Y.Title local _=D('TextLabel',{FontFace=Font.new
'rbxasset://fonts/families/GothamSSm.json',Text=Y.Content,TextColor3=Color3.
fromRGB(240,240,240),TextSize=14,TextXAlignment=Enum.TextXAlignment.Left,
TextYAlignment=Enum.TextYAlignment.Top,Size=UDim2.new(1,-40,1,0),Position=UDim2.
fromOffset(20,60),BackgroundTransparency=1,Parent=Z.Root,ClipsDescendants=false,
ThemeTag={TextColor3='Text'}})D('UISizeConstraint',{MinSize=Vector2.new(300,165)
,MaxSize=Vector2.new(620,math.huge),Parent=Z.Root})Z.Root.Size=UDim2.fromOffset(
_.TextBounds.X+40,165)if _.TextBounds.X+40>G.Size.X.Offset-120 then Z.Root.Size=
UDim2.fromOffset(G.Size.X.Offset-120,165)_.TextWrapped=true Z.Root.Size=UDim2.
fromOffset(G.Size.X.Offset-120,_.TextBounds.Y+150)end for ab,ac in next,Y.
Buttons do Z:Button(ac.Title,ac.Callback)end Z:Open()end local ab=p(A.Tab):Init(
G)function G.AddTab(ac,X)return ab:New(X.Title,X.Icon,G.TabHolder)end function G
.SelectTab(ac,X)ab:SelectTab(X or 1)end x.AddSignal(G.TabHolder:
GetPropertyChangedSignal'CanvasPosition',function()T=ab:GetCurrentTabPos()+16 U=
0 G.SelectorPosMotor:setGoal(C(ab:GetCurrentTabPos()))end)return G end end,[18]=
function()local aa,ab,ac,n,o=m(18)local p=ab.Parent local q,r,s=ac(p.Themes),ac(
p.Packages.Flipper),{Registry={},Signals={},TransparencyMotors={},
DefaultProperties={ScreenGui={ResetOnSpawn=false,ZIndexBehavior=Enum.
ZIndexBehavior.Sibling},Frame={BackgroundColor3=Color3.new(1,1,1),BorderColor3=
Color3.new(0,0,0),BorderSizePixel=0},ScrollingFrame={BackgroundColor3=Color3.
new(1,1,1),BorderColor3=Color3.new(0,0,0),ScrollBarImageColor3=Color3.new(0,0,0)
},TextLabel={BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),
Font=Enum.Font.SourceSans,Text='',TextColor3=Color3.new(0,0,0),
BackgroundTransparency=1,TextSize=14},TextButton={BackgroundColor3=Color3.new(1,
1,1),BorderColor3=Color3.new(0,0,0),AutoButtonColor=false,Font=Enum.Font.
SourceSans,Text='',TextColor3=Color3.new(0,0,0),TextSize=14},TextBox={
BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),
ClearTextOnFocus=false,Font=Enum.Font.SourceSans,Text='',TextColor3=Color3.new(0
,0,0),TextSize=14},ImageLabel={BackgroundTransparency=1,BackgroundColor3=Color3.
new(1,1,1),BorderColor3=Color3.new(0,0,0),BorderSizePixel=0},ImageButton={
BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),
AutoButtonColor=false},CanvasGroup={BackgroundColor3=Color3.new(1,1,1),
BorderColor3=Color3.new(0,0,0),BorderSizePixel=0}}}local t=function(t,u)if u.
ThemeTag then s.AddThemeObject(t,u.ThemeTag)end end function s.AddSignal(u,v)
table.insert(s.Signals,u:Connect(v))end function s.Disconnect()for u=#s.Signals,
1,-1 do local v=table.remove(s.Signals,u)v:Disconnect()end end function s.
GetThemeProperty(u)if q[ac(p).Theme][u]then return q[ac(p).Theme][u]end return q
.Dark[u]end function s.UpdateTheme()for u,v in next,s.Registry do for w,x in
next,v.Properties do u[w]=s.GetThemeProperty(x)end end for u,v in next,s.
TransparencyMotors do v:setGoal(r.Instant.new(s.GetThemeProperty
'ElementTransparency'))end end function s.AddThemeObject(u,v)local w=#s.Registry
+1 local x={Object=u,Properties=v,Idx=w}s.Registry[u]=x s.UpdateTheme()return u
end function s.OverrideTag(u,v)s.Registry[u].Properties=v s.UpdateTheme()end
function s.New(u,v,w)local x=Instance.new(u)for y,z in next,s.DefaultProperties[
u]or{}do x[y]=z end for y,z in next,v or{}do if y~='ThemeTag'then x[y]=z end end
for y,z in next,w or{}do z.Parent=x end t(x,v)return x end function s.
SpringMotor(u,v,w,x,y)x=x or false y=y or false local z=r.SingleMotor.new(u)z:
onStep(function(A)v[w]=A end)if y then table.insert(s.TransparencyMotors,z)end
local A=function(A,B)B=B or false if not x then if not B then if w==
'BackgroundTransparency'and ac(p).DialogOpen then return end end end z:setGoal(r
.Spring.new(A,{frequency=8}))end return z,A end return s end,[19]=function()
local aa,ab,ac,n,o=m(19)local p={}for q,r in next,ab:GetChildren()do table.
insert(p,ac(r))end return p end,[20]=function()local aa,ab,ac,n,o=m(20)local p=
ab.Parent.Parent local q=ac(p.Creator)local r,s,t=q.New,p.Components,{}t.__index
=t t.__type='Button'function t.New(u,v)assert(v.Title,'Button - Missing Title')v
.Callback=v.Callback or function()end local w=ac(s.Element)(v.Title,v.
Description,u.Container,true)local x=r('ImageLabel',{Image=
'rbxassetid://10709791437',Size=UDim2.fromOffset(16,16),AnchorPoint=Vector2.new(
1,0.5),Position=UDim2.new(1,-10,0.5,0),BackgroundTransparency=1,Parent=w.Frame,
ThemeTag={ImageColor3='Text'}})q.AddSignal(w.Frame.MouseButton1Click,function()u
.Library:SafeCallback(v.Callback)end)return w end return t end,[21]=function()
local aa,ab,ac,n,o=m(21)local p,q,r,s=game:GetService'UserInputService',game:
GetService'TouchInputService',game:GetService'RunService',game:GetService
'Players'local t,u=r.RenderStepped,s.LocalPlayer local v,w=u:GetMouse(),ab.
Parent.Parent local x=ac(w.Creator)local y,z,A=x.New,w.Components,{}A.__index=A
A.__type='Colorpicker'function A.New(B,C,D)local E=B.Library assert(D.Title,
'Colorpicker - Missing Title')assert(D.Default,
'AddColorPicker: Missing default value.')local F={Value=D.Default,Transparency=D
.Transparency or 0,Type='Colorpicker',Title=type(D.Title)=='string'and D.Title
or'Colorpicker',Callback=D.Callback or function(F)end}function F.SetHSVFromRGB(G
,H)local I,J,K=Color3.toHSV(H)F.Hue=I F.Sat=J F.Vib=K end F:SetHSVFromRGB(F.
Value)local G=ac(z.Element)(D.Title,D.Description,B.Container,true)F.SetTitle=G.
SetTitle F.SetDesc=G.SetDesc local H=y('Frame',{Size=UDim2.fromScale(1,1),
BackgroundColor3=F.Value,Parent=G.Frame},{y('UICorner',{CornerRadius=UDim.new(0,
4)})})local ad,ae=y('ImageLabel',{Size=UDim2.fromOffset(26,26),Position=UDim2.
new(1,-10,0.5,0),AnchorPoint=Vector2.new(1,0.5),Parent=G.Frame,Image=
'http://www.roblox.com/asset/?id=14204231522',ImageTransparency=0.45,ScaleType=
Enum.ScaleType.Tile,TileSize=UDim2.fromOffset(40,40)},{y('UICorner',{
CornerRadius=UDim.new(0,4)}),H}),function()local I=ac(z.Dialog):Create()I.Title.
Text=F.Title I.Root.Size=UDim2.fromOffset(430,330)local J,K,L,M,N,O=F.Hue,F.Sat,
F.Vib,F.Transparency,function()local J=ac(z.Textbox)()J.Frame.Parent=I.Root J.
Frame.Size=UDim2.new(0,90,0,32)return J end,function(J,K)return y('TextLabel',{
FontFace=Font.new('rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.
Medium,Enum.FontStyle.Normal),Text=J,TextColor3=Color3.fromRGB(240,240,240),
TextSize=13,TextXAlignment=Enum.TextXAlignment.Left,Size=UDim2.new(1,0,0,32),
Position=K,BackgroundTransparency=1,Parent=I.Root,ThemeTag={TextColor3='Text'}})
end local P,Q=function()local P=Color3.fromHSV(J,K,L)return{R=math.floor(P.r*255
),G=math.floor(P.g*255),B=math.floor(P.b*255)}end,y('ImageLabel',{Size=UDim2.
new(0,18,0,18),ScaleType=Enum.ScaleType.Fit,AnchorPoint=Vector2.new(0.5,0.5),
BackgroundTransparency=1,Image='http://www.roblox.com/asset/?id=4805639000'})
local R,S=y('ImageLabel',{Size=UDim2.fromOffset(180,160),Position=UDim2.
fromOffset(20,55),Image='rbxassetid://4155801252',BackgroundColor3=F.Value,
BackgroundTransparency=0,Parent=I.Root},{y('UICorner',{CornerRadius=UDim.new(0,4
)}),Q}),y('Frame',{BackgroundColor3=F.Value,Size=UDim2.fromScale(1,1),
BackgroundTransparency=F.Transparency},{y('UICorner',{CornerRadius=UDim.new(0,4)
})})local T,U=y('ImageLabel',{Image=
'http://www.roblox.com/asset/?id=14204231522',ImageTransparency=0.45,ScaleType=
Enum.ScaleType.Tile,TileSize=UDim2.fromOffset(40,40),BackgroundTransparency=1,
Position=UDim2.fromOffset(112,220),Size=UDim2.fromOffset(88,24),Parent=I.Root},{
y('UICorner',{CornerRadius=UDim.new(0,4)}),y('UIStroke',{Thickness=2,
Transparency=0.75}),S}),y('Frame',{BackgroundColor3=F.Value,Size=UDim2.
fromScale(1,1),BackgroundTransparency=0},{y('UICorner',{CornerRadius=UDim.new(0,
4)})})local V,W=y('ImageLabel',{Image=
'http://www.roblox.com/asset/?id=14204231522',ImageTransparency=0.45,ScaleType=
Enum.ScaleType.Tile,TileSize=UDim2.fromOffset(40,40),BackgroundTransparency=1,
Position=UDim2.fromOffset(20,220),Size=UDim2.fromOffset(88,24),Parent=I.Root},{
y('UICorner',{CornerRadius=UDim.new(0,4)}),y('UIStroke',{Thickness=2,
Transparency=0.75}),U}),{}for X=0,1,0.1 do table.insert(W,ColorSequenceKeypoint.
new(X,Color3.fromHSV(X,1,1)))end local X,Y=y('UIGradient',{Color=ColorSequence.
new(W),Rotation=90}),y('Frame',{Size=UDim2.new(1,0,1,-10),Position=UDim2.
fromOffset(0,5),BackgroundTransparency=1})local Z,_,ad=y('ImageLabel',{Size=
UDim2.fromOffset(14,14),Image='http://www.roblox.com/asset/?id=12266946128',
Parent=Y,ThemeTag={ImageColor3='DialogInput'}}),y('Frame',{Size=UDim2.
fromOffset(12,190),Position=UDim2.fromOffset(210,55),Parent=I.Root},{y(
'UICorner',{CornerRadius=UDim.new(1,0)}),X,Y}),N()ad.Frame.Position=UDim2.
fromOffset(D.Transparency and 260 or 240,55)O('Hex',UDim2.fromOffset(D.
Transparency and 360 or 340,55))local ae=N()ae.Frame.Position=UDim2.fromOffset(D
.Transparency and 260 or 240,95)O('Red',UDim2.fromOffset(D.Transparency and 360
or 340,95))local af=N()af.Frame.Position=UDim2.fromOffset(D.Transparency and 260
or 240,135)O('Green',UDim2.fromOffset(D.Transparency and 360 or 340,135))local
ag=N()ag.Frame.Position=UDim2.fromOffset(D.Transparency and 260 or 240,175)O(
'Blue',UDim2.fromOffset(D.Transparency and 360 or 340,175))local ah if D.
Transparency then ah=N()ah.Frame.Position=UDim2.fromOffset(260,215)O('Alpha',
UDim2.fromOffset(360,215))end local ai,aj,ak if D.Transparency then local al=y(
'Frame',{Size=UDim2.new(1,0,1,-10),Position=UDim2.fromOffset(0,5),
BackgroundTransparency=1})aj=y('ImageLabel',{Size=UDim2.fromOffset(14,14),Image=
'http://www.roblox.com/asset/?id=12266946128',Parent=al,ThemeTag={ImageColor3=
'DialogInput'}})ak=y('Frame',{Size=UDim2.fromScale(1,1)},{y('UIGradient',{
Transparency=NumberSequence.new{NumberSequenceKeypoint.new(0,0),
NumberSequenceKeypoint.new(1,1)},Rotation=270}),y('UICorner',{CornerRadius=UDim.
new(1,0)})})ai=y('Frame',{Size=UDim2.fromOffset(12,190),Position=UDim2.
fromOffset(230,55),Parent=I.Root,BackgroundTransparency=1},{y('UICorner',{
CornerRadius=UDim.new(1,0)}),y('ImageLabel',{Image=
'http://www.roblox.com/asset/?id=14204231522',ImageTransparency=0.45,ScaleType=
Enum.ScaleType.Tile,TileSize=UDim2.fromOffset(40,40),BackgroundTransparency=1,
Size=UDim2.fromScale(1,1),Parent=I.Root},{y('UICorner',{CornerRadius=UDim.new(1,
0)})}),ak,al})end local al=function()R.BackgroundColor3=Color3.fromHSV(J,1,1)Z.
Position=UDim2.new(0,-1,J,-6)Q.Position=UDim2.new(K,0,1-L,0)U.BackgroundColor3=
Color3.fromHSV(J,K,L)ad.Input.Text='#'..Color3.fromHSV(J,K,L):ToHex()ae.Input.
Text=P().R af.Input.Text=P().G ag.Input.Text=P().B if D.Transparency then ak.
BackgroundColor3=Color3.fromHSV(J,K,L)U.BackgroundTransparency=M aj.Position=
UDim2.new(0,-1,1-M,-6)ah.Input.Text=ac(w):Round((1-M)*100,0)..'%'end end x.
AddSignal(ad.Input.FocusLost,function(am)if am then local an,ao=pcall(Color3.
fromHex,ad.Input.Text)if an and typeof(ao)=='Color3'then J,K,L=Color3.toHSV(ao)
end end al()end)x.AddSignal(ae.Input.FocusLost,function(am)if am then local an=
P()local ao,ap=pcall(Color3.fromRGB,ae.Input.Text,an.G,an.B)if ao and typeof(ap)
=='Color3'then if tonumber(ae.Input.Text)<=255 then J,K,L=Color3.toHSV(ap)end
end end al()end)x.AddSignal(af.Input.FocusLost,function(am)if am then local an=
P()local ao,ap=pcall(Color3.fromRGB,an.R,af.Input.Text,an.B)if ao and typeof(ap)
=='Color3'then if tonumber(af.Input.Text)<=255 then J,K,L=Color3.toHSV(ap)end
end end al()end)x.AddSignal(ag.Input.FocusLost,function(am)if am then local an=
P()local ao,ap=pcall(Color3.fromRGB,an.R,an.G,ag.Input.Text)if ao and typeof(ap)
=='Color3'then if tonumber(ag.Input.Text)<=255 then J,K,L=Color3.toHSV(ap)end
end end al()end)if D.Transparency then x.AddSignal(ah.Input.FocusLost,function(
am)if am then pcall(function()local an=tonumber(ah.Input.Text)if an>=0 and an<=
100 then M=1-an*0.01 end end)end al()end)end x.AddSignal(R.InputBegan,function(
am)if am.UserInputType==Enum.UserInputType.MouseButton1 or am.UserInputType==
Enum.UserInputType.Touch then while p:IsMouseButtonPressed(Enum.UserInputType.
MouseButton1)do local an=R.AbsolutePosition.X local ao=an+R.AbsoluteSize.X local
ap,aq=math.clamp(v.X,an,ao),R.AbsolutePosition.Y local ar=aq+R.AbsoluteSize.Y
local as=math.clamp(v.Y,aq,ar)K=(ap-an)/(ao-an)L=1-((as-aq)/(ar-aq))al()t:Wait()
end end end)x.AddSignal(_.InputBegan,function(am)if am.UserInputType==Enum.
UserInputType.MouseButton1 or am.UserInputType==Enum.UserInputType.Touch then
while p:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)do local an=_.
AbsolutePosition.Y local ao=an+_.AbsoluteSize.Y local ap=math.clamp(v.Y,an,ao)J=
((ap-an)/(ao-an))al()t:Wait()end end end)if D.Transparency then x.AddSignal(ai.
InputBegan,function(am)if am.UserInputType==Enum.UserInputType.MouseButton1 then
while p:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)do local an=ai.
AbsolutePosition.Y local ao=an+ai.AbsoluteSize.Y local ap=math.clamp(v.Y,an,ao)M
=1-((ap-an)/(ao-an))al()t:Wait()end end end)end al()I:Button('Done',function()F:
SetValue({J,K,L},M)end)I:Button'Cancel'I:Open()end function F.Display(af)F.Value
=Color3.fromHSV(F.Hue,F.Sat,F.Vib)H.BackgroundColor3=F.Value H.
BackgroundTransparency=F.Transparency A.Library:SafeCallback(F.Callback,F.Value)
A.Library:SafeCallback(F.Changed,F.Value)end function F.SetValue(af,ag,ah)local
ai=Color3.fromHSV(ag[1],ag[2],ag[3])F.Transparency=ah or 0 F:SetHSVFromRGB(ai)F:
Display()end function F.SetValueRGB(af,ag,ah)F.Transparency=ah or 0 F:
SetHSVFromRGB(ag)F:Display()end function F.OnChanged(af,ag)F.Changed=ag ag(F.
Value)end function F.Destroy(af)G:Destroy()E.Options[C]=nil end x.AddSignal(G.
Frame.MouseButton1Click,function()ae()end)F:Display()E.Options[C]=F return F end
return A end,[22]=function()local aa,ab,ac,ad,ae=m(22)local af,ag,ah,ai,aj=game:
GetService'TweenService',game:GetService'UserInputService',game:GetService
'Players'.LocalPlayer:GetMouse(),game:GetService'Workspace'.CurrentCamera,ab.
Parent.Parent local ak,al=ac(aj.Creator),ac(aj.Packages.Flipper)local am,an,ao=
ak.New,aj.Components,{}ao.__index=ao ao.__type='Dropdown'function ao.New(ap,aq,
ar)local as,n,o=ap.Library,{Values=ar.Values,Value=ar.Default,Multi=ar.Multi,
Buttons={},Opened=false,Type='Dropdown',Callback=ar.Callback or function()end},
ac(an.Element)(ar.Title,ar.Description,ap.Container,false)o.DescLabel.Size=UDim2
.new(1,-170,0,14)n.SetTitle=o.SetTitle n.SetDesc=o.SetDesc local p,q=am(
'TextLabel',{FontFace=Font.new('rbxasset://fonts/families/GothamSSm.json',Enum.
FontWeight.Regular,Enum.FontStyle.Normal),Text='Value',TextColor3=Color3.
fromRGB(240,240,240),TextSize=13,TextXAlignment=Enum.TextXAlignment.Left,Size=
UDim2.new(1,-30,0,14),Position=UDim2.new(0,8,0.5,0),AnchorPoint=Vector2.new(0,
0.5),BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,
TextTruncate=Enum.TextTruncate.AtEnd,ThemeTag={TextColor3='Text'}}),am(
'ImageLabel',{Image='rbxassetid://10709790948',Size=UDim2.fromOffset(16,16),
AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,-8,0.5,0),
BackgroundTransparency=1,ThemeTag={ImageColor3='SubText'}})local r,s=am(
'TextButton',{Size=UDim2.fromOffset(160,30),Position=UDim2.new(1,-10,0.5,0),
AnchorPoint=Vector2.new(1,0.5),BackgroundTransparency=0.9,Parent=o.Frame,
ThemeTag={BackgroundColor3='DropdownFrame'}},{am('UICorner',{CornerRadius=UDim.
new(0,5)}),am('UIStroke',{Transparency=0.5,ApplyStrokeMode=Enum.ApplyStrokeMode.
Border,ThemeTag={Color='InElementBorder'}}),q,p}),am('UIListLayout',{Padding=
UDim.new(0,3)})local t=am('ScrollingFrame',{Size=UDim2.new(1,-5,1,-10),Position=
UDim2.fromOffset(5,5),BackgroundTransparency=1,BottomImage=
'rbxassetid://6889812791',MidImage='rbxassetid://6889812721',TopImage=
'rbxassetid://6276641225',ScrollBarImageColor3=Color3.fromRGB(255,255,255),
ScrollBarImageTransparency=0.95,ScrollBarThickness=4,BorderSizePixel=0,
CanvasSize=UDim2.fromScale(0,0)},{s})local u=am('Frame',{Size=UDim2.fromScale(1,
0.6),ThemeTag={BackgroundColor3='DropdownHolder'}},{t,am('UICorner',{
CornerRadius=UDim.new(0,7)}),am('UIStroke',{ApplyStrokeMode=Enum.ApplyStrokeMode
.Border,ThemeTag={Color='DropdownBorder'}}),am('ImageLabel',{
BackgroundTransparency=1,Image='http://www.roblox.com/asset/?id=5554236805',
ScaleType=Enum.ScaleType.Slice,SliceCenter=Rect.new(23,23,277,277),Size=UDim2.
fromScale(1,1)+UDim2.fromOffset(30,30),Position=UDim2.fromOffset(-15,-15),
ImageColor3=Color3.fromRGB(0,0,0),ImageTransparency=0.1})})local v=am('Frame',{
BackgroundTransparency=1,Size=UDim2.fromOffset(170,300),Parent=ap.Library.GUI,
Visible=false},{u,am('UISizeConstraint',{MinSize=Vector2.new(170,0)})})table.
insert(as.OpenFrames,v)local w,x=function()local w=0 if ai.ViewportSize.Y-r.
AbsolutePosition.Y<v.AbsoluteSize.Y-5 then w=v.AbsoluteSize.Y-5-(ai.ViewportSize
.Y-r.AbsolutePosition.Y)+40 end v.Position=UDim2.fromOffset(r.AbsolutePosition.X
-1,r.AbsolutePosition.Y-5-w)end,0 local y,z=function()if#n.Values>10 then v.Size
=UDim2.fromOffset(x,392)else v.Size=UDim2.fromOffset(x,s.AbsoluteContentSize.Y+
10)end end,function()t.CanvasSize=UDim2.fromOffset(0,s.AbsoluteContentSize.Y)end
w()y()ak.AddSignal(r:GetPropertyChangedSignal'AbsolutePosition',w)ak.AddSignal(r
.MouseButton1Click,function()n:Open()end)ak.AddSignal(ag.InputBegan,function(A)
if A.UserInputType==Enum.UserInputType.MouseButton1 or A.UserInputType==Enum.
UserInputType.Touch then local B,C=u.AbsolutePosition,u.AbsoluteSize if ah.X<B.X
or ah.X>B.X+C.X or ah.Y<(B.Y-20-1)or ah.Y>B.Y+C.Y then n:Close()end end end)
local A=ap.ScrollFrame function n.Open(B)n.Opened=true A.ScrollingEnabled=false
v.Visible=true af:Create(u,TweenInfo.new(0.2,Enum.EasingStyle.Quart,Enum.
EasingDirection.Out),{Size=UDim2.fromScale(1,1)}):Play()end function n.Close(B)n
.Opened=false A.ScrollingEnabled=true u.Size=UDim2.fromScale(1,0.6)v.Visible=
false end function n.Display(B)local C,D=n.Values,''if ar.Multi then for E,F in
next,C do if n.Value[F]then D=D..F..', 'end end D=D:sub(1,#D-2)else D=n.Value or
''end p.Text=(D==''and'--'or D)end function n.GetActiveValues(B)if ar.Multi then
local C={}for D,E in next,n.Value do table.insert(C,D)end return C else return n
.Value and 1 or 0 end end function n.BuildDropdownList(B)local C,D=n.Values,{}
for E,F in next,t:GetChildren()do if not F:IsA'UIListLayout'then F:Destroy()end
end local E=0 for F,G in next,C do local H={}E=E+1 local I,J=am('Frame',{Size=
UDim2.fromOffset(4,14),BackgroundColor3=Color3.fromRGB(76,194,255),Position=
UDim2.fromOffset(-1,16),AnchorPoint=Vector2.new(0,0.5),ThemeTag={
BackgroundColor3='Accent'}},{am('UICorner',{CornerRadius=UDim.new(0,2)})}),am(
'TextLabel',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',Text=G,
TextColor3=Color3.fromRGB(200,200,200),TextSize=13,TextXAlignment=Enum.
TextXAlignment.Left,BackgroundColor3=Color3.fromRGB(255,255,255),AutomaticSize=
Enum.AutomaticSize.Y,BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Position
=UDim2.fromOffset(10,0),Name='ButtonLabel',ThemeTag={TextColor3='Text'}})local K
,L=(am('TextButton',{Size=UDim2.new(1,-5,0,32),BackgroundTransparency=1,ZIndex=
23,Text='',Parent=t,ThemeTag={BackgroundColor3='DropdownOption'}},{I,J,am(
'UICorner',{CornerRadius=UDim.new(0,6)})}))if ar.Multi then L=n.Value[G]else L=n
.Value==G end local M,N=ak.SpringMotor(1,K,'BackgroundTransparency')local O,P=ak
.SpringMotor(1,I,'BackgroundTransparency')local Q=al.SingleMotor.new(6)Q:onStep(
function(R)I.Size=UDim2.new(0,4,0,R)end)ak.AddSignal(K.MouseEnter,function()N(L
and 0.85 or 0.89)end)ak.AddSignal(K.MouseLeave,function()N(L and 0.89 or 1)end)
ak.AddSignal(K.MouseButton1Down,function()N(0.92)end)ak.AddSignal(K.
MouseButton1Up,function()N(L and 0.85 or 0.89)end)function H.UpdateButton(R)if
ar.Multi then L=n.Value[G]if L then N(0.89)end else L=n.Value==G N(L and 0.89 or
1)end Q:setGoal(al.Spring.new(L and 14 or 6,{frequency=6}))P(L and 0 or 1)end J.
InputBegan:Connect(function(R)if R.UserInputType==Enum.UserInputType.
MouseButton1 or R.UserInputType==Enum.UserInputType.Touch then local S=not L if
n:GetActiveValues()==1 and not S and not ar.AllowNull then else if ar.Multi then
L=S n.Value[G]=L and true or nil else L=S n.Value=L and G or nil for T,U in next
,D do U:UpdateButton()end end H:UpdateButton()n:Display()as:SafeCallback(n.
Callback,n.Value)as:SafeCallback(n.Changed,n.Value)end end end)H:UpdateButton()n
:Display()D[K]=H end x=0 for F,G in next,D do if F.ButtonLabel then if F.
ButtonLabel.TextBounds.X>x then x=F.ButtonLabel.TextBounds.X end end end x=x+30
z()y()end function n.SetValues(B,C)if C then n.Values=C end n:BuildDropdownList(
)end function n.OnChanged(B,C)n.Changed=C C(n.Value)end function n.SetValue(B,C)
if n.Multi then local D={}for E,F in next,C do if table.find(n.Values,E)then D[E
]=true end end n.Value=D else if not C then n.Value=nil elseif table.find(n.
Values,C)then n.Value=C end end n:BuildDropdownList()as:SafeCallback(n.Callback,
n.Value)as:SafeCallback(n.Changed,n.Value)end function n.Destroy(B)o:Destroy()as
.Options[aq]=nil end n:BuildDropdownList()n:Display()local B={}if type(ar.
Default)=='string'then local C=table.find(n.Values,ar.Default)if C then table.
insert(B,C)end elseif type(ar.Default)=='table'then for C,D in next,ar.Default
do local E=table.find(n.Values,D)if E then table.insert(B,E)end end elseif type(
ar.Default)=='number'and n.Values[ar.Default]~=nil then table.insert(B,ar.
Default)end if next(B)then for C=1,#B do local D=B[C]if ar.Multi then n.Value[n.
Values[D] ]=true else n.Value=n.Values[D]end if not ar.Multi then break end end
n:BuildDropdownList()n:Display()end as.Options[aq]=n return n end return ao end,
[23]=function()local aa,ab,ac,ad,ae=m(23)local af=ab.Parent.Parent local ag=ac(
af.Creator)local ah,ai,aj,ak=ag.New,ag.AddSignal,af.Components,{}ak.__index=ak
ak.__type='Input'function ak.New(al,am,an)local ao=al.Library assert(an.Title,
'Input - Missing Title')an.Callback=an.Callback or function()end local ap,aq={
Value=an.Default or'',Numeric=an.Numeric or false,Finished=an.Finished or false,
Callback=an.Callback or function(ap)end,Type='Input'},ac(aj.Element)(an.Title,an
.Description,al.Container,false)ap.SetTitle=aq.SetTitle ap.SetDesc=aq.SetDesc
local ar=ac(aj.Textbox)(aq.Frame,true)ar.Frame.Position=UDim2.new(1,-10,0.5,0)ar
.Frame.AnchorPoint=Vector2.new(1,0.5)ar.Frame.Size=UDim2.fromOffset(160,30)ar.
Input.Text=an.Default or''ar.Input.PlaceholderText=an.Placeholder or''local as=
ar.Input function ap.SetValue(n,o)if an.MaxLength and#o>an.MaxLength then o=o:
sub(1,an.MaxLength)end if ap.Numeric then if(not tonumber(o))and o:len()>0 then
o=ap.Value end end ap.Value=o as.Text=o ao:SafeCallback(ap.Callback,ap.Value)ao:
SafeCallback(ap.Changed,ap.Value)end if ap.Finished then ai(as.FocusLost,
function(n)if not n then return end ap:SetValue(as.Text)end)else ai(as:
GetPropertyChangedSignal'Text',function()ap:SetValue(as.Text)end)end function ap
.OnChanged(n,o)ap.Changed=o o(ap.Value)end function ap.Destroy(n)aq:Destroy()ao.
Options[am]=nil end ao.Options[am]=ap return ap end return ak end,[24]=function(
)local aa,ab,ac,ad,ae=m(24)local af,ag=game:GetService'UserInputService',ab.
Parent.Parent local ah=ac(ag.Creator)local ai,aj,ak=ah.New,ag.Components,{}ak.
__index=ak ak.__type='Keybind'function ak.New(al,am,an)local ao=al.Library
assert(an.Title,'KeyBind - Missing Title')assert(an.Default,
'KeyBind - Missing default value.')local ap,aq,ar={Value=an.Default,Toggled=
false,Mode=an.Mode or'Toggle',Type='Keybind',Callback=an.Callback or function(ap
)end,ChangedCallback=an.ChangedCallback or function(ap)end},false,ac(aj.Element
)(an.Title,an.Description,al.Container,true)ap.SetTitle=ar.SetTitle ap.SetDesc=
ar.SetDesc local as=ai('TextLabel',{FontFace=Font.new(
'rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.Regular,Enum.
FontStyle.Normal),Text=an.Default,TextColor3=Color3.fromRGB(240,240,240),
TextSize=13,TextXAlignment=Enum.TextXAlignment.Center,Size=UDim2.new(0,0,0,14),
Position=UDim2.new(0,0,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=
Color3.fromRGB(255,255,255),AutomaticSize=Enum.AutomaticSize.X,
BackgroundTransparency=1,ThemeTag={TextColor3='Text'}})local n=ai('TextButton',{
Size=UDim2.fromOffset(0,30),Position=UDim2.new(1,-10,0.5,0),AnchorPoint=Vector2.
new(1,0.5),BackgroundTransparency=0.9,Parent=ar.Frame,AutomaticSize=Enum.
AutomaticSize.X,ThemeTag={BackgroundColor3='Keybind'}},{ai('UICorner',{
CornerRadius=UDim.new(0,5)}),ai('UIPadding',{PaddingLeft=UDim.new(0,8),
PaddingRight=UDim.new(0,8)}),ai('UIStroke',{Transparency=0.5,ApplyStrokeMode=
Enum.ApplyStrokeMode.Border,ThemeTag={Color='InElementBorder'}}),as})function ap
.GetState(o)if af:GetFocusedTextBox()and ap.Mode~='Always'then return false end
if ap.Mode=='Always'then return true elseif ap.Mode=='Hold'then if ap.Value==
'None'then return false end local p=ap.Value if p=='MouseLeft'or p=='MouseRight'
then return p=='MouseLeft'and af:IsMouseButtonPressed(Enum.UserInputType.
MouseButton1)or p=='MouseRight'and af:IsMouseButtonPressed(Enum.UserInputType.
MouseButton2)else return af:IsKeyDown(Enum.KeyCode[ap.Value])end else return ap.
Toggled end end function ap.SetValue(o,p,q)p=p or ap.Key q=q or ap.Mode as.Text=
p ap.Value=p ap.Mode=q end function ap.OnClick(o,p)ap.Clicked=p end function ap.
OnChanged(o,p)ap.Changed=p p(ap.Value)end function ap.DoClick(o)ao:SafeCallback(
ap.Callback,ap.Toggled)ao:SafeCallback(ap.Clicked,ap.Toggled)end function ap.
Destroy(o)ar:Destroy()ao.Options[am]=nil end ah.AddSignal(n.InputBegan,function(
o)if o.UserInputType==Enum.UserInputType.MouseButton1 or o.UserInputType==Enum.
UserInputType.Touch then aq=true as.Text='...'wait(0.2)local p p=af.InputBegan:
Connect(function(q)local r if q.UserInputType==Enum.UserInputType.Keyboard then
r=q.KeyCode.Name elseif q.UserInputType==Enum.UserInputType.MouseButton1 then r=
'MouseLeft'elseif q.UserInputType==Enum.UserInputType.MouseButton2 then r=
'MouseRight'end local s s=af.InputEnded:Connect(function(t)if t.KeyCode.Name==r
or r=='MouseLeft'and t.UserInputType==Enum.UserInputType.MouseButton1 or r==
'MouseRight'and t.UserInputType==Enum.UserInputType.MouseButton2 then aq=false
as.Text=r ap.Value=r ao:SafeCallback(ap.ChangedCallback,t.KeyCode or t.
UserInputType)ao:SafeCallback(ap.Changed,t.KeyCode or t.UserInputType)p:
Disconnect()s:Disconnect()end end)end)end end)ah.AddSignal(af.InputBegan,
function(o)if not aq and not af:GetFocusedTextBox()then if ap.Mode=='Toggle'then
local p=ap.Value if p=='MouseLeft'or p=='MouseRight'then if p=='MouseLeft'and o.
UserInputType==Enum.UserInputType.MouseButton1 or p=='MouseRight'and o.
UserInputType==Enum.UserInputType.MouseButton2 then ap.Toggled=not ap.Toggled ap
:DoClick()end elseif o.UserInputType==Enum.UserInputType.Keyboard then if o.
KeyCode.Name==p then ap.Toggled=not ap.Toggled ap:DoClick()end end end end end)
ao.Options[am]=ap return ap end return ak end,[25]=function()local aa,ab,ac,ad,
ae=m(25)local af=ab.Parent.Parent local ag,ah,ai,aj=af.Components,ac(af.Packages
.Flipper),ac(af.Creator),{}aj.__index=aj aj.__type='Paragraph'function aj.New(ak
,al)assert(al.Title,'Paragraph - Missing Title')al.Content=al.Content or''local
am=ac(ag.Element)(al.Title,al.Content,aj.Container,false)am.Frame.
BackgroundTransparency=0.92 am.Border.Transparency=0.6 return am end return aj
end,[26]=function()local aa,ab,ac,ad,ae=m(26)local af,ag=game:GetService
'UserInputService',ab.Parent.Parent local ah=ac(ag.Creator)local ai,aj,ak=ah.New
,ag.Components,{}ak.__index=ak ak.__type='Slider'function ak.New(al,am,an)local
ao=al.Library assert(an.Title,'Slider - Missing Title.')assert(an.Default,
'Slider - Missing default value.')assert(an.Min,
'Slider - Missing minimum value.')assert(an.Max,
'Slider - Missing maximum value.')assert(an.Rounding,
'Slider - Missing rounding value.')local ap,aq,ar={Value=nil,Min=an.Min,Max=an.
Max,Rounding=an.Rounding,Callback=an.Callback or function(ap)end,Type='Slider'},
false,ac(aj.Element)(an.Title,an.Description,al.Container,false)ar.DescLabel.
Size=UDim2.new(1,-170,0,14)ap.SetTitle=ar.SetTitle ap.SetDesc=ar.SetDesc local
as=ai('ImageLabel',{AnchorPoint=Vector2.new(0,0.5),Position=UDim2.new(0,-7,0.5,0
),Size=UDim2.fromOffset(14,14),Image=
'http://www.roblox.com/asset/?id=12266946128',ThemeTag={ImageColor3='Accent'}})
local n,o,p=ai('Frame',{BackgroundTransparency=1,Position=UDim2.fromOffset(7,0),
Size=UDim2.new(1,-14,1,0)},{as}),ai('Frame',{Size=UDim2.new(0,0,1,0),ThemeTag={
BackgroundColor3='Accent'}},{ai('UICorner',{CornerRadius=UDim.new(1,0)})}),ai(
'TextLabel',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',Text=
'Value',TextSize=12,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Right,
BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,Size=UDim2
.new(0,100,0,14),Position=UDim2.new(0,-4,0.5,0),AnchorPoint=Vector2.new(1,0.5),
ThemeTag={TextColor3='SubText'}})local q=ai('Frame',{Size=UDim2.new(1,0,0,4),
AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,-10,0.5,0),
BackgroundTransparency=0.4,Parent=ar.Frame,ThemeTag={BackgroundColor3=
'SliderRail'}},{ai('UICorner',{CornerRadius=UDim.new(1,0)}),ai(
'UISizeConstraint',{MaxSize=Vector2.new(150,math.huge)}),p,o,n})ah.AddSignal(as.
InputBegan,function(r)if r.UserInputType==Enum.UserInputType.MouseButton1 or r.
UserInputType==Enum.UserInputType.Touch then aq=true end end)ah.AddSignal(as.
InputEnded,function(r)if r.UserInputType==Enum.UserInputType.MouseButton1 or r.
UserInputType==Enum.UserInputType.Touch then aq=false end end)ah.AddSignal(af.
InputChanged,function(r)if aq and(r.UserInputType==Enum.UserInputType.
MouseMovement or r.UserInputType==Enum.UserInputType.Touch)then local s=math.
clamp((r.Position.X-n.AbsolutePosition.X)/n.AbsoluteSize.X,0,1)ap:SetValue(ap.
Min+((ap.Max-ap.Min)*s))end end)function ap.OnChanged(r,s)ap.Changed=s s(ap.
Value)end function ap.SetValue(r,s)r.Value=ao:Round(math.clamp(s,ap.Min,ap.Max),
ap.Rounding)as.Position=UDim2.new((r.Value-ap.Min)/(ap.Max-ap.Min),-7,0.5,0)o.
Size=UDim2.fromScale((r.Value-ap.Min)/(ap.Max-ap.Min),1)p.Text=tostring(r.Value)
ao:SafeCallback(ap.Callback,r.Value)ao:SafeCallback(ap.Changed,r.Value)end
function ap.Destroy(r)ar:Destroy()ao.Options[am]=nil end ap:SetValue(an.Default)
ao.Options[am]=ap return ap end return ak end,[27]=function()local aa,ab,ac,ad,
ae=m(27)local af,ag=game:GetService'TweenService',ab.Parent.Parent local ah=ac(
ag.Creator)local ai,aj,ak=ah.New,ag.Components,{}ak.__index=ak ak.__type=
'Toggle'function ak.New(al,am,an)local ao=al.Library assert(an.Title,
'Toggle - Missing Title')local ap,aq={Value=an.Default or false,Callback=an.
Callback or function(ap)end,Type='Toggle'},ac(aj.Element)(an.Title,an.
Description,al.Container,true)aq.DescLabel.Size=UDim2.new(1,-54,0,14)ap.SetTitle
=aq.SetTitle ap.SetDesc=aq.SetDesc local ar,as=ai('ImageLabel',{AnchorPoint=
Vector2.new(0,0.5),Size=UDim2.fromOffset(14,14),Position=UDim2.new(0,2,0.5,0),
Image='http://www.roblox.com/asset/?id=12266946128',ImageTransparency=0.5,
ThemeTag={ImageColor3='ToggleSlider'}}),ai('UIStroke',{Transparency=0.5,ThemeTag
={Color='ToggleSlider'}})local n=ai('Frame',{Size=UDim2.fromOffset(36,18),
AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,-10,0.5,0),Parent=aq.Frame,
BackgroundTransparency=1,ThemeTag={BackgroundColor3='Accent'}},{ai('UICorner',{
CornerRadius=UDim.new(0,9)}),as,ar})function ap.OnChanged(o,p)ap.Changed=p p(ap.
Value)end function ap.SetValue(o,p)p=not not p ap.Value=p ah.OverrideTag(as,{
Color=ap.Value and'Accent'or'ToggleSlider'})ah.OverrideTag(ar,{ImageColor3=ap.
Value and'ToggleToggled'or'ToggleSlider'})af:Create(ar,TweenInfo.new(0.25,Enum.
EasingStyle.Quint,Enum.EasingDirection.Out),{Position=UDim2.new(0,ap.Value and
19 or 2,0.5,0)}):Play()af:Create(n,TweenInfo.new(0.25,Enum.EasingStyle.Quint,
Enum.EasingDirection.Out),{BackgroundTransparency=ap.Value and 0 or 1}):Play()ar
.ImageTransparency=ap.Value and 0 or 0.5 ao:SafeCallback(ap.Callback,ap.Value)ao
:SafeCallback(ap.Changed,ap.Value)end function ap.Destroy(o)aq:Destroy()ao.
Options[am]=nil end ah.AddSignal(aq.Frame.MouseButton1Click,function()ap:
SetValue(not ap.Value)end)ap:SetValue(ap.Value)ao.Options[am]=ap return ap end
return ak end,[28]=function()local aa,ab,ac,ad,ae=m(28)return{assets={[
'lucide-accessibility']='rbxassetid://10709751939',['lucide-activity']=
'rbxassetid://10709752035',['lucide-air-vent']='rbxassetid://10709752131',[
'lucide-airplay']='rbxassetid://10709752254',['lucide-alarm-check']=
'rbxassetid://10709752405',['lucide-alarm-clock']='rbxassetid://10709752630',[
'lucide-alarm-clock-off']='rbxassetid://10709752508',['lucide-alarm-minus']=
'rbxassetid://10709752732',['lucide-alarm-plus']='rbxassetid://10709752825',[
'lucide-album']='rbxassetid://10709752906',['lucide-alert-circle']=
'rbxassetid://10709752996',['lucide-alert-octagon']='rbxassetid://10709753064',[
'lucide-alert-triangle']='rbxassetid://10709753149',['lucide-align-center']=
'rbxassetid://10709753570',['lucide-align-center-horizontal']=
'rbxassetid://10709753272',['lucide-align-center-vertical']=
'rbxassetid://10709753421',['lucide-align-end-horizontal']=
'rbxassetid://10709753692',['lucide-align-end-vertical']=
'rbxassetid://10709753808',['lucide-align-horizontal-distribute-center']=
'rbxassetid://10747779791',['lucide-align-horizontal-distribute-end']=
'rbxassetid://10747784534',['lucide-align-horizontal-distribute-start']=
'rbxassetid://10709754118',['lucide-align-horizontal-justify-center']=
'rbxassetid://10709754204',['lucide-align-horizontal-justify-end']=
'rbxassetid://10709754317',['lucide-align-horizontal-justify-start']=
'rbxassetid://10709754436',['lucide-align-horizontal-space-around']=
'rbxassetid://10709754590',['lucide-align-horizontal-space-between']=
'rbxassetid://10709754749',['lucide-align-justify']='rbxassetid://10709759610',[
'lucide-align-left']='rbxassetid://10709759764',['lucide-align-right']=
'rbxassetid://10709759895',['lucide-align-start-horizontal']=
'rbxassetid://10709760051',['lucide-align-start-vertical']=
'rbxassetid://10709760244',['lucide-align-vertical-distribute-center']=
'rbxassetid://10709760351',['lucide-align-vertical-distribute-end']=
'rbxassetid://10709760434',['lucide-align-vertical-distribute-start']=
'rbxassetid://10709760612',['lucide-align-vertical-justify-center']=
'rbxassetid://10709760814',['lucide-align-vertical-justify-end']=
'rbxassetid://10709761003',['lucide-align-vertical-justify-start']=
'rbxassetid://10709761176',['lucide-align-vertical-space-around']=
'rbxassetid://10709761324',['lucide-align-vertical-space-between']=
'rbxassetid://10709761434',['lucide-anchor']='rbxassetid://10709761530',[
'lucide-angry']='rbxassetid://10709761629',['lucide-annoyed']=
'rbxassetid://10709761722',['lucide-aperture']='rbxassetid://10709761813',[
'lucide-apple']='rbxassetid://10709761889',['lucide-archive']=
'rbxassetid://10709762233',['lucide-archive-restore']='rbxassetid://10709762058'
,['lucide-armchair']='rbxassetid://10709762327',['lucide-arrow-big-down']=
'rbxassetid://10747796644',['lucide-arrow-big-left']='rbxassetid://10709762574',
['lucide-arrow-big-right']='rbxassetid://10709762727',['lucide-arrow-big-up']=
'rbxassetid://10709762879',['lucide-arrow-down']='rbxassetid://10709767827',[
'lucide-arrow-down-circle']='rbxassetid://10709763034',['lucide-arrow-down-left'
]='rbxassetid://10709767656',['lucide-arrow-down-right']=
'rbxassetid://10709767750',['lucide-arrow-left']='rbxassetid://10709768114',[
'lucide-arrow-left-circle']='rbxassetid://10709767936',[
'lucide-arrow-left-right']='rbxassetid://10709768019',['lucide-arrow-right']=
'rbxassetid://10709768347',['lucide-arrow-right-circle']=
'rbxassetid://10709768226',['lucide-arrow-up']='rbxassetid://10709768939',[
'lucide-arrow-up-circle']='rbxassetid://10709768432',['lucide-arrow-up-down']=
'rbxassetid://10709768538',['lucide-arrow-up-left']='rbxassetid://10709768661',[
'lucide-arrow-up-right']='rbxassetid://10709768787',['lucide-asterisk']=
'rbxassetid://10709769095',['lucide-at-sign']='rbxassetid://10709769286',[
'lucide-award']='rbxassetid://10709769406',['lucide-axe']=
'rbxassetid://10709769508',['lucide-axis-3d']='rbxassetid://10709769598',[
'lucide-baby']='rbxassetid://10709769732',['lucide-backpack']=
'rbxassetid://10709769841',['lucide-baggage-claim']='rbxassetid://10709769935',[
'lucide-banana']='rbxassetid://10709770005',['lucide-banknote']=
'rbxassetid://10709770178',['lucide-bar-chart']='rbxassetid://10709773755',[
'lucide-bar-chart-2']='rbxassetid://10709770317',['lucide-bar-chart-3']=
'rbxassetid://10709770431',['lucide-bar-chart-4']='rbxassetid://10709770560',[
'lucide-bar-chart-horizontal']='rbxassetid://10709773669',['lucide-barcode']=
'rbxassetid://10747360675',['lucide-baseline']='rbxassetid://10709773863',[
'lucide-bath']='rbxassetid://10709773963',['lucide-battery']=
'rbxassetid://10709774640',['lucide-battery-charging']=
'rbxassetid://10709774068',['lucide-battery-full']='rbxassetid://10709774206',[
'lucide-battery-low']='rbxassetid://10709774370',['lucide-battery-medium']=
'rbxassetid://10709774513',['lucide-beaker']='rbxassetid://10709774756',[
'lucide-bed']='rbxassetid://10709775036',['lucide-bed-double']=
'rbxassetid://10709774864',['lucide-bed-single']='rbxassetid://10709774968',[
'lucide-beer']='rbxassetid://10709775167',['lucide-bell']=
'rbxassetid://10709775704',['lucide-bell-minus']='rbxassetid://10709775241',[
'lucide-bell-off']='rbxassetid://10709775320',['lucide-bell-plus']=
'rbxassetid://10709775448',['lucide-bell-ring']='rbxassetid://10709775560',[
'lucide-bike']='rbxassetid://10709775894',['lucide-binary']=
'rbxassetid://10709776050',['lucide-bitcoin']='rbxassetid://10709776126',[
'lucide-bluetooth']='rbxassetid://10709776655',['lucide-bluetooth-connected']=
'rbxassetid://10709776240',['lucide-bluetooth-off']='rbxassetid://10709776344',[
'lucide-bluetooth-searching']='rbxassetid://10709776501',['lucide-bold']=
'rbxassetid://10747813908',['lucide-bomb']='rbxassetid://10709781460',[
'lucide-bone']='rbxassetid://10709781605',['lucide-book']=
'rbxassetid://10709781824',['lucide-book-open']='rbxassetid://10709781717',[
'lucide-bookmark']='rbxassetid://10709782154',['lucide-bookmark-minus']=
'rbxassetid://10709781919',['lucide-bookmark-plus']='rbxassetid://10709782044',[
'lucide-bot']='rbxassetid://10709782230',['lucide-box']=
'rbxassetid://10709782497',['lucide-box-select']='rbxassetid://10709782342',[
'lucide-boxes']='rbxassetid://10709782582',['lucide-briefcase']=
'rbxassetid://10709782662',['lucide-brush']='rbxassetid://10709782758',[
'lucide-bug']='rbxassetid://10709782845',['lucide-building']=
'rbxassetid://10709783051',['lucide-building-2']='rbxassetid://10709782939',[
'lucide-bus']='rbxassetid://10709783137',['lucide-cake']=
'rbxassetid://10709783217',['lucide-calculator']='rbxassetid://10709783311',[
'lucide-calendar']='rbxassetid://10709789505',['lucide-calendar-check']=
'rbxassetid://10709783474',['lucide-calendar-check-2']=
'rbxassetid://10709783392',['lucide-calendar-clock']='rbxassetid://10709783577',
['lucide-calendar-days']='rbxassetid://10709783673',['lucide-calendar-heart']=
'rbxassetid://10709783835',['lucide-calendar-minus']='rbxassetid://10709783959',
['lucide-calendar-off']='rbxassetid://10709788784',['lucide-calendar-plus']=
'rbxassetid://10709788937',['lucide-calendar-range']='rbxassetid://10709789053',
['lucide-calendar-search']='rbxassetid://10709789200',['lucide-calendar-x']=
'rbxassetid://10709789407',['lucide-calendar-x-2']='rbxassetid://10709789329',[
'lucide-camera']='rbxassetid://10709789686',['lucide-camera-off']=
'rbxassetid://10747822677',['lucide-car']='rbxassetid://10709789810',[
'lucide-carrot']='rbxassetid://10709789960',['lucide-cast']=
'rbxassetid://10709790097',['lucide-charge']='rbxassetid://10709790202',[
'lucide-check']='rbxassetid://10709790644',['lucide-check-circle']=
'rbxassetid://10709790387',['lucide-check-circle-2']='rbxassetid://10709790298',
['lucide-check-square']='rbxassetid://10709790537',['lucide-chef-hat']=
'rbxassetid://10709790757',['lucide-cherry']='rbxassetid://10709790875',[
'lucide-chevron-down']='rbxassetid://10709790948',['lucide-chevron-first']=
'rbxassetid://10709791015',['lucide-chevron-last']='rbxassetid://10709791130',[
'lucide-chevron-left']='rbxassetid://10709791281',['lucide-chevron-right']=
'rbxassetid://10709791437',['lucide-chevron-up']='rbxassetid://10709791523',[
'lucide-chevrons-down']='rbxassetid://10709796864',['lucide-chevrons-down-up']=
'rbxassetid://10709791632',['lucide-chevrons-left']='rbxassetid://10709797151',[
'lucide-chevrons-left-right']='rbxassetid://10709797006',[
'lucide-chevrons-right']='rbxassetid://10709797382',[
'lucide-chevrons-right-left']='rbxassetid://10709797274',['lucide-chevrons-up']=
'rbxassetid://10709797622',['lucide-chevrons-up-down']=
'rbxassetid://10709797508',['lucide-chrome']='rbxassetid://10709797725',[
'lucide-circle']='rbxassetid://10709798174',['lucide-circle-dot']=
'rbxassetid://10709797837',['lucide-circle-ellipsis']='rbxassetid://10709797985'
,['lucide-circle-slashed']='rbxassetid://10709798100',['lucide-citrus']=
'rbxassetid://10709798276',['lucide-clapperboard']='rbxassetid://10709798350',[
'lucide-clipboard']='rbxassetid://10709799288',['lucide-clipboard-check']=
'rbxassetid://10709798443',['lucide-clipboard-copy']='rbxassetid://10709798574',
['lucide-clipboard-edit']='rbxassetid://10709798682',['lucide-clipboard-list']=
'rbxassetid://10709798792',['lucide-clipboard-signature']=
'rbxassetid://10709798890',['lucide-clipboard-type']='rbxassetid://10709798999',
['lucide-clipboard-x']='rbxassetid://10709799124',['lucide-clock']=
'rbxassetid://10709805144',['lucide-clock-1']='rbxassetid://10709799535',[
'lucide-clock-10']='rbxassetid://10709799718',['lucide-clock-11']=
'rbxassetid://10709799818',['lucide-clock-12']='rbxassetid://10709799962',[
'lucide-clock-2']='rbxassetid://10709803876',['lucide-clock-3']=
'rbxassetid://10709803989',['lucide-clock-4']='rbxassetid://10709804164',[
'lucide-clock-5']='rbxassetid://10709804291',['lucide-clock-6']=
'rbxassetid://10709804435',['lucide-clock-7']='rbxassetid://10709804599',[
'lucide-clock-8']='rbxassetid://10709804784',['lucide-clock-9']=
'rbxassetid://10709804996',['lucide-cloud']='rbxassetid://10709806740',[
'lucide-cloud-cog']='rbxassetid://10709805262',['lucide-cloud-drizzle']=
'rbxassetid://10709805371',['lucide-cloud-fog']='rbxassetid://10709805477',[
'lucide-cloud-hail']='rbxassetid://10709805596',['lucide-cloud-lightning']=
'rbxassetid://10709805727',['lucide-cloud-moon']='rbxassetid://10709805942',[
'lucide-cloud-moon-rain']='rbxassetid://10709805838',['lucide-cloud-off']=
'rbxassetid://10709806060',['lucide-cloud-rain']='rbxassetid://10709806277',[
'lucide-cloud-rain-wind']='rbxassetid://10709806166',['lucide-cloud-snow']=
'rbxassetid://10709806374',['lucide-cloud-sun']='rbxassetid://10709806631',[
'lucide-cloud-sun-rain']='rbxassetid://10709806475',['lucide-cloudy']=
'rbxassetid://10709806859',['lucide-clover']='rbxassetid://10709806995',[
'lucide-code']='rbxassetid://10709810463',['lucide-code-2']=
'rbxassetid://10709807111',['lucide-codepen']='rbxassetid://10709810534',[
'lucide-codesandbox']='rbxassetid://10709810676',['lucide-coffee']=
'rbxassetid://10709810814',['lucide-cog']='rbxassetid://10709810948',[
'lucide-coins']='rbxassetid://10709811110',['lucide-columns']=
'rbxassetid://10709811261',['lucide-command']='rbxassetid://10709811365',[
'lucide-compass']='rbxassetid://10709811445',['lucide-component']=
'rbxassetid://10709811595',['lucide-concierge-bell']='rbxassetid://10709811706',
['lucide-connection']='rbxassetid://10747361219',['lucide-contact']=
'rbxassetid://10709811834',['lucide-contrast']='rbxassetid://10709811939',[
'lucide-cookie']='rbxassetid://10709812067',['lucide-copy']=
'rbxassetid://10709812159',['lucide-copyleft']='rbxassetid://10709812251',[
'lucide-copyright']='rbxassetid://10709812311',['lucide-corner-down-left']=
'rbxassetid://10709812396',['lucide-corner-down-right']=
'rbxassetid://10709812485',['lucide-corner-left-down']=
'rbxassetid://10709812632',['lucide-corner-left-up']='rbxassetid://10709812784',
['lucide-corner-right-down']='rbxassetid://10709812939',[
'lucide-corner-right-up']='rbxassetid://10709813094',['lucide-corner-up-left']=
'rbxassetid://10709813185',['lucide-corner-up-right']='rbxassetid://10709813281'
,['lucide-cpu']='rbxassetid://10709813383',['lucide-croissant']=
'rbxassetid://10709818125',['lucide-crop']='rbxassetid://10709818245',[
'lucide-cross']='rbxassetid://10709818399',['lucide-crosshair']=
'rbxassetid://10709818534',['lucide-crown']='rbxassetid://10709818626',[
'lucide-cup-soda']='rbxassetid://10709818763',['lucide-curly-braces']=
'rbxassetid://10709818847',['lucide-currency']='rbxassetid://10709818931',[
'lucide-database']='rbxassetid://10709818996',['lucide-delete']=
'rbxassetid://10709819059',['lucide-diamond']='rbxassetid://10709819149',[
'lucide-dice-1']='rbxassetid://10709819266',['lucide-dice-2']=
'rbxassetid://10709819361',['lucide-dice-3']='rbxassetid://10709819508',[
'lucide-dice-4']='rbxassetid://10709819670',['lucide-dice-5']=
'rbxassetid://10709819801',['lucide-dice-6']='rbxassetid://10709819896',[
'lucide-dices']='rbxassetid://10723343321',['lucide-diff']=
'rbxassetid://10723343416',['lucide-disc']='rbxassetid://10723343537',[
'lucide-divide']='rbxassetid://10723343805',['lucide-divide-circle']=
'rbxassetid://10723343636',['lucide-divide-square']='rbxassetid://10723343737',[
'lucide-dollar-sign']='rbxassetid://10723343958',['lucide-download']=
'rbxassetid://10723344270',['lucide-download-cloud']='rbxassetid://10723344088',
['lucide-droplet']='rbxassetid://10723344432',['lucide-droplets']=
'rbxassetid://10734883356',['lucide-drumstick']='rbxassetid://10723344737',[
'lucide-edit']='rbxassetid://10734883598',['lucide-edit-2']=
'rbxassetid://10723344885',['lucide-edit-3']='rbxassetid://10723345088',[
'lucide-egg']='rbxassetid://10723345518',['lucide-egg-fried']=
'rbxassetid://10723345347',['lucide-electricity']='rbxassetid://10723345749',[
'lucide-electricity-off']='rbxassetid://10723345643',['lucide-equal']=
'rbxassetid://10723345990',['lucide-equal-not']='rbxassetid://10723345866',[
'lucide-eraser']='rbxassetid://10723346158',['lucide-euro']=
'rbxassetid://10723346372',['lucide-expand']='rbxassetid://10723346553',[
'lucide-external-link']='rbxassetid://10723346684',['lucide-eye']=
'rbxassetid://10723346959',['lucide-eye-off']='rbxassetid://10723346871',[
'lucide-factory']='rbxassetid://10723347051',['lucide-fan']=
'rbxassetid://10723354359',['lucide-fast-forward']='rbxassetid://10723354521',[
'lucide-feather']='rbxassetid://10723354671',['lucide-figma']=
'rbxassetid://10723354801',['lucide-file']='rbxassetid://10723374641',[
'lucide-file-archive']='rbxassetid://10723354921',['lucide-file-audio']=
'rbxassetid://10723355148',['lucide-file-audio-2']='rbxassetid://10723355026',[
'lucide-file-axis-3d']='rbxassetid://10723355272',['lucide-file-badge']=
'rbxassetid://10723355622',['lucide-file-badge-2']='rbxassetid://10723355451',[
'lucide-file-bar-chart']='rbxassetid://10723355887',['lucide-file-bar-chart-2']=
'rbxassetid://10723355746',['lucide-file-box']='rbxassetid://10723355989',[
'lucide-file-check']='rbxassetid://10723356210',['lucide-file-check-2']=
'rbxassetid://10723356100',['lucide-file-clock']='rbxassetid://10723356329',[
'lucide-file-code']='rbxassetid://10723356507',['lucide-file-cog']=
'rbxassetid://10723356830',['lucide-file-cog-2']='rbxassetid://10723356676',[
'lucide-file-diff']='rbxassetid://10723357039',['lucide-file-digit']=
'rbxassetid://10723357151',['lucide-file-down']='rbxassetid://10723357322',[
'lucide-file-edit']='rbxassetid://10723357495',['lucide-file-heart']=
'rbxassetid://10723357637',['lucide-file-image']='rbxassetid://10723357790',[
'lucide-file-input']='rbxassetid://10723357933',['lucide-file-json']=
'rbxassetid://10723364435',['lucide-file-json-2']='rbxassetid://10723364361',[
'lucide-file-key']='rbxassetid://10723364605',['lucide-file-key-2']=
'rbxassetid://10723364515',['lucide-file-line-chart']='rbxassetid://10723364725'
,['lucide-file-lock']='rbxassetid://10723364957',['lucide-file-lock-2']=
'rbxassetid://10723364861',['lucide-file-minus']='rbxassetid://10723365254',[
'lucide-file-minus-2']='rbxassetid://10723365086',['lucide-file-output']=
'rbxassetid://10723365457',['lucide-file-pie-chart']='rbxassetid://10723365598',
['lucide-file-plus']='rbxassetid://10723365877',['lucide-file-plus-2']=
'rbxassetid://10723365766',['lucide-file-question']='rbxassetid://10723365987',[
'lucide-file-scan']='rbxassetid://10723366167',['lucide-file-search']=
'rbxassetid://10723366550',['lucide-file-search-2']='rbxassetid://10723366340',[
'lucide-file-signature']='rbxassetid://10723366741',['lucide-file-spreadsheet']=
'rbxassetid://10723366962',['lucide-file-symlink']='rbxassetid://10723367098',[
'lucide-file-terminal']='rbxassetid://10723367244',['lucide-file-text']=
'rbxassetid://10723367380',['lucide-file-type']='rbxassetid://10723367606',[
'lucide-file-type-2']='rbxassetid://10723367509',['lucide-file-up']=
'rbxassetid://10723367734',['lucide-file-video']='rbxassetid://10723373884',[
'lucide-file-video-2']='rbxassetid://10723367834',['lucide-file-volume']=
'rbxassetid://10723374172',['lucide-file-volume-2']='rbxassetid://10723374030',[
'lucide-file-warning']='rbxassetid://10723374276',['lucide-file-x']=
'rbxassetid://10723374544',['lucide-file-x-2']='rbxassetid://10723374378',[
'lucide-files']='rbxassetid://10723374759',['lucide-film']=
'rbxassetid://10723374981',['lucide-filter']='rbxassetid://10723375128',[
'lucide-fingerprint']='rbxassetid://10723375250',['lucide-flag']=
'rbxassetid://10723375890',['lucide-flag-off']='rbxassetid://10723375443',[
'lucide-flag-triangle-left']='rbxassetid://10723375608',[
'lucide-flag-triangle-right']='rbxassetid://10723375727',['lucide-flame']=
'rbxassetid://10723376114',['lucide-flashlight']='rbxassetid://10723376471',[
'lucide-flashlight-off']='rbxassetid://10723376365',['lucide-flask-conical']=
'rbxassetid://10734883986',['lucide-flask-round']='rbxassetid://10723376614',[
'lucide-flip-horizontal']='rbxassetid://10723376884',['lucide-flip-horizontal-2'
]='rbxassetid://10723376745',['lucide-flip-vertical']='rbxassetid://10723377138'
,['lucide-flip-vertical-2']='rbxassetid://10723377026',['lucide-flower']=
'rbxassetid://10747830374',['lucide-flower-2']='rbxassetid://10723377305',[
'lucide-focus']='rbxassetid://10723377537',['lucide-folder']=
'rbxassetid://10723387563',['lucide-folder-archive']='rbxassetid://10723384478',
['lucide-folder-check']='rbxassetid://10723384605',['lucide-folder-clock']=
'rbxassetid://10723384731',['lucide-folder-closed']='rbxassetid://10723384893',[
'lucide-folder-cog']='rbxassetid://10723385213',['lucide-folder-cog-2']=
'rbxassetid://10723385036',['lucide-folder-down']='rbxassetid://10723385338',[
'lucide-folder-edit']='rbxassetid://10723385445',['lucide-folder-heart']=
'rbxassetid://10723385545',['lucide-folder-input']='rbxassetid://10723385721',[
'lucide-folder-key']='rbxassetid://10723385848',['lucide-folder-lock']=
'rbxassetid://10723386005',['lucide-folder-minus']='rbxassetid://10723386127',[
'lucide-folder-open']='rbxassetid://10723386277',['lucide-folder-output']=
'rbxassetid://10723386386',['lucide-folder-plus']='rbxassetid://10723386531',[
'lucide-folder-search']='rbxassetid://10723386787',['lucide-folder-search-2']=
'rbxassetid://10723386674',['lucide-folder-symlink']='rbxassetid://10723386930',
['lucide-folder-tree']='rbxassetid://10723387085',['lucide-folder-up']=
'rbxassetid://10723387265',['lucide-folder-x']='rbxassetid://10723387448',[
'lucide-folders']='rbxassetid://10723387721',['lucide-form-input']=
'rbxassetid://10723387841',['lucide-forward']='rbxassetid://10723388016',[
'lucide-frame']='rbxassetid://10723394389',['lucide-framer']=
'rbxassetid://10723394565',['lucide-frown']='rbxassetid://10723394681',[
'lucide-fuel']='rbxassetid://10723394846',['lucide-function-square']=
'rbxassetid://10723395041',['lucide-gamepad']='rbxassetid://10723395457',[
'lucide-gamepad-2']='rbxassetid://10723395215',['lucide-gauge']=
'rbxassetid://10723395708',['lucide-gavel']='rbxassetid://10723395896',[
'lucide-gem']='rbxassetid://10723396000',['lucide-ghost']=
'rbxassetid://10723396107',['lucide-gift']='rbxassetid://10723396402',[
'lucide-gift-card']='rbxassetid://10723396225',['lucide-git-branch']=
'rbxassetid://10723396676',['lucide-git-branch-plus']='rbxassetid://10723396542'
,['lucide-git-commit']='rbxassetid://10723396812',['lucide-git-compare']=
'rbxassetid://10723396954',['lucide-git-fork']='rbxassetid://10723397049',[
'lucide-git-merge']='rbxassetid://10723397165',['lucide-git-pull-request']=
'rbxassetid://10723397431',['lucide-git-pull-request-closed']=
'rbxassetid://10723397268',['lucide-git-pull-request-draft']=
'rbxassetid://10734884302',['lucide-glass']='rbxassetid://10723397788',[
'lucide-glass-2']='rbxassetid://10723397529',['lucide-glass-water']=
'rbxassetid://10723397678',['lucide-glasses']='rbxassetid://10723397895',[
'lucide-globe']='rbxassetid://10723404337',['lucide-globe-2']=
'rbxassetid://10723398002',['lucide-grab']='rbxassetid://10723404472',[
'lucide-graduation-cap']='rbxassetid://10723404691',['lucide-grape']=
'rbxassetid://10723404822',['lucide-grid']='rbxassetid://10723404936',[
'lucide-grip-horizontal']='rbxassetid://10723405089',['lucide-grip-vertical']=
'rbxassetid://10723405236',['lucide-hammer']='rbxassetid://10723405360',[
'lucide-hand']='rbxassetid://10723405649',['lucide-hand-metal']=
'rbxassetid://10723405508',['lucide-hard-drive']='rbxassetid://10723405749',[
'lucide-hard-hat']='rbxassetid://10723405859',['lucide-hash']=
'rbxassetid://10723405975',['lucide-haze']='rbxassetid://10723406078',[
'lucide-headphones']='rbxassetid://10723406165',['lucide-heart']=
'rbxassetid://10723406885',['lucide-heart-crack']='rbxassetid://10723406299',[
'lucide-heart-handshake']='rbxassetid://10723406480',['lucide-heart-off']=
'rbxassetid://10723406662',['lucide-heart-pulse']='rbxassetid://10723406795',[
'lucide-help-circle']='rbxassetid://10723406988',['lucide-hexagon']=
'rbxassetid://10723407092',['lucide-highlighter']='rbxassetid://10723407192',[
'lucide-history']='rbxassetid://10723407335',['lucide-home']=
'rbxassetid://10723407389',['lucide-hourglass']='rbxassetid://10723407498',[
'lucide-ice-cream']='rbxassetid://10723414308',['lucide-image']=
'rbxassetid://10723415040',['lucide-image-minus']='rbxassetid://10723414487',[
'lucide-image-off']='rbxassetid://10723414677',['lucide-image-plus']=
'rbxassetid://10723414827',['lucide-import']='rbxassetid://10723415205',[
'lucide-inbox']='rbxassetid://10723415335',['lucide-indent']=
'rbxassetid://10723415494',['lucide-indian-rupee']='rbxassetid://10723415642',[
'lucide-infinity']='rbxassetid://10723415766',['lucide-info']=
'rbxassetid://10723415903',['lucide-inspect']='rbxassetid://10723416057',[
'lucide-italic']='rbxassetid://10723416195',['lucide-japanese-yen']=
'rbxassetid://10723416363',['lucide-joystick']='rbxassetid://10723416527',[
'lucide-key']='rbxassetid://10723416652',['lucide-keyboard']=
'rbxassetid://10723416765',['lucide-lamp']='rbxassetid://10723417513',[
'lucide-lamp-ceiling']='rbxassetid://10723416922',['lucide-lamp-desk']=
'rbxassetid://10723417016',['lucide-lamp-floor']='rbxassetid://10723417131',[
'lucide-lamp-wall-down']='rbxassetid://10723417240',['lucide-lamp-wall-up']=
'rbxassetid://10723417356',['lucide-landmark']='rbxassetid://10723417608',[
'lucide-languages']='rbxassetid://10723417703',['lucide-laptop']=
'rbxassetid://10723423881',['lucide-laptop-2']='rbxassetid://10723417797',[
'lucide-lasso']='rbxassetid://10723424235',['lucide-lasso-select']=
'rbxassetid://10723424058',['lucide-laugh']='rbxassetid://10723424372',[
'lucide-layers']='rbxassetid://10723424505',['lucide-layout']=
'rbxassetid://10723425376',['lucide-layout-dashboard']=
'rbxassetid://10723424646',['lucide-layout-grid']='rbxassetid://10723424838',[
'lucide-layout-list']='rbxassetid://10723424963',['lucide-layout-template']=
'rbxassetid://10723425187',['lucide-leaf']='rbxassetid://10723425539',[
'lucide-library']='rbxassetid://10723425615',['lucide-life-buoy']=
'rbxassetid://10723425685',['lucide-lightbulb']='rbxassetid://10723425852',[
'lucide-lightbulb-off']='rbxassetid://10723425762',['lucide-line-chart']=
'rbxassetid://10723426393',['lucide-link']='rbxassetid://10723426722',[
'lucide-link-2']='rbxassetid://10723426595',['lucide-link-2-off']=
'rbxassetid://10723426513',['lucide-list']='rbxassetid://10723433811',[
'lucide-list-checks']='rbxassetid://10734884548',['lucide-list-end']=
'rbxassetid://10723426886',['lucide-list-minus']='rbxassetid://10723426986',[
'lucide-list-music']='rbxassetid://10723427081',['lucide-list-ordered']=
'rbxassetid://10723427199',['lucide-list-plus']='rbxassetid://10723427334',[
'lucide-list-start']='rbxassetid://10723427494',['lucide-list-video']=
'rbxassetid://10723427619',['lucide-list-x']='rbxassetid://10723433655',[
'lucide-loader']='rbxassetid://10723434070',['lucide-loader-2']=
'rbxassetid://10723433935',['lucide-locate']='rbxassetid://10723434557',[
'lucide-locate-fixed']='rbxassetid://10723434236',['lucide-locate-off']=
'rbxassetid://10723434379',['lucide-lock']='rbxassetid://10723434711',[
'lucide-log-in']='rbxassetid://10723434830',['lucide-log-out']=
'rbxassetid://10723434906',['lucide-luggage']='rbxassetid://10723434993',[
'lucide-magnet']='rbxassetid://10723435069',['lucide-mail']=
'rbxassetid://10734885430',['lucide-mail-check']='rbxassetid://10723435182',[
'lucide-mail-minus']='rbxassetid://10723435261',['lucide-mail-open']=
'rbxassetid://10723435342',['lucide-mail-plus']='rbxassetid://10723435443',[
'lucide-mail-question']='rbxassetid://10723435515',['lucide-mail-search']=
'rbxassetid://10734884739',['lucide-mail-warning']='rbxassetid://10734885015',[
'lucide-mail-x']='rbxassetid://10734885247',['lucide-mails']=
'rbxassetid://10734885614',['lucide-map']='rbxassetid://10734886202',[
'lucide-map-pin']='rbxassetid://10734886004',['lucide-map-pin-off']=
'rbxassetid://10734885803',['lucide-maximize']='rbxassetid://10734886735',[
'lucide-maximize-2']='rbxassetid://10734886496',['lucide-medal']=
'rbxassetid://10734887072',['lucide-megaphone']='rbxassetid://10734887454',[
'lucide-megaphone-off']='rbxassetid://10734887311',['lucide-meh']=
'rbxassetid://10734887603',['lucide-menu']='rbxassetid://10734887784',[
'lucide-message-circle']='rbxassetid://10734888000',['lucide-message-square']=
'rbxassetid://10734888228',['lucide-mic']='rbxassetid://10734888864',[
'lucide-mic-2']='rbxassetid://10734888430',['lucide-mic-off']=
'rbxassetid://10734888646',['lucide-microscope']='rbxassetid://10734889106',[
'lucide-microwave']='rbxassetid://10734895076',['lucide-milestone']=
'rbxassetid://10734895310',['lucide-minimize']='rbxassetid://10734895698',[
'lucide-minimize-2']='rbxassetid://10734895530',['lucide-minus']=
'rbxassetid://10734896206',['lucide-minus-circle']='rbxassetid://10734895856',[
'lucide-minus-square']='rbxassetid://10734896029',['lucide-monitor']=
'rbxassetid://10734896881',['lucide-monitor-off']='rbxassetid://10734896360',[
'lucide-monitor-speaker']='rbxassetid://10734896512',['lucide-moon']=
'rbxassetid://10734897102',['lucide-more-horizontal']='rbxassetid://10734897250'
,['lucide-more-vertical']='rbxassetid://10734897387',['lucide-mountain']=
'rbxassetid://10734897956',['lucide-mountain-snow']='rbxassetid://10734897665',[
'lucide-mouse']='rbxassetid://10734898592',['lucide-mouse-pointer']=
'rbxassetid://10734898476',['lucide-mouse-pointer-2']='rbxassetid://10734898194'
,['lucide-mouse-pointer-click']='rbxassetid://10734898355',['lucide-move']=
'rbxassetid://10734900011',['lucide-move-3d']='rbxassetid://10734898756',[
'lucide-move-diagonal']='rbxassetid://10734899164',['lucide-move-diagonal-2']=
'rbxassetid://10734898934',['lucide-move-horizontal']='rbxassetid://10734899414'
,['lucide-move-vertical']='rbxassetid://10734899821',['lucide-music']=
'rbxassetid://10734905958',['lucide-music-2']='rbxassetid://10734900215',[
'lucide-music-3']='rbxassetid://10734905665',['lucide-music-4']=
'rbxassetid://10734905823',['lucide-navigation']='rbxassetid://10734906744',[
'lucide-navigation-2']='rbxassetid://10734906332',['lucide-navigation-2-off']=
'rbxassetid://10734906144',['lucide-navigation-off']='rbxassetid://10734906580',
['lucide-network']='rbxassetid://10734906975',['lucide-newspaper']=
'rbxassetid://10734907168',['lucide-octagon']='rbxassetid://10734907361',[
'lucide-option']='rbxassetid://10734907649',['lucide-outdent']=
'rbxassetid://10734907933',['lucide-package']='rbxassetid://10734909540',[
'lucide-package-2']='rbxassetid://10734908151',['lucide-package-check']=
'rbxassetid://10734908384',['lucide-package-minus']='rbxassetid://10734908626',[
'lucide-package-open']='rbxassetid://10734908793',['lucide-package-plus']=
'rbxassetid://10734909016',['lucide-package-search']='rbxassetid://10734909196',
['lucide-package-x']='rbxassetid://10734909375',['lucide-paint-bucket']=
'rbxassetid://10734909847',['lucide-paintbrush']='rbxassetid://10734910187',[
'lucide-paintbrush-2']='rbxassetid://10734910030',['lucide-palette']=
'rbxassetid://10734910430',['lucide-palmtree']='rbxassetid://10734910680',[
'lucide-paperclip']='rbxassetid://10734910927',['lucide-party-popper']=
'rbxassetid://10734918735',['lucide-pause']='rbxassetid://10734919336',[
'lucide-pause-circle']='rbxassetid://10735024209',['lucide-pause-octagon']=
'rbxassetid://10734919143',['lucide-pen-tool']='rbxassetid://10734919503',[
'lucide-pencil']='rbxassetid://10734919691',['lucide-percent']=
'rbxassetid://10734919919',['lucide-person-standing']='rbxassetid://10734920149'
,['lucide-phone']='rbxassetid://10734921524',['lucide-phone-call']=
'rbxassetid://10734920305',['lucide-phone-forwarded']='rbxassetid://10734920508'
,['lucide-phone-incoming']='rbxassetid://10734920694',['lucide-phone-missed']=
'rbxassetid://10734920845',['lucide-phone-off']='rbxassetid://10734921077',[
'lucide-phone-outgoing']='rbxassetid://10734921288',['lucide-pie-chart']=
'rbxassetid://10734921727',['lucide-piggy-bank']='rbxassetid://10734921935',[
'lucide-pin']='rbxassetid://10734922324',['lucide-pin-off']=
'rbxassetid://10734922180',['lucide-pipette']='rbxassetid://10734922497',[
'lucide-pizza']='rbxassetid://10734922774',['lucide-plane']=
'rbxassetid://10734922971',['lucide-play']='rbxassetid://10734923549',[
'lucide-play-circle']='rbxassetid://10734923214',['lucide-plus']=
'rbxassetid://10734924532',['lucide-plus-circle']='rbxassetid://10734923868',[
'lucide-plus-square']='rbxassetid://10734924219',['lucide-podcast']=
'rbxassetid://10734929553',['lucide-pointer']='rbxassetid://10734929723',[
'lucide-pound-sterling']='rbxassetid://10734929981',['lucide-power']=
'rbxassetid://10734930466',['lucide-power-off']='rbxassetid://10734930257',[
'lucide-printer']='rbxassetid://10734930632',['lucide-puzzle']=
'rbxassetid://10734930886',['lucide-quote']='rbxassetid://10734931234',[
'lucide-radio']='rbxassetid://10734931596',['lucide-radio-receiver']=
'rbxassetid://10734931402',['lucide-rectangle-horizontal']=
'rbxassetid://10734931777',['lucide-rectangle-vertical']=
'rbxassetid://10734932081',['lucide-recycle']='rbxassetid://10734932295',[
'lucide-redo']='rbxassetid://10734932822',['lucide-redo-2']=
'rbxassetid://10734932586',['lucide-refresh-ccw']='rbxassetid://10734933056',[
'lucide-refresh-cw']='rbxassetid://10734933222',['lucide-refrigerator']=
'rbxassetid://10734933465',['lucide-regex']='rbxassetid://10734933655',[
'lucide-repeat']='rbxassetid://10734933966',['lucide-repeat-1']=
'rbxassetid://10734933826',['lucide-reply']='rbxassetid://10734934252',[
'lucide-reply-all']='rbxassetid://10734934132',['lucide-rewind']=
'rbxassetid://10734934347',['lucide-rocket']='rbxassetid://10734934585',[
'lucide-rocking-chair']='rbxassetid://10734939942',['lucide-rotate-3d']=
'rbxassetid://10734940107',['lucide-rotate-ccw']='rbxassetid://10734940376',[
'lucide-rotate-cw']='rbxassetid://10734940654',['lucide-rss']=
'rbxassetid://10734940825',['lucide-ruler']='rbxassetid://10734941018',[
'lucide-russian-ruble']='rbxassetid://10734941199',['lucide-sailboat']=
'rbxassetid://10734941354',['lucide-save']='rbxassetid://10734941499',[
'lucide-scale']='rbxassetid://10734941912',['lucide-scale-3d']=
'rbxassetid://10734941739',['lucide-scaling']='rbxassetid://10734942072',[
'lucide-scan']='rbxassetid://10734942565',['lucide-scan-face']=
'rbxassetid://10734942198',['lucide-scan-line']='rbxassetid://10734942351',[
'lucide-scissors']='rbxassetid://10734942778',['lucide-screen-share']=
'rbxassetid://10734943193',['lucide-screen-share-off']=
'rbxassetid://10734942967',['lucide-scroll']='rbxassetid://10734943448',[
'lucide-search']='rbxassetid://10734943674',['lucide-send']=
'rbxassetid://10734943902',['lucide-separator-horizontal']=
'rbxassetid://10734944115',['lucide-separator-vertical']=
'rbxassetid://10734944326',['lucide-server']='rbxassetid://10734949856',[
'lucide-server-cog']='rbxassetid://10734944444',['lucide-server-crash']=
'rbxassetid://10734944554',['lucide-server-off']='rbxassetid://10734944668',[
'lucide-settings']='rbxassetid://10734950309',['lucide-settings-2']=
'rbxassetid://10734950020',['lucide-share']='rbxassetid://10734950813',[
'lucide-share-2']='rbxassetid://10734950553',['lucide-sheet']=
'rbxassetid://10734951038',['lucide-shield']='rbxassetid://10734951847',[
'lucide-shield-alert']='rbxassetid://10734951173',['lucide-shield-check']=
'rbxassetid://10734951367',['lucide-shield-close']='rbxassetid://10734951535',[
'lucide-shield-off']='rbxassetid://10734951684',['lucide-shirt']=
'rbxassetid://10734952036',['lucide-shopping-bag']='rbxassetid://10734952273',[
'lucide-shopping-cart']='rbxassetid://10734952479',['lucide-shovel']=
'rbxassetid://10734952773',['lucide-shower-head']='rbxassetid://10734952942',[
'lucide-shrink']='rbxassetid://10734953073',['lucide-shrub']=
'rbxassetid://10734953241',['lucide-shuffle']='rbxassetid://10734953451',[
'lucide-sidebar']='rbxassetid://10734954301',['lucide-sidebar-close']=
'rbxassetid://10734953715',['lucide-sidebar-open']='rbxassetid://10734954000',[
'lucide-sigma']='rbxassetid://10734954538',['lucide-signal']=
'rbxassetid://10734961133',['lucide-signal-high']='rbxassetid://10734954807',[
'lucide-signal-low']='rbxassetid://10734955080',['lucide-signal-medium']=
'rbxassetid://10734955336',['lucide-signal-zero']='rbxassetid://10734960878',[
'lucide-siren']='rbxassetid://10734961284',['lucide-skip-back']=
'rbxassetid://10734961526',['lucide-skip-forward']='rbxassetid://10734961809',[
'lucide-skull']='rbxassetid://10734962068',['lucide-slack']=
'rbxassetid://10734962339',['lucide-slash']='rbxassetid://10734962600',[
'lucide-slice']='rbxassetid://10734963024',['lucide-sliders']=
'rbxassetid://10734963400',['lucide-sliders-horizontal']=
'rbxassetid://10734963191',['lucide-smartphone']='rbxassetid://10734963940',[
'lucide-smartphone-charging']='rbxassetid://10734963671',['lucide-smile']=
'rbxassetid://10734964441',['lucide-smile-plus']='rbxassetid://10734964188',[
'lucide-snowflake']='rbxassetid://10734964600',['lucide-sofa']=
'rbxassetid://10734964852',['lucide-sort-asc']='rbxassetid://10734965115',[
'lucide-sort-desc']='rbxassetid://10734965287',['lucide-speaker']=
'rbxassetid://10734965419',['lucide-sprout']='rbxassetid://10734965572',[
'lucide-square']='rbxassetid://10734965702',['lucide-star']=
'rbxassetid://10734966248',['lucide-star-half']='rbxassetid://10734965897',[
'lucide-star-off']='rbxassetid://10734966097',['lucide-stethoscope']=
'rbxassetid://10734966384',['lucide-sticker']='rbxassetid://10734972234',[
'lucide-sticky-note']='rbxassetid://10734972463',['lucide-stop-circle']=
'rbxassetid://10734972621',['lucide-stretch-horizontal']=
'rbxassetid://10734972862',['lucide-stretch-vertical']=
'rbxassetid://10734973130',['lucide-strikethrough']='rbxassetid://10734973290',[
'lucide-subscript']='rbxassetid://10734973457',['lucide-sun']=
'rbxassetid://10734974297',['lucide-sun-dim']='rbxassetid://10734973645',[
'lucide-sun-medium']='rbxassetid://10734973778',['lucide-sun-moon']=
'rbxassetid://10734973999',['lucide-sun-snow']='rbxassetid://10734974130',[
'lucide-sunrise']='rbxassetid://10734974522',['lucide-sunset']=
'rbxassetid://10734974689',['lucide-superscript']='rbxassetid://10734974850',[
'lucide-swiss-franc']='rbxassetid://10734975024',['lucide-switch-camera']=
'rbxassetid://10734975214',['lucide-sword']='rbxassetid://10734975486',[
'lucide-swords']='rbxassetid://10734975692',['lucide-syringe']=
'rbxassetid://10734975932',['lucide-table']='rbxassetid://10734976230',[
'lucide-table-2']='rbxassetid://10734976097',['lucide-tablet']=
'rbxassetid://10734976394',['lucide-tag']='rbxassetid://10734976528',[
'lucide-tags']='rbxassetid://10734976739',['lucide-target']=
'rbxassetid://10734977012',['lucide-tent']='rbxassetid://10734981750',[
'lucide-terminal']='rbxassetid://10734982144',['lucide-terminal-square']=
'rbxassetid://10734981995',['lucide-text-cursor']='rbxassetid://10734982395',[
'lucide-text-cursor-input']='rbxassetid://10734982297',['lucide-thermometer']=
'rbxassetid://10734983134',['lucide-thermometer-snowflake']=
'rbxassetid://10734982571',['lucide-thermometer-sun']='rbxassetid://10734982771'
,['lucide-thumbs-down']='rbxassetid://10734983359',['lucide-thumbs-up']=
'rbxassetid://10734983629',['lucide-ticket']='rbxassetid://10734983868',[
'lucide-timer']='rbxassetid://10734984606',['lucide-timer-off']=
'rbxassetid://10734984138',['lucide-timer-reset']='rbxassetid://10734984355',[
'lucide-toggle-left']='rbxassetid://10734984834',['lucide-toggle-right']=
'rbxassetid://10734985040',['lucide-tornado']='rbxassetid://10734985247',[
'lucide-toy-brick']='rbxassetid://10747361919',['lucide-train']=
'rbxassetid://10747362105',['lucide-trash']='rbxassetid://10747362393',[
'lucide-trash-2']='rbxassetid://10747362241',['lucide-tree-deciduous']=
'rbxassetid://10747362534',['lucide-tree-pine']='rbxassetid://10747362748',[
'lucide-trees']='rbxassetid://10747363016',['lucide-trending-down']=
'rbxassetid://10747363205',['lucide-trending-up']='rbxassetid://10747363465',[
'lucide-triangle']='rbxassetid://10747363621',['lucide-trophy']=
'rbxassetid://10747363809',['lucide-truck']='rbxassetid://10747364031',[
'lucide-tv']='rbxassetid://10747364593',['lucide-tv-2']=
'rbxassetid://10747364302',['lucide-type']='rbxassetid://10747364761',[
'lucide-umbrella']='rbxassetid://10747364971',['lucide-underline']=
'rbxassetid://10747365191',['lucide-undo']='rbxassetid://10747365484',[
'lucide-undo-2']='rbxassetid://10747365359',['lucide-unlink']=
'rbxassetid://10747365771',['lucide-unlink-2']='rbxassetid://10747397871',[
'lucide-unlock']='rbxassetid://10747366027',['lucide-upload']=
'rbxassetid://10747366434',['lucide-upload-cloud']='rbxassetid://10747366266',[
'lucide-usb']='rbxassetid://10747366606',['lucide-user']=
'rbxassetid://10747373176',['lucide-user-check']='rbxassetid://10747371901',[
'lucide-user-cog']='rbxassetid://10747372167',['lucide-user-minus']=
'rbxassetid://10747372346',['lucide-user-plus']='rbxassetid://10747372702',[
'lucide-user-x']='rbxassetid://10747372992',['lucide-users']=
'rbxassetid://10747373426',['lucide-utensils']='rbxassetid://10747373821',[
'lucide-utensils-crossed']='rbxassetid://10747373629',['lucide-venetian-mask']=
'rbxassetid://10747374003',['lucide-verified']='rbxassetid://10747374131',[
'lucide-vibrate']='rbxassetid://10747374489',['lucide-vibrate-off']=
'rbxassetid://10747374269',['lucide-video']='rbxassetid://10747374938',[
'lucide-video-off']='rbxassetid://10747374721',['lucide-view']=
'rbxassetid://10747375132',['lucide-voicemail']='rbxassetid://10747375281',[
'lucide-volume']='rbxassetid://10747376008',['lucide-volume-1']=
'rbxassetid://10747375450',['lucide-volume-2']='rbxassetid://10747375679',[
'lucide-volume-x']='rbxassetid://10747375880',['lucide-wallet']=
'rbxassetid://10747376205',['lucide-wand']='rbxassetid://10747376565',[
'lucide-wand-2']='rbxassetid://10747376349',['lucide-watch']=
'rbxassetid://10747376722',['lucide-waves']='rbxassetid://10747376931',[
'lucide-webcam']='rbxassetid://10747381992',['lucide-wifi']=
'rbxassetid://10747382504',['lucide-wifi-off']='rbxassetid://10747382268',[
'lucide-wind']='rbxassetid://10747382750',['lucide-wrap-text']=
'rbxassetid://10747383065',['lucide-wrench']='rbxassetid://10747383470',[
'lucide-x']='rbxassetid://10747384394',['lucide-x-circle']=
'rbxassetid://10747383819',['lucide-x-octagon']='rbxassetid://10747384037',[
'lucide-x-square']='rbxassetid://10747384217',['lucide-zoom-in']=
'rbxassetid://10747384552',['lucide-zoom-out']='rbxassetid://10747384679'}}end,[
30]=function()local aa,ab,ac,ad,ae=m(30)local af={SingleMotor=ac(ab.SingleMotor)
,GroupMotor=ac(ab.GroupMotor),Instant=ac(ab.Instant),Linear=ac(ab.Linear),Spring
=ac(ab.Spring),isMotor=ac(ab.isMotor)}return af end,[31]=function()local aa,ab,
ac,ad,ae=m(31)local af,ag,ah,ai=game:GetService'RunService',ac(ab.Parent.Signal)
,function()end,{}ai.__index=ai function ai.new()return setmetatable({_onStep=ag.
new(),_onStart=ag.new(),_onComplete=ag.new()},ai)end function ai.onStep(aj,ak)
return aj._onStep:connect(ak)end function ai.onStart(aj,ak)return aj._onStart:
connect(ak)end function ai.onComplete(aj,ak)return aj._onComplete:connect(ak)end
function ai.start(aj)if not aj._connection then aj._connection=af.RenderStepped:
Connect(function(ak)aj:step(ak)end)end end function ai.stop(aj)if aj._connection
then aj._connection:Disconnect()aj._connection=nil end end ai.destroy=ai.stop ai
.step=ah ai.getValue=ah ai.setGoal=ah function ai.__tostring(aj)return'Motor'end
return ai end,[32]=function()local aa,ab,ac,ad,ae=m(32)return function()local af
,ag=game:GetService'RunService',ac(ab.Parent.BaseMotor)describe(
'connection management',function()local ah=ag.new()it(
'should hook up connections on :start()',function()ah:start()expect(typeof(ah.
_connection)).to.equal'RBXScriptConnection'end)it(
'should remove connections on :stop() or :destroy()',function()ah:stop()expect(
ah._connection).to.equal(nil)end)end)it('should call :step() with deltaTime',
function()local ah,ai=(ag.new())function ah.step(aj,...)ai={...}ah:stop()end ah:
start()local aj=af.RenderStepped:Wait()af.RenderStepped:Wait()expect(ai).to.be.
ok()expect(ai[1]).to.equal(aj)end)end end,[33]=function()local aa,ab,ac,ad,ae=m(
33)local af,ag,ah=ac(ab.Parent.BaseMotor),ac(ab.Parent.SingleMotor),ac(ab.Parent
.isMotor)local ai=setmetatable({},af)ai.__index=ai local aj=function(aj)if ah(aj
)then return aj end local ak=typeof(aj)if ak=='number'then return ag.new(aj,
false)elseif ak=='table'then return ai.new(aj,false)end error((
'Unable to convert %q to motor; type %s is unsupported'):format(aj,ak),2)end
function ai.new(ak,al)assert(ak,'Missing argument #1: initialValues')assert(
typeof(ak)=='table','initialValues must be a table!')assert(not ak.step,
[[initialValues contains disallowed property "step". Did you mean to put a table of values here?]]
)local am=setmetatable(af.new(),ai)if al~=nil then am._useImplicitConnections=al
else am._useImplicitConnections=true end am._complete=true am._motors={}for an,
ao in pairs(ak)do am._motors[an]=aj(ao)end return am end function ai.step(ak,al)
if ak._complete then return true end local am=true for an,ao in pairs(ak._motors
)do local ap=ao:step(al)if not ap then am=false end end ak._onStep:fire(ak:
getValue())if am then if ak._useImplicitConnections then ak:stop()end ak.
_complete=true ak._onComplete:fire()end return am end function ai.setGoal(ak,al)
assert(not al.step,
[[goals contains disallowed property "step". Did you mean to put a table of goals here?]]
)ak._complete=false ak._onStart:fire()for am,an in pairs(al)do local ao=assert(
ak._motors[am],('Unknown motor for key %s'):format(am))ao:setGoal(an)end if ak.
_useImplicitConnections then ak:start()end end function ai.getValue(ak)local al=
{}for am,an in pairs(ak._motors)do al[am]=an:getValue()end return al end
function ai.__tostring(ak)return'Motor(Group)'end return ai end,[34]=function()
local aa,ab,ac,ad,ae=m(34)return function()local af,ag,ah=ac(ab.Parent.
GroupMotor),ac(ab.Parent.Instant),ac(ab.Parent.Spring)it(
'should complete when all child motors are complete',function()local ai=af.new({
A=1,B=2},false)expect(ai._complete).to.equal(true)ai:setGoal{A=ag.new(3),B=ah.
new(4,{frequency=7.5,dampingRatio=1})}expect(ai._complete).to.equal(false)ai:
step(1.6666666666666665E-2)expect(ai._complete).to.equal(false)for aj=1,30 do ai
:step(1.6666666666666665E-2)end expect(ai._complete).to.equal(true)end)it(
'should start when the goal is set',function()local ai,aj=af.new({A=0},false),
false ai:onStart(function()aj=not aj end)ai:setGoal{A=ag.new(1)}expect(aj).to.
equal(true)ai:setGoal{A=ag.new(1)}expect(aj).to.equal(false)end)it(
'should properly return all values',function()local ai=af.new({A=1,B=2},false)
local aj=ai:getValue()expect(aj.A).to.equal(1)expect(aj.B).to.equal(2)end)it(
'should error when a goal is given to GroupMotor.new',function()local ai=pcall(
function()af.new(ag.new(0))end)expect(ai).to.equal(false)end)it(
[[should error when a single goal is provided to GroupMotor:step]],function()
local ai=pcall(function()af.new{a=1}:setGoal(ag.new(0))end)expect(ai).to.equal(
false)end)end end,[35]=function()local aa,ab,ac,ad,ae=m(35)local af={}af.__index
=af function af.new(ag)return setmetatable({_targetValue=ag},af)end function af.
step(ag)return{complete=true,value=ag._targetValue}end return af end,[36]=
function()local aa,ab,ac,ad,ae=m(36)return function()local af=ac(ab.Parent.
Instant)it('should return a completed state with the provided value',function()
local ag=af.new(1.23)local ah=ag:step(0.1,{value=0,complete=false})expect(ah.
complete).to.equal(true)expect(ah.value).to.equal(1.23)end)end end,[37]=function
()local aa,ab,ac,ad,ae=m(37)local af={}af.__index=af function af.new(ag,ah)
assert(ag,'Missing argument #1: targetValue')ah=ah or{}return setmetatable({
_targetValue=ag,_velocity=ah.velocity or 1},af)end function af.step(ag,ah,ai)
local aj,ak,al=ah.value,ag._velocity,ag._targetValue local am=ai*ak local an=am
>=math.abs(al-aj)aj=aj+am*(al>aj and 1 or-1)if an then aj=ag._targetValue ak=0
end return{complete=an,value=aj,velocity=ak}end return af end,[38]=function()
local aa,ab,ac,ad,ae=m(38)return function()local af,ag=ac(ab.Parent.SingleMotor)
,ac(ab.Parent.Linear)describe('completed state',function()local ah,ai=af.new(0,
false),ag.new(1,{velocity=1})ah:setGoal(ai)for aj=1,60 do ah:step(
1.6666666666666665E-2)end it('should complete',function()expect(ah._state.
complete).to.equal(true)end)it('should be exactly the goal value when completed'
,function()expect(ah._state.value).to.equal(1)end)end)describe(
'uncompleted state',function()local ah,ai=af.new(0,false),ag.new(1,{velocity=1})
ah:setGoal(ai)for aj=1,59 do ah:step(1.6666666666666665E-2)end it(
'should be uncomplete',function()expect(ah._state.complete).to.equal(false)end)
end)describe('negative velocity',function()local ah,ai=af.new(1,false),ag.new(0,
{velocity=1})ah:setGoal(ai)for aj=1,60 do ah:step(1.6666666666666665E-2)end it(
'should complete',function()expect(ah._state.complete).to.equal(true)end)it(
'should be exactly the goal value when completed',function()expect(ah._state.
value).to.equal(0)end)end)end end,[39]=function()local aa,ab,ac,ad,ae=m(39)local
af={}af.__index=af function af.new(ag,ah)return setmetatable({signal=ag,
connected=true,_handler=ah},af)end function af.disconnect(ag)if ag.connected
then ag.connected=false for ah,ai in pairs(ag.signal._connections)do if ai==ag
then table.remove(ag.signal._connections,ah)return end end end end local ag={}ag
.__index=ag function ag.new()return setmetatable({_connections={},_threads={}},
ag)end function ag.fire(ah,...)for ai,aj in pairs(ah._connections)do aj.
_handler(...)end for ai,aj in pairs(ah._threads)do coroutine.resume(aj,...)end
ah._threads={}end function ag.connect(ah,ai)local aj=af.new(ah,ai)table.insert(
ah._connections,aj)return aj end function ag.wait(ah)table.insert(ah._threads,
coroutine.running())return coroutine.yield()end return ag end,[40]=function()
local aa,ab,ac,ad,ae=m(40)return function()local af=ac(ab.Parent.Signal)it(
'should invoke all connections, instantly',function()local ag,ah,ai=(af.new())ag
:connect(function(aj)ah=aj end)ag:connect(function(aj)ai=aj end)ag:fire'hello'
expect(ah).to.equal'hello'expect(ai).to.equal'hello'end)it(
'should return values when :wait() is called',function()local ag=af.new()spawn(
function()ag:fire(123,'hello')end)local ah,ai=ag:wait()expect(ah).to.equal(123)
expect(ai).to.equal'hello'end)it('should properly handle disconnections',
function()local ag,ah=af.new(),false local ai=ag:connect(function()ah=true end)
ai:disconnect()ag:fire()expect(ah).to.equal(false)end)end end,[41]=function()
local aa,ab,ac,ad,ae=m(41)local af=ac(ab.Parent.BaseMotor)local ag=setmetatable(
{},af)ag.__index=ag function ag.new(ah,ai)assert(ah,
'Missing argument #1: initialValue')assert(typeof(ah)=='number',
'initialValue must be a number!')local aj=setmetatable(af.new(),ag)if ai~=nil
then aj._useImplicitConnections=ai else aj._useImplicitConnections=true end aj.
_goal=nil aj._state={complete=true,value=ah}return aj end function ag.step(ah,ai
)if ah._state.complete then return true end local aj=ah._goal:step(ah._state,ai)
ah._state=aj ah._onStep:fire(aj.value)if aj.complete then if ah.
_useImplicitConnections then ah:stop()end ah._onComplete:fire()end return aj.
complete end function ag.getValue(ah)return ah._state.value end function ag.
setGoal(ah,ai)ah._state.complete=false ah._goal=ai ah._onStart:fire()if ah.
_useImplicitConnections then ah:start()end end function ag.__tostring(ah)return
'Motor(Single)'end return ag end,[42]=function()local aa,ab,ac,ad,ae=m(42)return
function()local af,ag=ac(ab.Parent.SingleMotor),ac(ab.Parent.Instant)it(
'should assign new state on step',function()local ah=af.new(0,false)ah:setGoal(
ag.new(5))ah:step(1.6666666666666665E-2)expect(ah._state.complete).to.equal(true
)expect(ah._state.value).to.equal(5)end)it(
[[should invoke onComplete listeners when the goal is completed]],function()
local ah,ai=af.new(0,false),false ah:onComplete(function()ai=true end)ah:
setGoal(ag.new(5))ah:step(1.6666666666666665E-2)expect(ai).to.equal(true)end)it(
'should start when the goal is set',function()local ah,ai=af.new(0,false),false
ah:onStart(function()ai=not ai end)ah:setGoal(ag.new(5))expect(ai).to.equal(true
)ah:setGoal(ag.new(5))expect(ai).to.equal(false)end)end end,[43]=function()local
aa,ab,ac,ad,ae=m(43)local af,ag,ah,ai=0.001,0.001,0.0001,{}ai.__index=ai
function ai.new(aj,ak)assert(aj,'Missing argument #1: targetValue')ak=ak or{}
return setmetatable({_targetValue=aj,_frequency=ak.frequency or 4,_dampingRatio=
ak.dampingRatio or 1},ai)end function ai.step(aj,ak,al)local am,an,ao,ap,aq=aj.
_dampingRatio,aj._frequency*2*math.pi,aj._targetValue,ak.value,ak.velocity or 0
local ar,as,n,o=ap-ao,(math.exp(-am*an*al))if am==1 then n=(ar*(1+an*al)+aq*al)*
as+ao o=(aq*(1-an*al)-ar*(an*an*al))*as elseif am<1 then local p=math.sqrt(1-am*
am)local q,r,s=math.cos(an*p*al),(math.sin(an*p*al))if p>ah then s=r/p else
local t=al*an s=t+((t*t)*(p*p)*(p*p)/20-p*p)*(t*t*t)/6 end local t if an*p>ah
then t=r/(an*p)else local u=an*p t=al+((al*al)*(u*u)*(u*u)/20-u*u)*(al*al*al)/6
end n=(ar*(q+am*s)+aq*t)*as+ao o=(aq*(q-s*am)-ar*(s*an))*as else local p=math.
sqrt(am*am-1)local q,r=-an*(am-p),-an*(am+p)local s=(aq-ar*q)/(2*an*p)local t=ar
-s local u,v=t*math.exp(q*al),s*math.exp(r*al)n=u+v+ao o=u*q+v*r end local p=
math.abs(o)<af and math.abs(n-ao)<ag return{complete=p,value=p and ao or n,
velocity=o}end return ai end,[44]=function()local aa,ab,ac,ad,ae=m(44)return
function()local af,ag=ac(ab.Parent.SingleMotor),ac(ab.Parent.Spring)describe(
'completed state',function()local ah,ai=af.new(0,false),ag.new(1,{frequency=2,
dampingRatio=0.75})ah:setGoal(ai)for aj=1,100 do ah:step(1.6666666666666665E-2)
end it('should complete',function()expect(ah._state.complete).to.equal(true)end)
it('should be exactly the goal value when completed',function()expect(ah._state.
value).to.equal(1)end)end)it('should inherit velocity',function()local ah=af.
new(0,false)ah._state={complete=false,value=0,velocity=-5}local ai=ag.new(1,{
frequency=2,dampingRatio=1})ah:setGoal(ai)ah:step(1.6666666666666665E-2)expect(
ah._state.velocity<0).to.equal(true)end)end end,[45]=function()local aa,ab,ac,ad
,ae=m(45)local af=function(af)local ag=tostring(af):match'^Motor%((.+)%)$'if ag
then return true,ag else return false end end return af end,[46]=function()local
aa,ab,ac,ad,ae=m(46)return function()local af,ag,ah=ac(ab.Parent.isMotor),ac(ab.
Parent.SingleMotor),ac(ab.Parent.GroupMotor)local ai,aj=ag.new(0),ah.new{}it(
'should properly detect motors',function()expect(af(ai)).to.equal(true)expect(
af(aj)).to.equal(true)end)it("shouldn't detect things that aren't motors",
function()expect(af{}).to.equal(false)end)it(
'should return the proper motor type',function()local ak,al=af(ai)local am,an=
af(aj)expect(al).to.equal'Single'expect(an).to.equal'Group'end)end end,[47]=
function()local aa,ab,ac,ad,ae=m(47)local af={Names={'Dark','Darker','Light',
'Aqua','Amethyst','Rose'}}for ag,ah in next,ab:GetChildren()do local ai=ac(ah)af
[ai.Name]=ai end return af end,[48]=function()local aa,ab,ac,ad,ae=m(48)return{
Name='Amethyst',Accent=Color3.fromRGB(97,62,167),AcrylicMain=Color3.fromRGB(20,
20,20),AcrylicBorder=Color3.fromRGB(110,90,130),AcrylicGradient=ColorSequence.
new(Color3.fromRGB(85,57,139),Color3.fromRGB(40,25,65)),AcrylicNoise=0.92,
TitleBarLine=Color3.fromRGB(95,75,110),Tab=Color3.fromRGB(160,140,180),Element=
Color3.fromRGB(140,120,160),ElementBorder=Color3.fromRGB(60,50,70),
InElementBorder=Color3.fromRGB(100,90,110),ElementTransparency=0.87,ToggleSlider
=Color3.fromRGB(140,120,160),ToggleToggled=Color3.fromRGB(0,0,0),SliderRail=
Color3.fromRGB(140,120,160),DropdownFrame=Color3.fromRGB(170,160,200),
DropdownHolder=Color3.fromRGB(60,45,80),DropdownBorder=Color3.fromRGB(50,40,65),
DropdownOption=Color3.fromRGB(140,120,160),Keybind=Color3.fromRGB(140,120,160),
Input=Color3.fromRGB(140,120,160),InputFocused=Color3.fromRGB(20,10,30),
InputIndicator=Color3.fromRGB(170,150,190),Dialog=Color3.fromRGB(60,45,80),
DialogHolder=Color3.fromRGB(45,30,65),DialogHolderLine=Color3.fromRGB(40,25,60),
DialogButton=Color3.fromRGB(60,45,80),DialogButtonBorder=Color3.fromRGB(95,80,
110),DialogBorder=Color3.fromRGB(85,70,100),DialogInput=Color3.fromRGB(70,55,85)
,DialogInputLine=Color3.fromRGB(175,160,190),Text=Color3.fromRGB(240,240,240),
SubText=Color3.fromRGB(170,170,170),Hover=Color3.fromRGB(140,120,160),
HoverChange=0.04}end,[49]=function()local aa,ab,ac,ad,ae=m(49)return{Name='Aqua'
,Accent=Color3.fromRGB(60,165,165),AcrylicMain=Color3.fromRGB(20,20,20),
AcrylicBorder=Color3.fromRGB(50,100,100),AcrylicGradient=ColorSequence.new(
Color3.fromRGB(60,140,140),Color3.fromRGB(40,80,80)),AcrylicNoise=0.92,
TitleBarLine=Color3.fromRGB(60,120,120),Tab=Color3.fromRGB(140,180,180),Element=
Color3.fromRGB(110,160,160),ElementBorder=Color3.fromRGB(40,70,70),
InElementBorder=Color3.fromRGB(80,110,110),ElementTransparency=0.84,ToggleSlider
=Color3.fromRGB(110,160,160),ToggleToggled=Color3.fromRGB(0,0,0),SliderRail=
Color3.fromRGB(110,160,160),DropdownFrame=Color3.fromRGB(160,200,200),
DropdownHolder=Color3.fromRGB(40,80,80),DropdownBorder=Color3.fromRGB(40,65,65),
DropdownOption=Color3.fromRGB(110,160,160),Keybind=Color3.fromRGB(110,160,160),
Input=Color3.fromRGB(110,160,160),InputFocused=Color3.fromRGB(20,10,30),
InputIndicator=Color3.fromRGB(130,170,170),Dialog=Color3.fromRGB(40,80,80),
DialogHolder=Color3.fromRGB(30,60,60),DialogHolderLine=Color3.fromRGB(25,50,50),
DialogButton=Color3.fromRGB(40,80,80),DialogButtonBorder=Color3.fromRGB(80,110,
110),DialogBorder=Color3.fromRGB(50,100,100),DialogInput=Color3.fromRGB(45,90,90
),DialogInputLine=Color3.fromRGB(130,170,170),Text=Color3.fromRGB(240,240,240),
SubText=Color3.fromRGB(170,170,170),Hover=Color3.fromRGB(110,160,160),
HoverChange=0.04}end,[50]=function()local aa,ab,ac,ad,ae=m(50)return{Name='Dark'
,Accent=Color3.fromRGB(177,152,255),AcrylicMain=Color3.fromRGB(17,19,27),
AcrylicBorder=Color3.fromRGB(57,61,80),AcrylicGradient=ColorSequence.new(Color3.
fromRGB(40,40,40),Color3.fromRGB(40,40,40)),AcrylicNoise=0.9,TitleBarLine=Color3
.fromRGB(45,48,64),Tab=Color3.fromRGB(177,152,255),Element=Color3.fromRGB(30,33,
45),ElementBorder=Color3.fromRGB(53,57,76),InElementBorder=Color3.fromRGB(75,80,
103),ElementTransparency=0.12,ToggleSlider=Color3.fromRGB(120,126,149),
ToggleToggled=Color3.fromRGB(30,23,47),SliderRail=Color3.fromRGB(91,96,118),
DropdownFrame=Color3.fromRGB(85,90,115),DropdownHolder=Color3.fromRGB(28,31,43),
DropdownBorder=Color3.fromRGB(65,70,94),DropdownOption=Color3.fromRGB(150,134,
199),Keybind=Color3.fromRGB(78,82,105),Input=Color3.fromRGB(85,90,115),
InputFocused=Color3.fromRGB(18,20,29),InputIndicator=Color3.fromRGB(137,145,173)
,Dialog=Color3.fromRGB(24,27,37),DialogHolder=Color3.fromRGB(20,22,31),
DialogHolderLine=Color3.fromRGB(53,57,76),DialogButton=Color3.fromRGB(39,43,59),
DialogButtonBorder=Color3.fromRGB(76,81,108),DialogBorder=Color3.fromRGB(70,75,
99),DialogInput=Color3.fromRGB(31,35,48),DialogInputLine=Color3.fromRGB(139,119,
210),Text=Color3.fromRGB(241,240,248),SubText=Color3.fromRGB(143,150,173),Hover=
Color3.fromRGB(159,143,207),HoverChange=0.045}end,[51]=function()local aa,ab,ac,
ad,ae=m(51)return{Name='Darker',Accent=Color3.fromRGB(72,138,182),AcrylicMain=
Color3.fromRGB(30,30,30),AcrylicBorder=Color3.fromRGB(60,60,60),AcrylicGradient=
ColorSequence.new(Color3.fromRGB(25,25,25),Color3.fromRGB(15,15,15)),
AcrylicNoise=0.94,TitleBarLine=Color3.fromRGB(65,65,65),Tab=Color3.fromRGB(100,
100,100),Element=Color3.fromRGB(70,70,70),ElementBorder=Color3.fromRGB(25,25,25)
,InElementBorder=Color3.fromRGB(55,55,55),ElementTransparency=0.82,DropdownFrame
=Color3.fromRGB(120,120,120),DropdownHolder=Color3.fromRGB(35,35,35),
DropdownBorder=Color3.fromRGB(25,25,25),Dialog=Color3.fromRGB(35,35,35),
DialogHolder=Color3.fromRGB(25,25,25),DialogHolderLine=Color3.fromRGB(20,20,20),
DialogButton=Color3.fromRGB(35,35,35),DialogButtonBorder=Color3.fromRGB(55,55,55
),DialogBorder=Color3.fromRGB(50,50,50),DialogInput=Color3.fromRGB(45,45,45),
DialogInputLine=Color3.fromRGB(120,120,120)}end,[52]=function()local aa,ab,ac,ad
,ae=m(52)return{Name='Light',Accent=Color3.fromRGB(0,103,192),AcrylicMain=Color3
.fromRGB(200,200,200),AcrylicBorder=Color3.fromRGB(120,120,120),AcrylicGradient=
ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255)),
AcrylicNoise=0.96,TitleBarLine=Color3.fromRGB(160,160,160),Tab=Color3.fromRGB(90
,90,90),Element=Color3.fromRGB(255,255,255),ElementBorder=Color3.fromRGB(180,180
,180),InElementBorder=Color3.fromRGB(150,150,150),ElementTransparency=0.65,
ToggleSlider=Color3.fromRGB(40,40,40),ToggleToggled=Color3.fromRGB(255,255,255),
SliderRail=Color3.fromRGB(40,40,40),DropdownFrame=Color3.fromRGB(200,200,200),
DropdownHolder=Color3.fromRGB(240,240,240),DropdownBorder=Color3.fromRGB(200,200
,200),DropdownOption=Color3.fromRGB(150,150,150),Keybind=Color3.fromRGB(120,120,
120),Input=Color3.fromRGB(200,200,200),InputFocused=Color3.fromRGB(100,100,100),
InputIndicator=Color3.fromRGB(80,80,80),Dialog=Color3.fromRGB(255,255,255),
DialogHolder=Color3.fromRGB(240,240,240),DialogHolderLine=Color3.fromRGB(228,228
,228),DialogButton=Color3.fromRGB(255,255,255),DialogButtonBorder=Color3.
fromRGB(190,190,190),DialogBorder=Color3.fromRGB(140,140,140),DialogInput=Color3
.fromRGB(250,250,250),DialogInputLine=Color3.fromRGB(160,160,160),Text=Color3.
fromRGB(0,0,0),SubText=Color3.fromRGB(40,40,40),Hover=Color3.fromRGB(50,50,50),
HoverChange=0.16}end,[53]=function()local aa,ab,ac,ad,ae=m(53)return{Name='Rose'
,Accent=Color3.fromRGB(180,55,90),AcrylicMain=Color3.fromRGB(40,40,40),
AcrylicBorder=Color3.fromRGB(130,90,110),AcrylicGradient=ColorSequence.new(
Color3.fromRGB(190,60,135),Color3.fromRGB(165,50,70)),AcrylicNoise=0.92,
TitleBarLine=Color3.fromRGB(140,85,105),Tab=Color3.fromRGB(180,140,160),Element=
Color3.fromRGB(200,120,170),ElementBorder=Color3.fromRGB(110,70,85),
InElementBorder=Color3.fromRGB(120,90,90),ElementTransparency=0.86,ToggleSlider=
Color3.fromRGB(200,120,170),ToggleToggled=Color3.fromRGB(0,0,0),SliderRail=
Color3.fromRGB(200,120,170),DropdownFrame=Color3.fromRGB(200,160,180),
DropdownHolder=Color3.fromRGB(120,50,75),DropdownBorder=Color3.fromRGB(90,40,55)
,DropdownOption=Color3.fromRGB(200,120,170),Keybind=Color3.fromRGB(200,120,170),
Input=Color3.fromRGB(200,120,170),InputFocused=Color3.fromRGB(20,10,30),
InputIndicator=Color3.fromRGB(170,150,190),Dialog=Color3.fromRGB(120,50,75),
DialogHolder=Color3.fromRGB(95,40,60),DialogHolderLine=Color3.fromRGB(90,35,55),
DialogButton=Color3.fromRGB(120,50,75),DialogButtonBorder=Color3.fromRGB(155,90,
115),DialogBorder=Color3.fromRGB(100,70,90),DialogInput=Color3.fromRGB(135,55,80
),DialogInputLine=Color3.fromRGB(190,160,180),Text=Color3.fromRGB(240,240,240),
SubText=Color3.fromRGB(170,170,170),Hover=Color3.fromRGB(200,120,170),
HoverChange=0.04}end}do local ab,ac,ad,ae,af,ag,ah,ai,aj,ak,al,am,an,ao,ap,aq=c,
setmetatable,error,newproxy,getmetatable,next,table,unpack,coroutine,script,type
,require,pcall,getfenv,setfenv,rawget local ar,as,n,o,p,q,r,s,t,u,v=ah.insert,ah
.remove,ah.freeze or function(ar)return ar end,ab and ab.defer or function(ar,
...)local as=aj.create(ar)aj.resume(as,...)return as end,'0.0.0-venv',{},{},{},{
},{},{}local w,x={GetChildren=function(w)local x,y=v[w],{}for z in ag,x do ar(y,
z)end return y end,FindFirstChild=function(w,x)if not x then ad(
'Argument 1 missing or nil',2)end for y in ag,v[w]do if y.Name==x then return y
end end return end,GetFullName=function(w)local x,y=w.Name,w.Parent while y do x
=y.Name..'.'..x y=y.Parent end return'VirtualEnv.'..x end},{}for y,z in ag,w do
x[y]=function(A,...)if not v[A]then ad(
"Expected ':' not '.' calling member function "..y,1)end return z(A,...)end end
local y=function(y,z,A)local B,C,D,E,F=ac({},{__mode='k'}),function(B)ad(B..
' is not a valid (virtual) member of '..y..' "'..z..'"',1)end,function(B)ad(
'Unable to assign (virtual) property '..B..'. Property is read only',1)end,(ae(
true))local G=af(E)G.__index=function(H,I)if I=='ClassName'then return y elseif
I=='Name'then return z elseif I=='Parent'then return A elseif y=='StringValue'
and I=='Value'then return F else local J=x[I]if J then return J end end for J in
ag,B do if J.Name==I then return J end end C(I)end G.__newindex=function(H,I,J)
if I=='ClassName'then D(I)elseif I=='Name'then z=J elseif I=='Parent'then if J==
E then return end if A~=nil then v[A][E]=nil end A=J if J~=nil then v[J][E]=true
end elseif y=='StringValue'and I=='Value'then F=J else C(I)end end G.__tostring=
function()return z end v[E]=B if A~=nil then v[A][E]=true end return E end local 
function z(A,B)local C,D,E,F=A[1],A[2],A[3],A[4]local G=as(E,1)local H=y(D,G,B)q
[C]=H if E then for I,J in ag,E do H[I]=J end end if F then for I,J in ag,F do
z(J,H)end end return H end local A={}for B,C in ag,l do ar(A,z(C))end for B,C in
ag,aa do local D=q[B]r[D]=C local E=D.ClassName if E=='LocalScript'or E==
'Script'then ar(t,D)end end local B=function(B)local C,D=B.ClassName,s[B]if D
and C=='ModuleScript'then return ai(D)end local E=r[B]if not E then return end
if C=='LocalScript'or C=='Script'then E()return else local F={E()}s[B]=F return
ai(F)end end function m(C)local D=q[C]local E=r[D]if not E then return end local
F,G,H,I,J,K,L=false,n{Version=p,Script=ak,Shared=u,GetScript=function()return ak
end,GetShared=function()return u end},D,function(F,...)if v[F]and F.ClassName==
'ModuleScript'and r[F]then return B(F)end return am(F,...)end local M,N=function
(M,...)if not F then L()end if al(M)=='number'and M>=0 then if M==0 then return
K else M=M+1 local N,O=an(ao,M)if N and O==J then return K end end end return
ao(M,...)end,function(M,N,...)if not F then L()end if al(M)=='number'and M>=0
then if M==0 then return ap(K,N)else M=M+1 local O,P=an(ao,M)if O and P==J then
return ap(K,N)end end end return ap(M,N,...)end function L()J=ao(0)local O={maui
=G,script=H,require=I,getfenv=M,setfenv=N}K=ac({},{__index=function(P,Q)local R=
aq(K,Q)if R~=nil then return R end local S=O[Q]if S~=nil then return S end
return J[Q]end})ap(E,K)F=true end return G,H,I,M,N end for C,D in ag,t do o(B,D)
end do local C for D,E in ag,A do if E.ClassName=='ModuleScript'and E.Name==
'MainModule'then C=E break end end if C then return B(C)end end end end local aa
=h()if not aa or type(aa.CreateWindow)~='function'then return end aa.
SafeCallback=function(ab,ac,...)if type(ac)~='function'or not a.alive then
return end local ad,ae=pcall(ac,...)if not ad then a.record(ae)end return ad and
ae or nil end local ab=aa.Destroy aa.Destroy=function()f()end a.cleanup[#a.
cleanup+1]=function()pcall(ab,aa)end local ac=g(
[[https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua]]
,true)local ad=g(
[[https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua]]
,true)local ae=game:GetService('Players')local af=game:GetService('RunService')
local ag=game:GetService('UserInputService')local ah=game:GetService(
'TweenService')local ai=game:GetService('Teams')local aj=game:GetService(
'CoreGui')local ak=ae.LocalPlayer local al=workspace.CurrentCamera local am=ag.
TouchEnabled and not ag.KeyboardEnabled local an,ao,ap={},{},{}local function aq
(ar,as)local i=ar:Connect(a.guard(as))an[#an+1]=i if#an%64==0 then for j=#an,1,-
1 do if not an[j].Connected then table.remove(an,j)end end end return i end
local function ar(as,i)local j=Instance.new(as)if i then local k=i.Parent for l,
m in pairs(i)do if l~='Parent'then j[l]=m end end if k then j.Parent=k end end
ap[j]=true j.Destroying:Connect(function()ap[j]=nil end)return j end local 
function as()for i,j in ipairs(an)do pcall(j.Disconnect,j)end for i in pairs(ao)
do pcall(i.Remove,i)end for i in pairs(ap)do pcall(i.Destroy,i)end table.clear(
an)table.clear(ao)table.clear(ap)end a.cleanup[#a.cleanup+1]=as aq(workspace:
GetPropertyChangedSignal('CurrentCamera'),function()al=workspace.CurrentCamera
end)local i=ak:FindFirstChild('PlayerGui')do local j=Instance.new('Folder')if
pcall(function()j.Parent=aj end)then i=aj end j:Destroy()end local j=ar(
'ScreenGui',{Name='ZephyrUniversalOverlay',ResetOnSpawn=false,IgnoreGuiInset=
true,DisplayOrder=20,Parent=i})local k={}local l=0 local function m(n,o)local p
if type(Drawing)=='table'and type(Drawing.new)=='function'then local q,r=pcall(
Drawing.new,n)if q then p=r end end local q={Visible=false,Color=Color3.new(1,1,
1),Transparency=1,Thickness=1,Position=Vector2.zero,Size=Vector2.zero,Radius=0,
From=Vector2.zero,To=Vector2.zero,Text='',Center=false,Filled=false}local r,s if
not p then l+=1 r=Instance.new(n=='Text'and'TextLabel'or'Frame')r.
BorderSizePixel=0 r.Visible=false r.Parent=j if n=='Text'then r.
BackgroundTransparency=1 r.Font=Enum.Font.GothamMedium r.TextStrokeColor3=Color3
.new()r.TextYAlignment=Enum.TextYAlignment.Top else s=Instance.new('UIStroke')s.
ApplyStrokeMode=Enum.ApplyStrokeMode.Border s.Parent=r if n=='Circle'then local
t=Instance.new('UICorner')t.CornerRadius=UDim.new(1,0)t.Parent=r end end end
local t,u=false,nil local v={}local function w()if t then return end t=true ao[u
]=nil k[u]=nil if p then pcall(p.Remove,p)else r:Destroy()end end local function 
x()if t then return end r.Visible=q.Visible if not q.Visible then return end r.
ZIndex=q.ZIndex or 1 local y=1-math.clamp(q.Transparency or 1,0,1)if n=='Text'
then r.Text=q.Text r.TextSize=tonumber(q.Size)or 12 r.TextColor3=q.Color r.
TextTransparency=y r.TextStrokeTransparency=q.Outline and 0.45 or 1 r.
AnchorPoint=Vector2.new(q.Center and 0.5 or 0,0)r.Position=UDim2.fromOffset(q.
Position.X,q.Position.Y)r.Size=UDim2.fromOffset(300,(tonumber(q.Size)or 12)+5)r.
TextXAlignment=q.Center and Enum.TextXAlignment.Center or Enum.TextXAlignment.
Left else s.Color=q.Color s.Thickness=q.Thickness s.Transparency=y s.Enabled=not
q.Filled and n~='Line'r.BackgroundColor3=q.Color r.BackgroundTransparency=(q.
Filled or n=='Line')and y or 1 if n=='Line'then local z=q.To-q.From r.
AnchorPoint=Vector2.new(0.5,0.5)r.Position=UDim2.fromOffset((q.From.X+q.To.X)/2,
(q.From.Y+q.To.Y)/2)r.Size=UDim2.fromOffset(z.Magnitude,math.max(1,q.Thickness))
r.Rotation=math.deg(math.atan2(z.Y,z.X))elseif n=='Circle'then r.AnchorPoint=
Vector2.new(0.5,0.5)r.Position=UDim2.fromOffset(q.Position.X,q.Position.Y)r.Size
=UDim2.fromOffset(q.Radius*2,q.Radius*2)else r.Position=UDim2.fromOffset(q.
Position.X,q.Position.Y)r.Size=UDim2.fromOffset(math.max(0,q.Size.X),math.max(0,
q.Size.Y))end end end u=setmetatable({},{__index=function(y,z)if z=='Remove'or z
=='Destroy'then return w end return q[z]end,__newindex=function(y,z,A)if t or(v[
z]and q[z]==A)then return end v[z]=true q[z]=A if p then local B,C=pcall(
function()p[z]=A end)if not B then a.record(C)end else k[u]=x end end})ao[u]=
true if p then pcall(function()p.Visible=false end)end for y,z in pairs(o or{})
do u[y]=z end return u end local function n()for o,p in pairs(k)do k[o]=nil
local q,r=pcall(p)if not q then a.record(r)end end end local o=RaycastParams.
new()o.FilterType=Enum.RaycastFilterType.Exclude local p=Vector2.new local q=
Vector3.new local r=CFrame.new local s=CFrame.lookAt local t=os.clock local u=
math.abs local v=math.huge local function w()local x=al.ViewportSize return p(x.
X*0.5,x.Y*0.5)end local function x(y,z)local A,B,C=y.X-z.X,y.Y-z.Y,y.Z-z.Z
return A*A+B*B+C*C end local function y(z,A)if not z or not A then return false
end local B,C=pcall(function()if not z.Neutral and not A.Neutral and z.Team and
A.Team then return z.Team==A.Team end local B,C=z.Character,A.Character if B and
C then local D,E=B:FindFirstChild('Team'),C:FindFirstChild('Team')if D and E and
D:IsA('StringValue')then return D.Value==E.Value end local F,G=B:GetAttribute(
'Team'),C:GetAttribute('Team')if F~=nil and G~=nil then return F==G end end
return false end)return B and C or false end local function z(A)return A and(A:
FindFirstChild('HumanoidRootPart')or A:FindFirstChild('UpperTorso')or A:
FindFirstChild('Torso'))end local function A(B)return B and B:
FindFirstChildOfClass('Humanoid')end local function B(C)local D=A(C)return D and
D.Health>0 end local function C(D,E)if not D then return false end E=E or al.
CFrame.Position o.FilterDescendantsInstances={ak.Character,al}for F,G in ipairs(
{'Head','HumanoidRootPart'})do local H=D:FindFirstChild(G)if H then local I=
workspace:Raycast(E,H.Position-E,o)if not I or I.Instance:IsDescendantOf(D)then
return true end end end return false end local function D(E,F,G)if not E then
return nil end if F=='Head'then return E:FindFirstChild('Head')end if F=='Body'
then return z(E)end local H,I=nil,v for J,K in ipairs({'Head','HumanoidRootPart'
,'UpperTorso','Torso'})do local L=E:FindFirstChild(K)if L then local M,N=al:
WorldToViewportPoint(L.Position)if N then local O=(p(M.X,M.Y)-G).Magnitude if O<
I then H,I=L,O end end end end return H end local function E(F)if F>0.65 then
return Color3.fromRGB(112,218,181)elseif F>0.35 then return Color3.fromRGB(240,
198,100)else return Color3.fromRGB(244,113,137)end end local F,G,H={},{},{}local
I=0 local J,K={},{}local function L(M)if not M:IsA('Model')then return false end
if ae:GetPlayerFromCharacter(M)then return false end if not M:
FindFirstChildOfClass('Humanoid')then return false end local N=M:FindFirstChild(
'HumanoidRootPart')or M:FindFirstChild('UpperTorso')or M:FindFirstChild('Torso')
or M:FindFirstChild('Head')return N~=nil end local function M(N)if F[N]then
return end if not L(N)then return end I=I+1 F[N]=true G[I]=N H[N]=I for O,P in
ipairs(J)do c.spawn(P,N)end end local function N(O)if not F[O]then return end
for P,Q in ipairs(K)do c.spawn(Q,O)end local P=H[O]local Q=G[I]G[P]=Q H[Q]=P G[I
]=nil H[O]=nil F[O]=nil I=I-1 end aq(workspace.DescendantAdded,function(O)if O:
IsA('Model')then c.defer(function()if O.Parent then M(O)end end)elseif O:IsA(
'Humanoid')or(O:IsA('BasePart')and O.Name=='HumanoidRootPart')then c.defer(
function()local P=O.Parent if P and P:IsA('Model')and P.Parent then M(P)end end)
end end)aq(workspace.DescendantRemoving,function(O)if F[O]then N(O)end if O:IsA(
'Humanoid')and O.Parent and F[O.Parent]then N(O.Parent)end end)local function O(
P)aq(P.CharacterAdded,function(Q)if F[Q]then N(Q)end end)end for P,Q in ipairs(
ae:GetPlayers())do O(Q)end aq(ae.PlayerAdded,O)c.spawn(function()for P,Q in
ipairs(workspace:GetDescendants())do if not a.alive then return end if Q:IsA(
'Model')then M(Q)end if P%100==0 then c.wait()end end end)local function P(Q,R,S
,T,U)local V=T and 144 or 176 local W=T and 700 or 900 local X=T and 560 or 668
local Y=U().ViewportSize local Z=Q:CreateWindow({Title='',SubTitle='',TabWidth=V
,Size=UDim2.fromOffset(math.min(W,Y.X-40),math.min(X,Y.Y-40)),Acrylic=false,
Theme='Dark',MinimizeKey=Enum.KeyCode.RightShift})Q.GUI.DisplayOrder=100000 Q.
GUI.IgnoreGuiInset=true local _=Z.Root Z.AcrylicPaint.Frame.Visible=false local
at={background=Color3.fromRGB(17,19,27),navigation=Color3.fromRGB(21,23,32),line
=Color3.fromRGB(45,48,64),text=Color3.fromRGB(241,240,248),muted=Color3.fromRGB(
143,150,173),accent=Color3.fromRGB(177,152,255)}local au={}local function av(aw,
ax,ay,az)local aA=R(aw,ax)if ay then aA[ay]=at[az]au[#au+1]={aA,ay,az}end return
aA end local function aw(ax,ay,az,aA,aB,aC,aD,aE)return av('TextLabel',{Name=ax,
Text=ay,TextSize=az,Font=aE or Enum.Font.GothamMedium,TextXAlignment=Enum.
TextXAlignment.Left,BackgroundTransparency=1,Position=aA,Size=aB,Parent=aD or _,
ZIndex=4,TextTruncate=Enum.TextTruncate.AtEnd},'TextColor3',aC)end _.
BackgroundTransparency=0 _.BackgroundColor3=at.background _.BorderSizePixel=0 au
[#au+1]={_,'BackgroundColor3','background'}av('UICorner',{CornerRadius=UDim.new(
0,14),Parent=_})local ax=av('Frame',{Name='MatteBacking',BackgroundTransparency=
0,BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=0,Parent=_},
'BackgroundColor3','background')av('UICorner',{CornerRadius=UDim.new(0,14),
Parent=ax})local ay=av('Frame',{Name='NavigationPanel',BorderSizePixel=0,
Position=UDim2.fromOffset(1,57),Size=UDim2.new(0,V+22,1,-58),ZIndex=0,Parent=_},
'BackgroundColor3','navigation')av('UICorner',{CornerRadius=UDim.new(0,13),
Parent=ay})av('Frame',{Name='NavigationDivider',BorderSizePixel=0,Position=UDim2
.fromOffset(V+24,57),Size=UDim2.new(0,1,1,-58),ZIndex=3,Parent=_},
'BackgroundColor3','line')av('UIStroke',{Thickness=1,Transparency=0.25,Parent=_}
,'Color','line')local az=av('TextLabel',{Name='ZephyrMonogram',Text='Z',Font=
Enum.Font.GothamBold,TextSize=23,BackgroundColor3=Color3.fromRGB(177,152,255),
TextColor3=Color3.fromRGB(24,20,36),Size=UDim2.fromOffset(32,32),Position=UDim2.
fromOffset(18,12),ZIndex=4,Parent=_})av('UICorner',{CornerRadius=UDim.new(0,9),
Parent=az})aw('Brand','ZEPHYR',15,UDim2.fromOffset(62,10),UDim2.fromOffset(120,
22),'text',_,Enum.Font.GothamBold)aw('Edition','UNIVERSAL',9,UDim2.fromOffset(63
,31),UDim2.fromOffset(110,13),'muted')aw('NavigationCaption','WORKSPACE',9,UDim2
.fromOffset(23,76),UDim2.fromOffset(V-12,14),'muted')aw('ContentCaption',
'CONFIGURATION',9,UDim2.fromOffset(V+47,76),UDim2.new(1,-V-74,0,14),'accent')aw(
'FooterBrand','ZEPHYR  /  UNIVERSAL',9,UDim2.fromOffset(23,0),UDim2.fromOffset(V
-12,14),'muted').Position=UDim2.new(0,23,1,-64)local aA=aw('WindowShortcut',T
and'DRAG TO MOVE'or'R SHIFT   Hide window',10,UDim2.new(0,23,1,-43),UDim2.
fromOffset(V-12,20),'muted')av('Frame',{Name='FooterLine',BorderSizePixel=0,
Position=UDim2.new(0,23,1,-80),Size=UDim2.fromOffset(V-14,1),ZIndex=3,Parent=_},
'BackgroundColor3','line')local function aB(aC)local aD=aC=='Light'at.background
=aD and Color3.fromRGB(242,243,249)or Color3.fromRGB(17,19,27)at.navigation=aD
and Color3.fromRGB(232,234,243)or Color3.fromRGB(21,23,32)at.text=aD and Color3.
fromRGB(33,35,49)or Color3.fromRGB(241,240,248)at.muted=aD and Color3.fromRGB(
101,108,130)or Color3.fromRGB(143,150,173)at.line=aD and Color3.fromRGB(195,199,
216)or Color3.fromRGB(45,48,64)at.accent=aD and Color3.fromRGB(109,76,193)or
Color3.fromRGB(177,152,255)for aE,aF in ipairs(au)do if aF[1].Parent then aF[1][
aF[2] ]=at[aF[3] ]end end end local aC=Q.SetTheme Q.SetTheme=function(aD,aE)aC(
aD,aE)aB(aD.Theme)end local aD=av('UIScale',{Scale=1,Parent=_})local function aE
()local aF=U()if not aF or Z.Maximized then return end local aG=aF.ViewportSize
local aH=math.max(240,aG.X-32)local aI=math.max(200,aG.Y-32)local aJ=math.min(1,
aH/620)aD.Scale=aJ local aK=math.min(W,aH/aJ)local aL=math.min(X,aI/aJ)Z.Size=
UDim2.fromOffset(aK,aL)Z.Position=UDim2.fromOffset((aG.X-aK*aJ)/2,(aG.Y-aL*aJ)/2
)_.Size,_.Position=Z.Size,Z.Position local aM=aL<440 aA.Visible=not aM _.
FooterBrand.Visible=not aM _.FooterLine.Visible=not aM _.NavigationCaption.
Visible=not aM Z.TabHolder.Parent.Position=UDim2.fromOffset(12,aM and 78 or 103)
Z.TabHolder.Parent.Size=UDim2.new(0,V,1,aM and-94 or-202)Z.TabHolder.
ScrollBarThickness=2 Z.TabHolder.ScrollBarImageTransparency=0.65 end local aF
local function aG()if aF then aF:Disconnect()end local aH=U()if aH then aF=S(aH:
GetPropertyChangedSignal('ViewportSize'),aE)end aE()end S(workspace:
GetPropertyChangedSignal('CurrentCamera'),aG)aG()return Z end local function at(
au)local av={Main={{'PA','01   AIMBOT'},{'PH','02   HITBOXES'},{'PF',
'03   AUTO FARM'},{'SA','04   SAFE AREA'}},MainNPCS={{'NA','01   AIMBOT'},{'NH',
'02   HITBOXES'},{'NF','03   AUTO FARM'}},Visuals={{'PV','01   PLAYER DISPLAY'}}
,VisualsNPCS={{'NV','01   NPC DISPLAY'},{'IE','02   ITEMS & INTERACTABLES'}}}for
aw,ax in pairs(av)do local ay,az=au[aw],{}for aA,aB in ipairs(ax)do local aC=ay:
AddSection(aB[2])aC.Container.Parent.LayoutOrder=aA az[aB[1] ]=aC end au[aw]=
setmetatable({},{__index=function(aA,aB)local aC=ay[aB]if type(aC)=='function'
and aB:sub(1,3)=='Add'and aB~='AddSection'then return function(aD,aE,...)local
aF=type(aE)=='string'and aE:match('^([^_]+)_')return aC(az[aF]or ay,aE,...)end
end return aC end})end end local au=P(aa,ar,aq,am,function()return workspace.
CurrentCamera end)if am then local av=ar('ScreenGui',{Name=
'ZephyrUniversalToggle',ResetOnSpawn=false,Parent=i})local aw=ar('ImageButton',{
Size=UDim2.fromOffset(44,44),Position=UDim2.new(0.1,0,0.5,0),AnchorPoint=Vector2
.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(230,239,235),Image=
'rbxthumb://type=Asset&id=89616857457936&w=420&h=420',BackgroundTransparency=0.1
,Parent=av})ar('UICorner',{CornerRadius=UDim.new(0,7),Parent=aw})ar('UIStroke',{
Color=Color3.fromRGB(100,100,100),Thickness=2,Parent=aw})ar('TextLabel',{Size=
UDim2.fromScale(1,1),BackgroundTransparency=1,Text='',TextColor3=Color3.new(1,1,
1),TextSize=30,Font=Enum.Font.GothamBold,Parent=aw})local ax,ay=true,false aq(aw
.Activated,function()if ay then ay=false return end ax=not ax if au.Minimize
then au:Minimize(not ax)elseif au.ToggleWindow then au:ToggleWindow()elseif au.
SetVisible then au:SetVisible(ax)end aw.BackgroundColor3=Color3.fromRGB(230,239,
235)end)local az,aA,aB,aC aq(aw.InputBegan,function(aD)if aD.UserInputType==Enum
.UserInputType.Touch or aD.UserInputType==Enum.UserInputType.MouseButton1 then
az,aA,aB,aC=true,aD.Position,aw.Position,aD ay=false end end)aq(ag.InputChanged,
function(aD)if az and(aD==aC or(aC.UserInputType==Enum.UserInputType.
MouseButton1 and aD.UserInputType==Enum.UserInputType.MouseMovement))then local
aE=aD.Position-aA if math.abs(aE.X)+math.abs(aE.Y)>6 then ay=true end local aF=
av.AbsoluteSize aw.Position=UDim2.fromOffset(math.clamp(aB.X.Scale*aF.X+aB.X.
Offset+aE.X,22,math.max(22,aF.X-22)),math.clamp(aB.Y.Scale*aF.Y+aB.Y.Offset+aE.Y
,22,math.max(22,aF.Y-22)))end end)aq(ag.InputEnded,function(aD)if aD==aC then az
,aC=false,nil end end)end local av={Main=au:AddTab({Title='Players',Icon=
'crosshair'}),Visuals=au:AddTab({Title='Player ESP',Icon='eye'}),MainNPCS=au:
AddTab({Title='NPCs',Icon='target'}),VisualsNPCS=au:AddTab({Title='World ESP',
Icon='scan'}),Settings=au:AddTab({Title='Settings',Icon='settings'})}at(av)local
aw=aa.Options local function ax(ay)for az,aA in ipairs({'PF_Farm','NF_Farm',
'SA_Toggle'})do if aA~=ay and aw[aA]and aw[aA].Value then aw[aA]:SetValue(false)
end end end do local ay={Enabled=false,Key=am and'Automatic'or'MouseButton2',
ShowFOV=false,FOVSize=100,Strength=0.3,Mode=am and'Automatic'or'Toggle',
TeamCheck=false,WallCheck=false,TargetPart='Head'}local az,aA=nil,false local aB
=w()local aC=m('Circle',{Thickness=1,Color=Color3.new(1,1,1),Filled=false,
Transparency=0.7,NumSides=60,ZIndex=1,Radius=ay.FOVSize,Position=aB,Visible=
false})local function aD()aB=w()aC.Position=aB aC.Radius=ay.FOVSize aC.Visible=
ay.ShowFOV and ay.Enabled end local function aE(aF)if not aF or aF==ak then
return false end local aG=aF.Character if not B(aG)then return false end if ay.
TeamCheck and y(aF,ak)then return false end if ay.WallCheck and not C(aG)then
return false end return true end local function aF()local aG,aH=nil,v for aI,aJ
in ipairs(ae:GetPlayers())do if aE(aJ)then local aK=D(aJ.Character,ay.TargetPart
,aB)if aK then local aL,aM=al:WorldToViewportPoint(aK.Position)if aM then local
Q=(p(aL.X,aL.Y)-aB).Magnitude if Q<=ay.FOVSize and Q<aH then aG,aH=aJ,Q end end
end end end return aG end local function aG(aH)if not aH or not aH.Character
then return end local aI=D(aH.Character,ay.TargetPart,aB)if aI then al.CFrame=al
.CFrame:Lerp(s(al.CFrame.Position,aI.Position),ay.Strength)end end av.Main:
AddToggle('PA_Enabled',{Title='Enable Aimbot',Default=false,Callback=function(aH
)if aH and aw.NA_Enabled and aw.NA_Enabled.Value then aw.NA_Enabled:SetValue(
false)end ay.Enabled=aH aD()end})av.Main:AddToggle('PA_ShowFOV',{Title=
'Show FOV Circle',Default=false,Callback=function(aH)ay.ShowFOV=aH aD()end})av.
Main:AddToggle('PA_Team',{Title='Team Check',Default=false,Callback=function(aH)
ay.TeamCheck=aH end})av.Main:AddToggle('PA_Wall',{Title='Wall Check',Default=
false,Callback=function(aH)ay.WallCheck=aH end})av.Main:AddDropdown('PA_Part',{
Title='Target Body Part',Values={'Head','Body','Both'},Default='Head'}):
OnChanged(function(aH)ay.TargetPart=aH end)if not am then av.Main:AddDropdown(
'PA_Key',{Title='Aimbot Key',Values={'Automatic','MouseButton2','E','Q','T','F',
'C','X','Z','LeftAlt','LeftControl'},Default='MouseButton2'}):OnChanged(function
(aH)ay.Key=aH end)av.Main:AddDropdown('PA_Mode',{Title='Activation Mode',Values=
{'Toggle','Hold'},Default='Toggle'}):OnChanged(function(aH)ay.Mode=aH end)end av
.Main:AddSlider('PA_FOVSize',{Title='FOV Size',Default=100,Min=30,Max=300,
Rounding=0}):OnChanged(function(aH)ay.FOVSize=aH aD()end)av.Main:AddSlider(
'PA_Strength',{Title='Aimbot Strength',Default=0.3,Min=0.02,Max=1,Rounding=3}):
OnChanged(function(aH)ay.Strength=aH end)if not am then aq(ag.InputBegan,
function(aH)if ay.Key=='Automatic'then return end local aI=(aH.KeyCode and aH.
KeyCode.Name==ay.Key)or(aH.UserInputType and aH.UserInputType.Name==ay.Key)if aI
then if ay.Mode=='Toggle'then ay.Enabled=not ay.Enabled aw.PA_Enabled:SetValue(
ay.Enabled)else aA=true end end end)aq(ag.InputEnded,function(aH)if ay.Key==
'Automatic'then return end local aI=(aH.KeyCode and aH.KeyCode.Name==ay.Key)or(
aH.UserInputType and aH.UserInputType.Name==ay.Key)if aI and ay.Mode=='Hold'then
aA=false end end)end aq(af.RenderStepped,function()aD()if not ay.Enabled then
return end if not am and ay.Mode=='Hold'and not aA and ay.Key~='Automatic'then
return end az=aF()if az then aG(az)end end)aq(ak.OnTeleport,function(aH)if aH==
Enum.TeleportState.Started then aC:Remove()end end)end do local ay={HBE=false,
HBESize=5,TeamCheck=false,WallCheck=false,Farm=false,FarmMethod=
'Teleport to self'}local az,aA={},nil local function aB(aC,aD)if not aC then
return end for aE,aF in ipairs(aC:GetChildren())do if aF:IsA('SelectionBox')and
aF.Name=='ZephyrHitboxOutline'then aF:Destroy()end end if aD then aC.Size=aD.
size aC.Transparency=aD.transparency aC.CanCollide=aD.canCollide aC.Color=aD.
color aC.Material=aD.material end end local function aC(aD)if not aD or not aD.
Character or aD==ak then return false end if ay.TeamCheck and y(aD,ak)then
return false end return B(aD.Character)and aD.Character:FindFirstChild(
'HumanoidRootPart')~=nil end local function aD()local aE={}for aF,aG in ipairs(
ae:GetPlayers())do if aC(aG)then local aH=aG.Character.HumanoidRootPart local aI
=az[aG]if aI and aI.root~=aH then aB(aI.root,aI)aI=nil end aE[aG]=aI or{root=aH,
size=aH.Size,transparency=aH.Transparency,canCollide=aH.CanCollide,color=aH.
Color,material=aH.Material}end end for aF,aG in pairs(az)do if not aE[aF]then
aB(aG.root,aG)end end az=aE end local function aE()for aF,aG in pairs(az)do if
not aC(aF)or(ay.WallCheck and not C(aF.Character))then aB(aF.Character and aF.
Character:FindFirstChild('HumanoidRootPart'),aG)continue end local aH=aF.
Character.HumanoidRootPart aH.Size=q(ay.HBESize,ay.HBESize,ay.HBESize)aH.
Transparency=0.7 aH.Color=Color3.fromRGB(255,50,50)aH.Material=Enum.Material.
ForceField aH.CanCollide=false if not aH:FindFirstChild('ZephyrHitboxOutline')
then local aI=Instance.new('SelectionBox')aI.Name='ZephyrHitboxOutline'aI.
Adornee=aH aI.Color3=Color3.fromRGB(255,50,50)aI.LineThickness=0.05 aI.
Transparency=0.5 aI.Parent=aH end end end local function aF()for aG,aH in pairs(
az)do aB(aH.root,aH)end table.clear(az)end a.cleanup[#a.cleanup+1]=aF av.Main:
AddToggle('PH_Team',{Title='HBE Team Check',Default=false,Callback=function(aG)
ay.TeamCheck=aG if ay.HBE then aD()aE()end end})av.Main:AddToggle('PH_Wall',{
Title='HBE Wall Check',Default=false,Callback=function(aG)ay.WallCheck=aG if ay.
HBE then aE()end end})av.Main:AddToggle('PH_HBE',{Title='HBE',Default=false,
Callback=function(aG)ay.HBE=aG if aG then aD()aE()else aF()end end})av.Main:
AddSlider('PH_Size',{Title='HBE Size',Default=5,Min=1,Max=20,Rounding=1}):
OnChanged(function(aG)ay.HBESize=aG if ay.HBE then aE()end end)av.Main:
AddToggle('PF_Farm',{Title='AutoFarm',Default=false,Callback=function(aG)if aG
then ax('PF_Farm')end ay.Farm=aG aA=nil end})av.Main:AddDropdown('PF_Method',{
Title='AutoFarm Method',Values={'Teleport to self','Teleport to'},Default=
'Teleport to self'}):OnChanged(function(aG)ay.FarmMethod=aG aA=nil end)aq(af.
Heartbeat,function()if not ay.Farm or not B(ak.Character)then return end local
aG=z(ak.Character)if not aG then return end if not aA or not aC(aA)then local aH
=v for aI,aJ in ipairs(ae:GetPlayers())do if aC(aJ)then local aK=x(aJ.Character.
HumanoidRootPart.Position,aG.Position)if aK<aH then aA,aH=aJ,aK end end end end
if not aA then return end if ay.FarmMethod=='Teleport to self'then aA.Character.
HumanoidRootPart.CFrame=aG.CFrame*r(0,0,-5)else aG.CFrame=aA.Character.
HumanoidRootPart.CFrame*r(0,0,3)end end)c.spawn(function()while c.wait(0.5)do if
ay.HBE then aD()aE()end end end)aq(ae.PlayerRemoving,function(aG)if az[aG]then
if aG.Character then aB(aG.Character:FindFirstChild('HumanoidRootPart'),az[aG])
end az[aG]=nil end if aA==aG then aA=nil end end)end do local ay,az,aA=q(0,10000
,0),nil,false ar('Part',{Name='ZephyrSafe',Size=q(100,1,100),Position=ay,
Anchored=true,CanCollide=true,Material=Enum.Material.SmoothPlastic,BrickColor=
BrickColor.new('Really blue'),Parent=workspace})ar('Part',{Name='ZephyrVoid',
Size=q(150,1,150),Position=ay-q(0,10,0),Anchored=true,CanCollide=true,
Transparency=1,Parent=workspace})local aB local function aC(aD,aE)if aB then aB:
Cancel()end aB=ah:Create(aD,TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.
EasingDirection.Out),{CFrame=r(aE)})aB:Play()end a.cleanup[#a.cleanup+1]=
function()if aB then aB:Cancel()end local aD=z(ak.Character)if aA and aD and az
then aD.CFrame=r(az)end end av.Main:AddToggle('SA_Toggle',{Title=
'Safe Area Teleport',Default=false,Callback=function(aD)if aD then ax(
'SA_Toggle')end local aE=ak.Character and z(ak.Character)if not aE then return
end if aD then az=aE.Position aC(aE,ay+q(0,3,0))aA=true else if aB then aB:
Cancel()end if az then aE.CFrame=r(az)end aA=false end end})aq(ak.CharacterAdded
,function(aD)if aA then local aE=aD:WaitForChild('HumanoidRootPart',5)if aE then
aE.CFrame=r(ay+q(0,3,0))end end end)aq(af.Heartbeat,function()if not aA then
return end local aD=ak.Character and z(ak.Character)if aD and x(aD.Position,ay)>
10000 then aD.CFrame=r(ay+q(0,3,0))end end)end do local ay={HBE=false,Size=5,
Farm=false,Method='Teleport to self',Interval=0.1,Distance=5}local az=250*250
local aA={}local aB={}local aC=nil local aD=0 local function aE(aF)if aB[aF]then
return end local aG=z(aF)if not aG then return end aB[aF]={root=aG,size=aG.Size,
trans=aG.Transparency,cc=aG.CanCollide,color=aG.Color,material=aG.Material}end
local function aF(aG)local aH=aB[aG]local aI=aH and aH.root if aI and aH then aI
.Size=aH.size aI.Transparency=aH.trans aI.CanCollide=aH.cc aI.Color=aH.color aI.
Material=aH.material for aJ,aK in ipairs(aI:GetChildren())do if aK:IsA(
'SelectionBox')and aK.Name=='ZephyrHitboxOutline'then aK:Destroy()end end end aA
[aG]=nil aB[aG]=nil end local function aG(aH)local aI=z(aH)if not aI then return
end if aB[aH]and aB[aH].root~=aI then aF(aH)end if aA[aH]==ay.Size then return
end aE(aH)if aA[aH]then for aJ,aK in ipairs(aI:GetChildren())do if aK:IsA(
'SelectionBox')and aK.Name=='ZephyrHitboxOutline'then aK:Destroy()end end end aI
.Size=q(ay.Size,ay.Size,ay.Size)aI.Transparency=0.7 aI.Color=Color3.fromRGB(255,
50,50)aI.Material=Enum.Material.ForceField aI.CanCollide=false local aJ=Instance
.new('SelectionBox')aJ.Name='ZephyrHitboxOutline'aJ.Adornee=aI aJ.Color3=Color3.
fromRGB(255,50,50)aJ.LineThickness=0.05 aJ.Transparency=0.5 aJ.Parent=aI aA[aH]=
ay.Size end local function aH()for aI in pairs(aA)do aF(aI)end table.clear(aA)
table.clear(aB)end a.cleanup[#a.cleanup+1]=aH local function aI()if not B(ak.
Character)then aH()return end local aJ=z(ak.Character)if not aJ then return end
aJ=aJ.Position for aK=1,I do local aL=G[aK]local aM=z(aL)if not aM then if aA[aL
]then aF(aL)end continue end local Q=A(aL)local R=x(aM.Position,aJ)<=az local S=
Q and Q.Health>0 if ay.HBE and R and S then aG(aL)elseif aA[aL]then aF(aL)end
end for aK in pairs(aA)do if not F[aK]then aF(aK)end end end local function aJ()
if not ay.Farm or not B(ak.Character)then return end local aK=z(ak.Character)if
not aK then return end local aL=t()if aL-aD<ay.Interval then return end aD=aL
local aM=aK.Position if ay.Method=='Teleport to self'then local Q=0 for R=1,I do
local S=G[R]local T=A(S)if T and T.Health>0 then local U=z(S)if U and x(U.
Position,aM)<=az then U.CFrame=aK.CFrame*r(math.random(-1,1),0,-ay.Distance+Q)Q=
Q+0.1 end end end else if aC then local Q=A(aC)if not Q or Q.Health<=0 or not F[
aC]then aC=nil end end if not aC then local Q,R=nil,v for S=1,I do local T=G[S]
local U=A(T)if U and U.Health>0 then local V=z(T)if V then local W=x(V.Position,
aM)if W<R then Q,R=T,W end end end end aC=Q end if aC then local Q=z(aC)if Q
then aK.CFrame=Q.CFrame*r(0,0,ay.Distance)end end end end K[#K+1]=function(aK)if
aA[aK]then aF(aK)end if aC==aK then aC=nil end end av.MainNPCS:AddToggle(
'NH_HBE',{Title='HBE',Default=false,Callback=function(aK)ay.HBE=aK if not aK
then aH()end end})av.MainNPCS:AddSlider('NH_Size',{Title='HBE Size',Default=5,
Min=1,Max=20,Rounding=1}):OnChanged(function(aK)ay.Size=aK for aL in pairs(aA)do
aA[aL]=-1 end end)av.MainNPCS:AddToggle('NF_Farm',{Title='AutoFarm',Default=
false,Callback=function(aK)if aK then ax('NF_Farm')end ay.Farm=aK aC=nil end})av
.MainNPCS:AddDropdown('NF_Method',{Title='AutoFarm Method',Values={
'Teleport to self','Teleport to'},Default='Teleport to self'}):OnChanged(
function(aK)ay.Method=aK aC=nil end)av.MainNPCS:AddSlider('NF_Speed',{Title=
'Teleport Speed',Default=0.1,Min=0,Max=1,Rounding=2}):OnChanged(function(aK)ay.
Interval=aK end)av.MainNPCS:AddSlider('NF_Dist',{Title='Teleport Distance',
Default=5,Min=1,Max=20,Rounding=1}):OnChanged(function(aK)ay.Distance=aK end)aq(
af.Heartbeat,aJ)c.spawn(function()while c.wait(0.5)do if ay.HBE then aI()end end
end)end do local ay={Enabled=false,FOV=100,Strength=0.3,ShowFOV=false,BodyPart=
'Head',WallCheck=false,DeathCheck=false,KeyMode=am and'Automatic'or'Toggle',
Keybind='X',YOffset=0.5}local az=500*500 local aA=0.25 local aB={}local aC,aD=
nil,0 local aE=m('Circle',{Thickness=1,Color=Color3.fromRGB(106,202,226),Filled=
false,Transparency=0.7,NumSides=60,Radius=ay.FOV,Position=w(),Visible=false})
local function aF()local aG=w()aE.Position=aG aE.Radius=ay.FOV aE.Visible=ay.
ShowFOV end local function aG(aH,aI)local aJ=aB[aH]local aK=t()if aJ and aK-aJ[2
]<aA then return aJ[1]end local aL=C(aH,aI)aB[aH]={aL,aK}return aL end local 
function aH(aI)if ay.BodyPart=='Head'then return aI:FindFirstChild('Head')elseif
ay.BodyPart=='Body'then return z(aI)else return aI:FindFirstChild('Head')or z(aI
)end end aq(af.RenderStepped,function(aI)if not al then return end aF()if not ay
.Enabled then aC=nil aD=0 return end local aJ=al.CFrame local aK=aJ.Position
local aL=w()if t()>=aD then aD=t()+0.1 local aM,Q=nil,v for R=1,I do local S=G[R
]local T=z(S)if not T then continue end if x(aK,T.Position)>az then continue end
if ay.DeathCheck then local U=A(S)if not U or U.Health<=0 then continue end end
local U=aH(S)if not U then continue end local V=U.Position+q(0,ay.YOffset,0)
local W,X=al:WorldToViewportPoint(V)if not X then continue end local Y=(p(W.X,W.
Y)-aL).Magnitude if Y>ay.FOV or Y>=Q then continue end if ay.WallCheck and not
aG(S,aK)then continue end aM,Q=S,Y end aC=aM end if aC and F[aC]then local aM=
aH(aC)if aM then local Q=aM.Position+q(0,ay.YOffset,0)local R,S=al:
WorldToViewportPoint(Q)if S and(p(R.X,R.Y)-aL).Magnitude<=ay.FOV then al.CFrame=
aJ:Lerp(s(aK,Q),1-(1-ay.Strength)^(math.min(aI or 1/60,0.1)*60))end end end end)
if not am then local function aI(aJ,aK)if aJ.KeyCode and aJ.KeyCode.Name==ay.
Keybind then if ay.KeyMode=='Toggle'and aK then ay.Enabled=not ay.Enabled aw.
NA_Enabled:SetValue(ay.Enabled)elseif ay.KeyMode=='Hold'then ay.Enabled=aK aw.
NA_Enabled:SetValue(aK)end end end aq(ag.InputBegan,function(aJ,aK)if not aK
then aI(aJ,true)end end)aq(ag.InputEnded,function(aJ,aK)if not aK then aI(aJ,
false)end end)end K[#K+1]=function(aI)aB[aI]=nil end av.MainNPCS:AddToggle(
'NA_Enabled',{Title='Enable Aimbot',Default=false,Callback=function(aI)if aI and
aw.PA_Enabled and aw.PA_Enabled.Value then aw.PA_Enabled:SetValue(false)end ay.
Enabled=aI end})av.MainNPCS:AddToggle('NA_ShowFOV',{Title='Show FOV Circle',
Default=false,Callback=function(aI)ay.ShowFOV=aI end})av.MainNPCS:AddToggle(
'NA_Wall',{Title='Wall Check',Default=false,Callback=function(aI)ay.WallCheck=aI
end})av.MainNPCS:AddToggle('NA_Death',{Title='Death Check',Default=false,
Callback=function(aI)ay.DeathCheck=aI end})av.MainNPCS:AddDropdown('NA_Part',{
Title='Target Body Part',Values={'Head','Body','Both'},Default='Head'}):
OnChanged(function(aI)ay.BodyPart=aI end)av.MainNPCS:AddSlider('NA_FOV',{Title=
'FOV Size',Default=100,Min=50,Max=500,Rounding=0}):OnChanged(function(aI)ay.FOV=
aI end)av.MainNPCS:AddSlider('NA_Strength',{Title='Aimbot Strength',Default=0.3,
Min=0.02,Max=1,Rounding=3}):OnChanged(function(aI)ay.Strength=aI end)if not am
then av.MainNPCS:AddDropdown('NA_KeyMode',{Title='Keybind Mode',Values={'Toggle'
,'Hold'},Default='Toggle'}):OnChanged(function(aI)ay.KeyMode=aI end)av.MainNPCS:
AddDropdown('NA_Keybind',{Title='Keybind',Values={'A','B','C','D','E','F','G',
'H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z',
'LeftAlt','LeftControl','LeftShift'},Default='X'}):OnChanged(function(aI)ay.
Keybind=aI end)end aq(ak.OnTeleport,function(aI)if aI==Enum.TeleportState.
Started then aE:Remove()end end)end do local ay={TeamCheck=false,Box=false,
BoxStyle='Normal',Health=false,HealthPos='Overhead',HealthWidth=50,Chams=false,
Tracers=false,TracerOrigin='Bottom',Names=false,Distance=false}local az={}local 
function aA(aB)aB.Box.Visible=false aB.HBOut.Visible=false aB.HBar.Visible=false
aB.Chams.Enabled=false aB.Tracer.Visible=false aB.Name.Visible=false aB.Dist.
Visible=false for aC,aD in ipairs(aB.Corners)do aD.Visible=false end end local 
function aB(aC)if az[aC]then return end local aD={Box=m('Square',{Thickness=1,
Color=Color3.new(1,1,1),Filled=false,Visible=false}),HBOut=m('Square',{Thickness
=1,Color=Color3.new(0,0,0),Filled=true,Visible=false}),HBar=m('Square',{
Thickness=1,Filled=true,Visible=false}),Chams=ar('Highlight',{FillTransparency=
0.78,OutlineTransparency=0.15,Enabled=false}),Tracer=m('Line',{Thickness=1,Color
=Color3.new(1,1,1),Visible=false}),Name=m('Text',{Size=12,Center=true,Color=
Color3.new(1,1,1),Outline=true,OutlineColor=Color3.new(0,0,0),Font=2,Visible=
false}),Dist=m('Text',{Size=11,Center=true,Color=Color3.new(1,1,1),Outline=true,
OutlineColor=Color3.new(0,0,0),Font=2,Visible=false}),Corners={}}for aE=1,8 do
aD.Corners[aE]=m('Line',{Thickness=1,Color=Color3.new(1,1,1),Visible=false})end
aD.Name.Text=aC.Name if aC.Character then aD.Chams.Parent=aC.Character end az[aC
]=aD aD.CharacterConnection=aq(aC.CharacterAdded,function(aE)aD.Chams.Parent=aE
end)end local function aC(aD)local aE=az[aD]if not aE then return end if aE.
CharacterConnection then aE.CharacterConnection:Disconnect()end pcall(function()
aE.Box:Remove()aE.HBOut:Remove()aE.HBar:Remove()aE.Chams:Destroy()aE.Tracer:
Remove()aE.Name:Remove()aE.Dist:Remove()for aF,aG in ipairs(aE.Corners)do aG:
Remove()end end)az[aD]=nil end local function aD(aE,aF,aG,aH,aI,aJ)if not aJ
then for aK,aL in ipairs(aE)do aL.Visible=false end return end local aK=5 local
aL={{aF,aG,aF,aG+aK},{aF,aG,aF+aK,aG},{aF+aH,aG,aF+aH,aG+aK},{aF+aH,aG,aF+aH-aK,
aG},{aF,aG+aI,aF,aG+aI-aK},{aF,aG+aI,aF+aK,aG+aI},{aF+aH,aG+aI,aF+aH,aG+aI-aK},{
aF+aH,aG+aI,aF+aH-aK,aG+aI}}for aM,Q in ipairs(aL)do aE[aM].From=p(Q[1],Q[2])aE[
aM].To=p(Q[3],Q[4])aE[aM].Visible=true end end for aE,aF in ipairs(ae:
GetPlayers())do if aF~=ak then aB(aF)end end aq(ae.PlayerAdded,function(aE)if aE
~=ak then aB(aE)end end)aq(ae.PlayerRemoving,aC)aq(af.RenderStepped,function()
local aE=al.CFrame local aF=aE.Position local aG=al.ViewportSize for aH,aI in
pairs(az)do if not aH.Parent then aC(aH)continue end local aJ=aH.Character if
not aJ or not B(aJ)then aA(aI)continue end if ay.TeamCheck and y(aH,ak)then aA(
aI)continue end local aK=aJ:FindFirstChild('HumanoidRootPart')local aL=A(aJ)if
not aK or not aL then aA(aI)continue end if not(ay.Box or ay.Health or ay.Chams
or ay.Tracers or ay.Names or ay.Distance)then aA(aI)continue end local aM,Q=al:
WorldToViewportPoint(aK.Position)if not Q then aA(aI)continue end local R=al:
WorldToViewportPoint(aK.Position+q(0,3,0))local S=al:WorldToViewportPoint(aK.
Position-q(0,3,0))local T=u(R.Y-S.Y)local U=T*0.5 local V,W=aM.X-U*0.5,aM.Y-T*
0.5 aI.Chams.Enabled=ay.Chams if ay.Chams and aI.Chams.Parent~=aJ then aI.Chams.
Parent=aJ end if ay.Box then if ay.BoxStyle=='Normal'then aI.Box.Size=p(U,T)aI.
Box.Position=p(V,W)aI.Box.Visible=true aD(aI.Corners,V,W,U,T,false)else aI.Box.
Visible=false aD(aI.Corners,V,W,U,T,true)end else aI.Box.Visible=false aD(aI.
Corners,V,W,U,T,false)end if ay.Health then local X=math.clamp(aL.Health/math.
max(aL.MaxHealth,1),0,1)if ay.HealthPos=='Side'then aI.HBOut.Size=p(4,T+2)aI.
HBOut.Position=p(V-6,W-1)aI.HBar.Size=p(2,T*X)aI.HBar.Position=p(V-5,W+T*(1-X))
else local Y=ay.HealthWidth aI.HBOut.Size=p(Y+2,6)aI.HBOut.Position=p(V+(U-Y)*
0.5-1,W-10)aI.HBar.Size=p(Y*X,4)aI.HBar.Position=p(V+(U-Y)*0.5,W-9)end aI.HBar.
Color=E(X)aI.HBOut.Visible=true aI.HBar.Visible=true else aI.HBOut.Visible=false
aI.HBar.Visible=false end if ay.Tracers then aI.Tracer.From=p(aG.X*0.5,ay.
TracerOrigin=='Bottom'and aG.Y or 0)aI.Tracer.To=p(aM.X,aM.Y)aI.Tracer.Visible=
true else aI.Tracer.Visible=false end if ay.Names then aI.Name.Position=p(aM.X,W
-20)aI.Name.Visible=true else aI.Name.Visible=false end if ay.Distance then aI.
Dist.Text=string.format('%.0f studs',(aK.Position-aF).Magnitude)aI.Dist.Position
=p(aM.X,W+T+4)aI.Dist.Visible=true else aI.Dist.Visible=false end end end)av.
Visuals:AddToggle('PV_Box',{Title='Box ESP',Default=false,Callback=function(aE)
ay.Box=aE end})av.Visuals:AddDropdown('PV_BoxSt',{Title='Box Style',Values={
'Normal','Corner'},Default='Normal'}):OnChanged(function(aE)ay.BoxStyle=aE end)
av.Visuals:AddToggle('PV_Health',{Title='Health Bar ESP',Default=false,Callback=
function(aE)ay.Health=aE end})av.Visuals:AddDropdown('PV_HPos',{Title=
'Health Bar Pos',Values={'Overhead','Side'},Default='Overhead'}):OnChanged(
function(aE)ay.HealthPos=aE end)av.Visuals:AddToggle('PV_Team',{Title=
'Team Check',Default=false,Callback=function(aE)ay.TeamCheck=aE end})av.Visuals:
AddToggle('PV_Chams',{Title='Chams',Default=false,Callback=function(aE)ay.Chams=
aE end})av.Visuals:AddToggle('PV_Tracers',{Title='Tracers',Default=false,
Callback=function(aE)ay.Tracers=aE end})av.Visuals:AddToggle('PV_Names',{Title=
'Names',Default=false,Callback=function(aE)ay.Names=aE end})av.Visuals:
AddToggle('PV_Dist',{Title='Distance',Default=false,Callback=function(aE)ay.
Distance=aE end})av.Visuals:AddDropdown('PV_TrOrig',{Title='Tracer Origin',
Values={'Bottom','Top'},Default='Bottom'}):OnChanged(function(aE)ay.TracerOrigin
=aE end)end do local ay={Box=false,BoxStyle='Normal',CornerSize=5,Health=false,
HealthPos='Overhead',HealthWidth=50,Chams=false,Name=false,MaxVisible=50,
MaxRange=500}local az=ay.MaxRange*ay.MaxRange local aA=0.3 local aB={}local aC=
Color3.fromRGB(106,202,226)local aD=Color3.fromRGB(174,145,214)local function aE
(aF)local aG={Box=m('Square',{Thickness=1,Color=Color3.fromRGB(106,202,226),
Filled=false,Visible=false,ZIndex=1}),HBOut=m('Square',{Thickness=1,Color=Color3
.new(0,0,0),Filled=true,Visible=false,ZIndex=1}),HBar=m('Square',{Thickness=1,
Filled=true,Visible=false,ZIndex=2}),Name=m('Text',{Size=12,Center=true,Color=
Color3.fromRGB(106,202,226),Outline=true,OutlineColor=Color3.new(0,0,0),Font=2,
Visible=false,ZIndex=2,Text=aF.Name}),Chams=ar('Highlight',{FillTransparency=
0.78,OutlineTransparency=0.15,Enabled=false,Parent=aF,Adornee=aF}),Corners={}}
for aH=1,8 do aG.Corners[aH]=m('Line',{Thickness=1,Color=Color3.fromRGB(106,202,
226),Visible=false,ZIndex=1})end return aG end local function aF(aG)if not aG
then return end pcall(function()aG.Box:Remove()aG.HBOut:Remove()aG.HBar:Remove()
aG.Name:Remove()aG.Chams:Destroy()for aH,aI in ipairs(aG.Corners)do aI:Remove()
end end)end local function aG(aH)if not aH then return end aH.Box.Visible=false
aH.HBOut.Visible=false aH.HBar.Visible=false aH.Name.Visible=false aH.Chams.
Enabled=false for aI,aJ in ipairs(aH.Corners)do aJ.Visible=false end end local 
function aH(aI,aJ,aK,aL,aM,Q)if not Q then for R,S in ipairs(aI)do S.Visible=
false end return end local R=ay.CornerSize local S={{aJ,aK,aJ,aK+R},{aJ,aK,aJ+R,
aK},{aJ+aL,aK,aJ+aL,aK+R},{aJ+aL,aK,aJ+aL-R,aK},{aJ,aK+aM,aJ,aK+aM-R},{aJ,aK+aM,
aJ+R,aK+aM},{aJ+aL,aK+aM,aJ+aL,aK+aM-R},{aJ+aL,aK+aM,aJ+aL-R,aK+aM}}for T,U in
ipairs(S)do aI[T].From=p(U[1],U[2])aI[T].To=p(U[3],U[4])aI[T].Visible=true end
end K[#K+1]=function(aI)local aJ=aB[aI]if aJ then if aJ.drawings then aF(aJ.
drawings)end aB[aI]=nil end end local aI={}local aJ,aK,aL=0,0,false aq(af.
RenderStepped,function()local aM=ay.Box or ay.Health or ay.Chams or ay.Name if
not aM then if not aL then return end aL=false aJ=0 for Q,R in pairs(aB)do if R.
drawings then aG(R.drawings)end end return end aL=true if not al then return end
local Q=al.CFrame local R=Q.Position local S=t()if S>=aJ then aJ=S+0.2 table.
clear(aI)for T,U in pairs(aB)do if U.drawings then if S-(U.lastVisible or S)>5
then aF(U.drawings)U.drawings=nil else aG(U.drawings)end end end local T=0 for U
=1,I do local V=G[U]local W=z(V)if not W then continue end local X=x(R,W.
Position)if X>az then local Y=aB[V]if Y and Y.drawings then aG(Y.drawings)end
continue end local Y=A(V)if not Y or Y.Health<=0 then local Z=aB[V]if Z and Z.
drawings then aG(Z.drawings)end continue end local Z=aB[V]if not Z then Z={
drawings=nil,visTime=0,visResult=false}aB[V]=Z end Z.distSq=X Z.root=W Z.hum=Y Z
.model=V T=T+1 aI[T]=Z end table.sort(aI,function(U,V)return U.distSq<V.distSq
end)aK=math.min(T,ay.MaxVisible)for U=aK+1,T do local V=aI[U]if V.drawings then
aG(V.drawings)end aI[U]=nil end end local T=4 for U=1,aK do local V=aI[U]local W
=V.model local X=V.root local Y=V.hum if not F[W]or not X.Parent or not Y.Parent
or Y.Health<=0 then if V.drawings then aG(V.drawings)end continue end local Z,_=
al:WorldToViewportPoint(X.Position)if not _ then if V.drawings then aG(V.
drawings)end continue end V.lastVisible=S if not V.drawings then V.drawings=aE(W
)end local aN=V.drawings if ay.Chams then if S-V.visTime>aA and T>0 then T-=1 V.
visResult=C(W,R)V.visTime=S end aN.Chams.FillColor=V.visResult and aC or aD aN.
Chams.OutlineColor=aN.Chams.FillColor aN.Chams.Enabled=true if aN.Chams.Parent~=
W then aN.Chams.Parent=W end else aN.Chams.Enabled=false end local aO=al:
WorldToViewportPoint(X.Position+q(0,3,0))local aP=al:WorldToViewportPoint(X.
Position-q(0,3,0))local aQ=u(aO.Y-aP.Y)local aR=aQ*0.5 local aS,aT=Z.X-aR*0.5,Z.
Y-aQ*0.5 if ay.Name then aN.Name.Position=p(Z.X,aT-20)aN.Name.Visible=true else
aN.Name.Visible=false end if ay.Box then if ay.BoxStyle=='Normal'then aN.Box.
Size=p(aR,aQ)aN.Box.Position=p(aS,aT)aN.Box.Visible=true aH(aN.Corners,aS,aT,aR,
aQ,false)else aN.Box.Visible=false aH(aN.Corners,aS,aT,aR,aQ,true)end else aN.
Box.Visible=false aH(aN.Corners,aS,aT,aR,aQ,false)end if ay.Health then local aU
=math.clamp(Y.Health/math.max(Y.MaxHealth,1),0,1)if ay.HealthPos=='Side'then aN.
HBOut.Size=p(4,aQ+2)aN.HBOut.Position=p(aS-6,aT-1)aN.HBar.Size=p(2,aQ*aU)aN.HBar
.Position=p(aS-5,aT+aQ*(1-aU))else local aV=ay.HealthWidth aN.HBOut.Size=p(aV+2,
4)aN.HBOut.Position=p(aS+(aR-aV)*0.5-1,aT-10)aN.HBar.Size=p(aV*aU,2)aN.HBar.
Position=p(aS+(aR-aV)*0.5,aT-9)end aN.HBar.Color=E(aU)aN.HBOut.Visible=true aN.
HBar.Visible=true else aN.HBOut.Visible=false aN.HBar.Visible=false end end end)
av.VisualsNPCS:AddToggle('NV_Box',{Title='Box ESP',Default=false,Callback=
function(aM)ay.Box=aM end})av.VisualsNPCS:AddDropdown('NV_BoxSt',{Title=
'Box Style',Values={'Normal','Corner'},Default='Normal'}):OnChanged(function(aM)
ay.BoxStyle=aM end)av.VisualsNPCS:AddToggle('NV_Name',{Title='Name ESP',Default=
false,Callback=function(aM)ay.Name=aM end})av.VisualsNPCS:AddToggle('NV_Health',
{Title='Health Bar ESP',Default=false,Callback=function(aM)ay.Health=aM end})av.
VisualsNPCS:AddToggle('NV_Chams',{Title='Chams',Default=false,Callback=function(
aM)ay.Chams=aM end})av.VisualsNPCS:AddDropdown('NV_HPos',{Title='Health Bar Pos'
,Values={'Overhead','Side'},Default='Overhead'}):OnChanged(function(aM)ay.
HealthPos=aM end)av.VisualsNPCS:AddSlider('NV_MaxVis',{Title='Max Visible NPCs',
Default=50,Min=10,Max=200,Rounding=0}):OnChanged(function(aM)ay.MaxVisible=aM
end)av.VisualsNPCS:AddSlider('NV_Range',{Title='ESP Range',Default=500,Min=50,
Max=2000,Rounding=0}):OnChanged(function(aM)ay.MaxRange=aM az=aM*aM end)end do
local ay={Enabled=false,Names=false,Chams=false,MaxDist=100}local az=ay.MaxDist*
ay.MaxDist local aA={}local function aB(aC)local aD=aC.Parent if not aD or aD==
workspace then return nil end if aD.Name=='Proximity'or aD.Name=='Prompt'then aD
=aD.Parent if not aD or aD==workspace then return nil end end return aD end
local function aC(aD,aE)if aD.ActionText~=''then return aD.ActionText end if aD.
ObjectText~=''then return aD.ObjectText end return aE.Name end local function aD
(aE)local aF=aB(aE)if not aF or aA[aF]then return end local aG={name=m('Text',{
Size=12,Center=true,Color=Color3.new(0,1,0),Outline=true,OutlineColor=Color3.
new(0,0,0),Font=2,Visible=false,ZIndex=2,Text=aC(aE,aF)}),chams=ar('Highlight',{
FillTransparency=0.78,OutlineTransparency=0.15,FillColor=Color3.new(0,1,0),
OutlineColor=Color3.new(0,1,0),Enabled=false,Parent=aF,Adornee=aF})}aA[aF]=aG
end local function aE(aF)local aG=aA[aF]if not aG then return end pcall(function
()aG.name:Remove()aG.chams:Destroy()end)aA[aF]=nil end local function aF()for aG
in pairs(aA)do aE(aG)end end local function aG()for aH,aI in ipairs(workspace:
GetDescendants())do if aI:IsA('ProximityPrompt')then aD(aI)end end end aq(
workspace.DescendantAdded,function(aH)if ay.Enabled and aH:IsA('ProximityPrompt'
)then c.defer(function()if aH.Parent then aD(aH)end end)end end)aq(workspace.
DescendantRemoving,function(aH)if aH:IsA('ProximityPrompt')then local aI=aB(aH)
if aI then aE(aI)end end aE(aH)end)aq(af.RenderStepped,function()if not ay.
Enabled then return end local aH=al.CFrame.Position for aI,aJ in pairs(aA)do if
not aI.Parent then aE(aI)continue end local aK=(aI:IsA('Model')and(aI.
PrimaryPart or aI:FindFirstChildWhichIsA('BasePart')))or(aI:IsA('BasePart')and
aI)or nil if not aK then aJ.name.Visible=false aJ.chams.Enabled=false continue
end if x(aK.Position,aH)>az then aJ.name.Visible=false aJ.chams.Enabled=false
continue end aJ.chams.Enabled=ay.Chams if ay.Names then local aL,aM=al:
WorldToViewportPoint(aK.Position)aJ.name.Position=p(aL.X,aL.Y)aJ.name.Visible=aM
else aJ.name.Visible=false end end end)av.VisualsNPCS:AddToggle('IE_Enabled',{
Title='Item ESP',Default=false,Callback=function(aH)ay.Enabled=aH if aH then aG(
)else aF()end end})av.VisualsNPCS:AddToggle('IE_Names',{Title='Item Names',
Default=false,Callback=function(aH)ay.Names=aH end})av.VisualsNPCS:AddToggle(
'IE_Chams',{Title='Item Chams',Default=false,Callback=function(aH)ay.Chams=aH
end})av.VisualsNPCS:AddSlider('IE_Dist',{Title='ESP Distance',Default=100,Min=10
,Max=500,Rounding=0}):OnChanged(function(aH)ay.MaxDist=aH az=aH*aH end)end local
ay=type(readfile)=='function'and type(writefile)=='function'and type(makefolder)
=='function'and type(isfolder)=='function'and type(listfiles)=='function'av.
Settings:AddParagraph({Title='Compatibility',Content=(l>0 and'Native UI overlay'
or'Drawing overlay')..(ay and' | Local storage available'or
' | Session-only settings')})av.Settings:AddButton({Title='Unload Zephyr',
Callback=function()aa:Destroy()end})if ad and ay then local az,aA=pcall(function
()ad:SetLibrary(aa)ad:SetFolder('ZephyrUniversal')ad:BuildInterfaceSection(av.
Settings)end)if not az then a.record(aA)end end if ac and ay then local az,aA=
pcall(function()ac:SetLibrary(aa)ac:IgnoreThemeSettings()ac:SetIgnoreIndexes({})
ac:SetFolder('ZephyrUniversal/specific-game')ac:BuildConfigSection(av.Settings)
ac:LoadAutoloadConfig()end)if not az then a.record(aA)end end au:SelectTab(1)aq(
af.RenderStepped,n)aq(ak.OnTeleport,function(az)if az==Enum.TeleportState.
Started then f()end end)a.ready=true end)if not aa then a.record(ab)end if not
aa or not a.ready then f()end

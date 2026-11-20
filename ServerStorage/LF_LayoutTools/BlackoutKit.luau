local K={}
local CS=game:GetService("CollectionService")
K.CHEV="rbxassetid://128598121432273"
K.WALL=Color3.fromRGB(70,86,130) K.FLOOR=Color3.fromRGB(52,64,98) K.LIME=Color3.fromRGB(180,255,70)
function K.root() return workspace.Map_LiveFire:FindFirstChild("Arena") end
function K.O() return K.root().Origin.CFrame end
function K.F(par,name) local f=par:FindFirstChild(name) if not f then f=Instance.new("Folder") f.Name=name f.Parent=par end return f end
local function style(p,m)
 if m=="lime" then p.Material=Enum.Material.SmoothPlastic p.MaterialVariant="VS_Lime" p.Color=Color3.new(1,1,1)
 elseif m=="limeN" then p.Material=Enum.Material.Neon p.Color=K.LIME p.CastShadow=false
 elseif m=="floor" then p.Material=Enum.Material.Concrete p.MaterialVariant="VS_Floor" p.Color=K.FLOOR
 else p.Material=Enum.Material.SmoothPlastic p.MaterialVariant="VS_Navy" p.Color=Color3.new(1,1,1) end
 p.TopSurface=Enum.SurfaceType.Smooth p.BottomSurface=Enum.SurfaceType.Smooth end
function K.box(par,name,x0,x1,y0,y1,z0,z1,m)
 if x0>x1 then x0,x1=x1,x0 end if y0>y1 then y0,y1=y1,y0 end if z0>z1 then z0,z1=z1,z0 end
 local p=Instance.new("Part") p.Name=name p.Anchored=true p.Size=Vector3.new(x1-x0,y1-y0,z1-z0)
 p.CFrame=K.O()*CFrame.new((x0+x1)/2,(y0+y1)/2,(z0+z1)/2) style(p,m) p.Parent=par return p end
function K.mass(par,name,x0,x1,z0,z1,y0,h) local b=K.box(par,name,x0,x1,y0,y0+h,z0,z1,"wall") K.box(par,name.."Top",x0,x1,y0+h,y0+h+0.6,z0,z1,"lime") return b end
function K.lowwall(par,x0,x1,z0,z1,y0,h) K.box(par,"LowWall",x0,x1,y0,y0+h,z0,z1,"wall") K.box(par,"LowWallCap",x0,x1,y0+h,y0+h+0.5,z0,z1,"lime") end
function K.wall(par,x0,x1,z0,z1,y0,h) -- window wall along its long axis
 if x0>x1 then x0,x1=x1,x0 end if z0>z1 then z0,z1=z1,z0 end
 local alongX=(x1-x0)>=(z1-z0) local a0,a1=alongX and x0 or z0, alongX and x1 or z1
 local function seg(a,b,y,yy) if alongX then K.box(par,"Wall",a,b,y,yy,z0,z1,"wall") else K.box(par,"Wall",x0,x1,y,yy,a,b,"wall") end end
 local wy0,wy1=y0+5,y0+h-4 local a=a0 local i=0
 while a<a1-0.01 do local b=math.min(a+6,a1) if i%2==0 or b-a<6 or wy1-wy0<3 then seg(a,b,y0,y0+h) else seg(a,b,y0,wy0) seg(a,b,wy1,y0+h) end a=b i+=1 end
 if alongX then K.box(par,"WallCap",x0,x1,y0+h,y0+h+0.6,z0-0.1,z1+0.1,"lime") else K.box(par,"WallCap",x0-0.1,x1+0.1,y0+h,y0+h+0.6,z0,z1,"lime") end end
function K.frameX(par,x0,x1,z,y0,h) K.box(par,"Frame",x0,x0+2,y0,y0+h,z-1,z+1,"lime") K.box(par,"Frame",x1-2,x1,y0,y0+h,z-1,z+1,"lime") K.box(par,"Frame",x0,x1,y0+h-2,y0+h,z-1,z+1,"lime") end
function K.frameZ(par,x,z0,z1,y0,h) K.box(par,"Frame",x-1,x+1,y0,y0+h,z0,z0+2,"lime") K.box(par,"Frame",x-1,x+1,y0,y0+h,z1-2,z1,"lime") K.box(par,"Frame",x-1,x+1,y0+h-2,y0+h,z0,z1,"lime") end
-- wedge: (tx,tz) = centre of the HIGH edge, dir = downhill unit vector (local), lime=true for a lime diagonal, boost=speed for a chevron vehicle ramp
function K.wedge(par,tx,tz,dir,run,rise,w,base,lime,boost)
 local O=K.O()
 local Tp=Vector3.new(tx,base+rise,tz) local Bp=Tp+dir*run Bp=Vector3.new(Bp.X,base,Bp.Z)
 local c=Vector3.new((Tp.X+Bp.X)/2,base+rise/2,(Tp.Z+Bp.Z)/2)
 local wd=Instance.new("WedgePart") wd.Name=lime and "DiagWedge" or "RampMass" wd.Anchored=true wd.Size=Vector3.new(w,rise,run)
 wd.CFrame=O*CFrame.lookAt(c,c+dir) style(wd,lime and "lime" or "wall") wd.Parent=par
 if boost then
  local d=(Tp-Bp) local L=d.Magnitude d=d.Unit local right=d:Cross(Vector3.yAxis).Unit local n=right:Cross(d) if n.Y<0 then n=-n end
  local sc=(Tp+Bp)/2-n*0.45
  local s=Instance.new("Part") s.Name="VehicleRamp" s.Anchored=true s.Size=Vector3.new(w,1,L) s.CFrame=O*CFrame.lookAt(sc,sc-d,n) style(s,"lime") s.Parent=par
  local wd2=O:VectorToWorldSpace(d)
  for _,p in ipairs({s,wd}) do p:SetAttribute("RampBoost",boost) p:SetAttribute("RampDir",wd2) end
  local t=Instance.new("Texture") t.Name="Chevrons" t.Texture=K.CHEV t.Face=Enum.NormalId.Top t.StudsPerTileU=w-4 t.StudsPerTileV=9.9 t.OffsetStudsU=2 t.Color3=Color3.new(1,1,1) t.Parent=s
  CS:AddTag(t,"RampChevron") end
 return wd end
function K.pad(par,x,y,z,target)
 local p=K.box(par,"JumpPad",x-4,x+4,y,y+0.4,z-4,z+4,"lime") K.box(par,"JumpPadGlow",x-2.5,x+2.5,y+0.4,y+0.5,z-2.5,z+2.5,"limeN")
 p:SetAttribute("PadTarget",K.O():PointToWorldSpace(target)) CS:AddTag(p,"JumpPad")
 local l=Instance.new("PointLight",p) l.Color=K.LIME l.Range=14 l.Brightness=1.5 return p end
-- ===== shaped wall pieces (upright; built in a local frame: u = length axis, v = thickness) =====
local function lbox(par,base,name,u0,u1,y0,y1,v0,v1,m)
 if u0>u1 then u0,u1=u1,u0 end if v0>v1 then v0,v1=v1,v0 end
 local p=Instance.new("Part") p.Name=name p.Anchored=true p.Size=Vector3.new(u1-u0,y1-y0,v1-v0)
 p.CFrame=base*CFrame.new((u0+u1)/2,(y0+y1)/2,(v0+v1)/2) style(p,m) p.Parent=par return p end
local function lfin(par,base,name,u0,u1,y0,h,v0,v1,highAtU1,m) -- upright triangle: rises along u
 local w=Instance.new("WedgePart") w.Name=name w.Anchored=true w.Size=Vector3.new(math.abs(v1-v0),h,math.abs(u1-u0))
 local c=Vector3.new((u0+u1)/2,y0+h/2,(v0+v1)/2)
 local dir=highAtU1 and Vector3.new(-1,0,0) or Vector3.new(1,0,0) -- wedge front (look) = low end
 w.CFrame=base*CFrame.lookAt(c,c+dir) style(w,m) w.Parent=par return w end
function K.shape(par,kind,cx,cz,rot,L,H,t,y0)
 local base=K.O()*CFrame.new(cx,y0 or 0,cz)*CFrame.Angles(0,rot,0)
 local a,b=-L/2,L/2 local v0,v1=-t/2,t/2
 if kind=="step" then
  local hs={H,H*0.68,H*0.38} for i=1,3 do local u0=a+(i-1)*L/3 local u1=a+i*L/3 lbox(par,base,"StepWall",u0,u1,0,hs[i],v0,v1,"wall") lbox(par,base,"StepCap",u0,u1,hs[i],hs[i]+0.6,v0-0.05,v1+0.05,"lime") end
 elseif kind=="slopetop" then
  lbox(par,base,"SlopeWall",a,b,0,H*0.55,v0,v1,"wall") lfin(par,base,"SlopeTop",a,b,H*0.55,H*0.45,v0,v1,true,"lime")
 elseif kind=="portal" then
  local side=L*0.24 local top=H*0.68
  lbox(par,base,"Portal",a,a+side,0,H,v0,v1,"wall") lbox(par,base,"Portal",b-side,b,0,H,v0,v1,"wall") lbox(par,base,"Portal",a+side,b-side,top,H,v0,v1,"wall")
  lbox(par,base,"PortalTrim",a+side,b-side,top-0.6,top,v0-0.1,v1+0.1,"lime") lbox(par,base,"PortalCap",a,b,H,H+0.6,v0-0.05,v1+0.05,"lime")
 elseif kind=="L" then
  lbox(par,base,"LWall",a,b,0,H,v0,v1,"wall") lbox(par,base,"LCap",a,b,H,H+0.6,v0-0.05,v1+0.05,"lime")
  lbox(par,base,"LWall",b-t,b,0,H,v1,v1+L*0.5,"wall") lbox(par,base,"LCap",b-t,b,H,H+0.6,v1,v1+L*0.5,"lime")
 elseif kind=="fin" then
  lfin(par,base,"Fin",a,b,0,H,v0,v1,true,"lime") lbox(par,base,"FinBase",a,b,0,1.2,v0-0.6,v1+0.6,"wall")
 elseif kind=="notch" then
  local q=L/4 lbox(par,base,"NotchWall",a,a+q,0,H,v0,v1,"wall") lbox(par,base,"NotchWall",b-q,b,0,H,v0,v1,"wall") lbox(par,base,"NotchWall",a+q,b-q,0,H*0.5,v0,v1,"wall")
  lbox(par,base,"NotchCap",a,a+q,H,H+0.6,v0-0.05,v1+0.05,"lime") lbox(par,base,"NotchCap",b-q,b,H,H+0.6,v0-0.05,v1+0.05,"lime") lbox(par,base,"NotchCap",a+q,b-q,H*0.5,H*0.5+0.6,v0-0.05,v1+0.05,"lime")
 elseif kind=="zig" then
  lbox(par,base,"ZigWall",a,a+L*0.55,0,H,v0-t*0.9,v1-t*0.9,"wall") lbox(par,base,"ZigWall",b-L*0.55,b,0,H*0.75,v0+t*0.9,v1+t*0.9,"wall")
  lbox(par,base,"ZigCap",a,a+L*0.55,H,H+0.6,v0-t*0.9-0.05,v1-t*0.9+0.05,"lime") lbox(par,base,"ZigCap",b-L*0.55,b,H*0.75,H*0.75+0.6,v0+t*0.9-0.05,v1+t*0.9+0.05,"lime")
 end
end
-- footprint half-extents (local u,v) of a shape for spacing checks
function K.shapeExtent(kind,L,t) if kind=="L" then return L/2,(t/2+L*0.5) elseif kind=="zig" then return L/2,t*1.5 else return L/2,t/2 end end
-- ===== NIGHT HELPERS =====
K.HAZ="rbxassetid://83353144711842" K.CHK="rbxassetid://109129574912807"
function K.slab(par,name,x0,x1,z0,z1,top,th) th=th or 10 return K.mass(par,name,x0,x1,z0,z1,top-0.6-th,th) end
function K.leg(par,x0,x1,z0,z1,top,th) th=th or 10 K.box(par,"Leg",x0,x1,0,top-0.6-th,z0,z1,"wall") end
function K.tex(p,id,face,tile,trans) local t=Instance.new("Texture") t.Texture=id t.Face=face or Enum.NormalId.Top t.StudsPerTileU=tile t.StudsPerTileV=tile t.Color3=Color3.new(1,1,1) t.Transparency=trans or 0 t.Parent=p return t end
function K.checker(par,x0,x1,z0,z1,top) local p=K.box(par,"Checker",x0,x1,top,top+0.06,z0,z1,"lime") p.CanCollide=false p.CanQuery=false K.tex(p,K.CHK,Enum.NormalId.Top,16) p.Transparency=1 return p end
function K.hazard(par,x0,x1,z0,z1,top) local p=K.box(par,"HazardEdge",x0,x1,top,top+0.08,z0,z1,"lime") p.CanQuery=false K.tex(p,K.HAZ,Enum.NormalId.Top,6) return p end
-- lime outline rectangle on a vertical face. axis="x": plane x=c (u=z), axis="z": plane z=c (u=x); dir = +1/-1 outward
function K.outline(par,axis,c,dir,u0,u1,y0,y1,w)
 w=w or 1.4 local d0,d1 if dir>0 then d0,d1=c,c+0.35 else d0,d1=c-0.35,c end
 local function bar(a0,a1,b0,b1) if axis=="x" then K.box(par,"Outline",d0,d1,b0,b1,a0,a1,"lime") else K.box(par,"Outline",a0,a1,b0,b1,d0,d1,"lime") end end
 bar(u0,u1,y0,y0+w) bar(u0,u1,y1-w,y1) bar(u0,u0+w,y0,y1) bar(u1-w,u1,y0,y1) end
function K.sign(p,face,text,size)
 local g=Instance.new("SurfaceGui") g.Face=face g.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud g.PixelsPerStud=size or 12 g.LightInfluence=0.3 g.Parent=p
 local l=Instance.new("TextLabel",g) l.Size=UDim2.fromScale(1,1) l.BackgroundTransparency=1 l.Text=text l.TextScaled=true l.FontFace=Font.fromEnum(Enum.Font.GothamBlack) l.TextColor3=K.LIME l.TextStrokeTransparency=0.6 l.TextStrokeColor3=Color3.fromRGB(28,36,74) return g end
return K

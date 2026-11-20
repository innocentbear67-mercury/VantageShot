local K={}
K.root=workspace.Map_LiveFire:FindFirstChild("Arena")
local MV={white="VS_White",lime="VS_Lime",floor="VS_Floor",road="VS_Floor"}
local BM={white=Enum.Material.SmoothPlastic,lime=Enum.Material.SmoothPlastic,floor=Enum.Material.Concrete,road=Enum.Material.Concrete,
 blue=Enum.Material.Neon,red=Enum.Material.Neon,glow=Enum.Material.Neon,glass=Enum.Material.Glass,limeN=Enum.Material.Neon}
local COL={white=Color3.new(1,1,1),lime=Color3.new(1,1,1),floor=Color3.new(1,1,1),road=Color3.fromRGB(176,180,188),
 blue=Color3.fromRGB(180,255,70),red=Color3.fromRGB(180,255,70),glow=Color3.fromRGB(240,246,255),glass=Color3.fromRGB(120,190,255),limeN=Color3.fromRGB(180,255,70)}
function K.B(par,name,x0,x1,y0,y1,z0,z1,m)
 if x0>x1 then x0,x1=x1,x0 end if z0>z1 then z0,z1=z1,z0 end if y0>y1 then y0,y1=y1,y0 end
 local p=Instance.new("Part") p.Name=name p.Anchored=true
 p.Size=Vector3.new(x1-x0,y1-y0,z1-z0) p.CFrame=CFrame.new((x0+x1)/2,(y0+y1)/2,(z0+z1)/2)
 m=m or "white" p.Material=BM[m] p.Color=COL[m] if MV[m] then p.MaterialVariant=MV[m] end
 if m=="blue" or m=="red" or m=="glow" or m=="limeN" then p.CastShadow=false end
 if m=="glass" then p.Transparency=0.55 p.CastShadow=false end
 p.TopSurface=Enum.SurfaceType.Smooth p.BottomSurface=Enum.SurfaceType.Smooth p.Parent=par return p end
function K.F(par,name) local f=Instance.new("Folder") f.Name=name f.Parent=par return f end
-- wall along X at z (thickness t), from y0 height h, with door gaps {centre,width}
function K.wallX(par,name,x0,x1,z,y0,h,doors,t,m)
 t=t or 2 if x0>x1 then x0,x1=x1,x0 end doors=doors or {}
 table.sort(doors,function(a,b) return a[1]<b[1] end)
 local cur=x0
 for _,d in ipairs(doors) do local a,b=d[1]-d[2]/2,d[1]+d[2]/2
  if a>cur then K.B(par,name,cur,a,y0,y0+h,z-t/2,z+t/2,m) end
  local dh=d[3] or 10 if dh<h then K.B(par,name.."Lintel",a,b,y0+dh,y0+h,z-t/2,z+t/2,m) end
  K.B(par,"DoorFrame",a-0.6,a,y0,y0+dh+0.6,z-t/2-0.15,z+t/2+0.15,"lime") K.B(par,"DoorFrame",b,b+0.6,y0,y0+dh+0.6,z-t/2-0.15,z+t/2+0.15,"lime")
  K.B(par,"DoorFrame",a,b,y0+dh,y0+dh+0.6,z-t/2-0.15,z+t/2+0.15,"lime")
  cur=b end
 if cur<x1 then K.B(par,name,cur,x1,y0,y0+h,z-t/2,z+t/2,m) end
end
function K.wallZ(par,name,z0,z1,x,y0,h,doors,t,m)
 t=t or 2 if z0>z1 then z0,z1=z1,z0 end doors=doors or {}
 table.sort(doors,function(a,b) return a[1]<b[1] end)
 local cur=z0
 for _,d in ipairs(doors) do local a,b=d[1]-d[2]/2,d[1]+d[2]/2
  if a>cur then K.B(par,name,x-t/2,x+t/2,y0,y0+h,cur,a,m) end
  local dh=d[3] or 10 if dh<h then K.B(par,name.."Lintel",x-t/2,x+t/2,y0+dh,y0+h,a,b,m) end
  K.B(par,"DoorFrame",x-t/2-0.15,x+t/2+0.15,y0,y0+dh+0.6,a-0.6,a,"lime") K.B(par,"DoorFrame",x-t/2-0.15,x+t/2+0.15,y0,y0+dh+0.6,b,b+0.6,"lime")
  K.B(par,"DoorFrame",x-t/2-0.15,x+t/2+0.15,y0+dh,y0+dh+0.6,a,b,"lime")
  cur=b end
 if cur<z1 then K.B(par,name,x-t/2,x+t/2,y0,y0+h,cur,z1,m) end
end
-- stairs: start (x,z) at y0 going in direction (dx,dz) unit axis, climbing to y1, width w. rise 1, run 1.6
function K.stairs(par,x,z,dx,dz,y0,y1,w,m)
 local n=math.ceil(y1-y0) local run=1.6
 for i=1,n do local top=math.min(y0+i,y1)
  local a=(i-1)*run local b=i*run
  if dx~=0 then local xa,xb=x+dx*a,x+dx*b K.B(par,"Step",xa,xb,y0,top,z-w/2,z+w/2,m or "floor")
  else local za,zb=z+dz*a,z+dz*b K.B(par,"Step",x-w/2,x+w/2,y0,top,za,zb,m or "floor") end end
 -- lime nosing line on side
 return n*run end
-- railing: posts + lime top rail along a line at height y (x0,z0)->(x1,z1) axis aligned
function K.rail(par,x0,z0,x1,z1,y)
 if x0==x1 then K.B(par,"Rail",x0-0.3,x0+0.3,y+2.8,y+3.4,z0,z1,"lime") for z=math.min(z0,z1),math.max(z0,z1),6 do K.B(par,"RailPost",x0-0.25,x0+0.25,y,y+2.8,z-0.25,z+0.25,"white") end
 else K.B(par,"Rail",x0,x1,y+2.8,y+3.4,z0-0.3,z0+0.3,"lime") for x=math.min(x0,x1),math.max(x0,x1),6 do K.B(par,"RailPost",x-0.25,x+0.25,y,y+2.8,z0-0.25,z0+0.25,"white") end end
end
-- grapple anchor marker (blue ring) at position facing axis
function K.anchor(par,x,y,z) do return end
 local n=K.B(par,"AnchorNode",x-2,x+2,y-2,y+2,z-2,z+2,"white")
 local r=Instance.new("Part") r.Name="AnchorRing" r.Shape=Enum.PartType.Cylinder r.Anchored=true r.Material=Enum.Material.Neon r.Color=COL.blue r.CastShadow=false
 r.Size=Vector3.new(0.6,7,7) r.CFrame=CFrame.new(x,y,z)*CFrame.Angles(0,0,math.rad(90)) r.Parent=par
 local l=Instance.new("PointLight",r) l.Range=10 l.Brightness=1 l.Color=COL.blue
end
function K.light(par,x0,x1,y,z0,z1,face,range)
 local p=K.B(par,"LightStrip",x0,x1,y-0.25,y+0.25,z0,z1,"glow")
 local l=Instance.new("SurfaceLight",p) l.Face=face or Enum.NormalId.Bottom l.Range=range or 22 l.Brightness=1.6 l.Angle=120 l.Color=COL.glow return p end
return K

local M={}
local G=2 M.G=G
local C={W=Color3.fromRGB(228,230,230),D=Color3.fromRGB(56,60,66),T=Color3.fromRGB(92,96,100),MID=Color3.fromRGB(140,144,148),
Y=Color3.fromRGB(222,178,46),CONT=Color3.fromRGB(64,68,72),SLAB=Color3.fromRGB(168,168,164),SAND=Color3.fromRGB(146,136,108),CAMO=Color3.fromRGB(72,82,60),RED=Color3.fromRGB(230,40,30)}
M.C=C
local MAT=Enum.Material
function M.style(p,k)
 p.MaterialVariant=""
 if k=="w" then p.Material=MAT.Concrete p.MaterialVariant="VS_WhitePrecast" p.Color=Color3.fromRGB(234,235,231)
 elseif k=="p" then p.Material=MAT.Concrete p.MaterialVariant="VS_WhitePrecast" p.Color=Color3.fromRGB(236,236,232)
 elseif k=="d" then p.Material=MAT.Metal p.MaterialVariant="VS_Gunmetal" p.Color=C.D p.Reflectance=0.06
 elseif k=="t" then p.Material=MAT.DiamondPlate p.MaterialVariant="VS_TreadPlate" p.Color=C.T
 elseif k=="m" then p.Material=MAT.Metal p.MaterialVariant="VS_PaintedSteel" p.Color=C.MID
 elseif k=="y" then p.Material=MAT.Metal p.Color=C.Y
 elseif k=="c" then p.Material=MAT.Metal p.MaterialVariant="VS_CorrugatedSteel" p.Color=C.CONT
 elseif k=="s" then p.Material=MAT.Pavement p.MaterialVariant="VS_ConcreteSlab" p.Color=C.SLAB
 elseif k=="b" then p.Material=MAT.Fabric p.Color=C.SAND
 elseif k=="camo" then p.Material=MAT.Fabric p.Color=C.CAMO
 elseif k=="g" then p.Material=MAT.Glass p.Color=Color3.fromRGB(70,80,88) p.Transparency=0.35 p.Reflectance=0.15
 elseif k=="red" then p.Material=MAT.Neon p.Color=C.RED p.CanCollide=false p.CastShadow=false
 elseif k=="void" then p.Material=MAT.SmoothPlastic p.Color=Color3.fromRGB(22,24,27)
 end
 return p
end
function M.model(par,name) local m=Instance.new("Model") m.Name=name m.Parent=par return m end
function M.box(par,name,x1,y1,z1,x2,y2,z2,k)
 local sx,sy,sz=math.abs(x2-x1),math.abs(y2-y1),math.abs(z2-z1)
 if sx<0.01 or sy<0.01 or sz<0.01 then return nil end
 local p=Instance.new("Part") p.Name=name p.Anchored=true p.TopSurface=Enum.SurfaceType.Smooth p.BottomSurface=Enum.SurfaceType.Smooth
 p.Size=Vector3.new(sx,sy,sz) p.CFrame=CFrame.new((x1+x2)/2,(y1+y2)/2,(z1+z2)/2)
 M.style(p,k or "w") p.Parent=par return p
end
function M.part(par,name,size,cf,k,shape)
 local p=Instance.new("Part") p.Name=name p.Anchored=true p.Size=size p.CFrame=cf
 if shape then p.Shape=shape end p.TopSurface=Enum.SurfaceType.Smooth p.BottomSurface=Enum.SurfaceType.Smooth
 M.style(p,k or "w") p.Parent=par return p
end
-- generic wall with rectangular holes. axis "x": runs along x at z=c ; holes {{a,b,lo,hi}}
local function wall(par,axis,a1,a2,c,t,y1,y2,holes,k,name)
 holes=holes or {}
 local bp={a1,a2}
 for _,h in ipairs(holes) do table.insert(bp,math.clamp(h[1],a1,a2)) table.insert(bp,math.clamp(h[2],a1,a2)) end
 table.sort(bp)
 local out={}
 for i=1,#bp-1 do local u,v=bp[i],bp[i+1]
  if v-u>0.05 then local mid=(u+v)/2
   local cuts={}
   for _,h in ipairs(holes) do if mid>h[1] and mid<h[2] then table.insert(cuts,{math.max(h[3],y1),math.min(h[4],y2)}) end end
   table.sort(cuts,function(p,q) return p[1]<q[1] end)
   local y=y1
   local segs={}
   for _,cu in ipairs(cuts) do if cu[1]>y then table.insert(segs,{y,cu[1]}) end y=math.max(y,cu[2]) end
   if y<y2 then table.insert(segs,{y,y2}) end
   for _,s in ipairs(segs) do
    if axis=="x" then table.insert(out,M.box(par,name or "Wall",u,s[1],c-t/2,v,s[2],c+t/2,k))
    else table.insert(out,M.box(par,name or "Wall",c-t/2,s[1],u,c+t/2,s[2],v,k)) end
   end
  end
 end
 return out
end
function M.wallX(par,x1,x2,z,t,y1,y2,holes,k,name) return wall(par,"x",math.min(x1,x2),math.max(x1,x2),z,t,y1,y2,holes,k,name) end
function M.wallZ(par,z1,z2,x,t,y1,y2,holes,k,name) return wall(par,"z",math.min(z1,z2),math.max(z1,z2),x,t,y1,y2,holes,k,name) end
-- face trim: band on outer face. axis x face at z, n outward sign
function M.band(par,axis,a1,a2,f,n,y1,y2,k,depth)
 depth=depth or 0.5
 if axis=="x" then return M.box(par,"Band",a1,y1,f,a2,y2,f+n*depth,k or "d") else return M.box(par,"Band",f,y1,a1,f+n*depth,y2,a2,k or "d") end
end
function M.baseStrip(par,axis,a1,a2,f,n,y)
 y=y or G
 M.band(par,axis,a1,a2,f,n,y,y+1.6,"m",0.35)
 M.band(par,axis,a1,a2,f,n,y+1.6,y+2.1,"y",0.4)
end
-- recessed-looking windows (dark inset panels) along a face
function M.windows(par,axis,a1,a2,f,n,y,step,w,h,k)
 for v=a1+step/2,a2-step/2+0.01,step do
  if axis=="x" then M.box(par,"Win",v-w/2,y,f,v+w/2,y+h,f+n*0.15,k or "void") else M.box(par,"Win",f,y,v-w/2,f+n*0.15,y+h,v+w/2,k or "void") end
 end
end
-- vertical panel joints
function M.joints(par,axis,a1,a2,f,n,y1,y2,step)
 for v=a1+step,a2-step*0.5,step do
  if axis=="x" then M.box(par,"Joint",v-0.15,y1,f,v+0.15,y2,f+n*0.1,"d") else M.box(par,"Joint",f,y1,v-0.15,f+n*0.1,y2,v+0.15,"d") end
 end
end
-- railing on straight axis-aligned line
function M.rail(par,x1,z1,x2,z2,y)
 local L=math.max(math.abs(x2-x1),math.abs(z2-z1)) if L<1 then return end
 local alongX=math.abs(x2-x1)>=math.abs(z2-z1)
 local function bar(name,y1,y2,th,k)
  if alongX then local p=M.box(par,name,math.min(x1,x2),y1,z1-th/2,math.max(x1,x2),y2,z1+th/2,k) return p
  else local p=M.box(par,name,x1-th/2,y1,math.min(z1,z2),x1+th/2,y2,math.max(z1,z2),k) return p end
 end
 local top=bar("RailTop",y+3.1,y+3.45,0.35,"y")
 local mid=bar("RailMid",y+1.6,y+1.85,0.2,"m") if mid then mid.CastShadow=false end
 local n=math.max(1,math.floor(L/6))
 for i=0,n do local t=i/n local x=x1+(x2-x1)*t local z=z1+(z2-z1)*t
  local p=M.box(par,"RailPost",x-0.14,y,z-0.14,x+0.14,y+3.1,z+0.14,"m") p.CastShadow=false end
end
-- rails round rect with gaps {{x,z},...}
function M.rectRails(par,x1,z1,x2,z2,y,gaps,gw)
 gw=gw or 8 gaps=gaps or {}
 local sides={{"x",z1,x1,x2},{"x",z2,x1,x2},{"z",x1,z1,z2},{"z",x2,z1,z2}}
 for _,s in ipairs(sides) do
  local cuts={}
  for _,g in ipairs(gaps) do local perp=(s[1]=="x") and g[2] or g[1] local al=(s[1]=="x") and g[1] or g[2]
   if math.abs(perp-s[2])<2.5 and al>s[3]-3 and al<s[4]+3 then table.insert(cuts,{al-gw/2,al+gw/2}) end end
  table.sort(cuts,function(p,q) return p[1]<q[1] end)
  local pos=s[3] local segs={}
  for _,c in ipairs(cuts) do if c[1]>pos then table.insert(segs,{pos,c[1]}) end pos=math.max(pos,c[2]) end
  if pos<s[4] then table.insert(segs,{pos,s[4]}) end
  for _,sg in ipairs(segs) do if sg[2]-sg[1]>1.5 then
   if s[1]=="x" then M.rail(par,sg[1],s[2],sg[2],s[2],y) else M.rail(par,s[2],sg[1],s[2],sg[2],y) end end end
 end
end
-- straight stair. (x,z)=bottom start centre line; dir "+x","-x","+z","-z"; returns end pos along axis
function M.stair(par,x,z,dir,w,y0,y1,rails)
 local m=M.model(par,"Stair")
 local rise=y1-y0 local n=math.max(1,math.ceil(rise/1.0)) local run=1.5
 local sgn=(dir:sub(1,1)=="+") and 1 or -1 local ax=dir:sub(2,2)
 for i=1,n do
  local top=y0+rise*i/n
  local a=(i-1)*run local b=i*run
  if ax=="x" then M.box(m,"Step",x+sgn*a,y0,z-w/2,x+sgn*b,top,z+w/2,"t")
  else M.box(m,"Step",x-w/2,y0,z+sgn*a,x+w/2,top,z+sgn*b,"t") end
 end
 local L=n*run
 if rails~=false then
  for _,s in ipairs({-1,1}) do
   local A,B
   if ax=="x" then A=Vector3.new(x,y0+3.4,z+s*(w/2-0.2)) B=Vector3.new(x+sgn*L,y1+3.4,z+s*(w/2-0.2))
   else A=Vector3.new(x+s*(w/2-0.2),y0+3.4,z) B=Vector3.new(x+s*(w/2-0.2),y1+3.4,z+sgn*L) end
   local len=(B-A).Magnitude
   M.part(m,"StairRail",Vector3.new(0.3,0.3,len),CFrame.lookAt((A+B)/2,B),"y")
   local sk
   if ax=="x" then sk=M.box(m,"Stringer",math.min(x,x+sgn*L),y0,z+s*(w/2)-0.3+ (s>0 and 0.3 or 0),math.max(x,x+sgn*L),y0+0.01,z+s*(w/2)+(s>0 and 0.3 or 0)) end
  end
 end
 return (ax=="x") and (x+sgn*L) or (z+sgn*L)
end
function M.slab(par,x1,z1,x2,z2,y,th,k,name) return M.box(par,name or "Slab",x1,y-(th or 1),z1,x2,y,z2,k or "s") end
function M.pillar(par,x,z,y0,y1,s,k) s=s or 2.4 return M.box(par,"Pillar",x-s/2,y0,z-s/2,x+s/2,y1,z+s/2,k or "w") end
function M.sandbags(par,x1,z1,x2,z2,y)
 local alongX=math.abs(x2-x1)>=math.abs(z2-z1) local L=alongX and math.abs(x2-x1) or math.abs(z2-z1)
 local n=math.max(1,math.floor(L/2.4))
 for layer=0,1 do for i=0,n-1-layer do
  local t0=(i+layer*0.5)/n local t1=(i+1+layer*0.5)/n
  local ax1=x1+(x2-x1)*t0 local az1=z1+(z2-z1)*t0 local ax2=x1+(x2-x1)*t1 local az2=z1+(z2-z1)*t1
  local yb=y+layer*1.1
  local p
  if alongX then p=M.box(par,"Sandbag",ax1+0.05,yb,az1-0.8,ax2-0.05,yb+1.15,az1+0.8,"b") else p=M.box(par,"Sandbag",ax1-0.8,yb,az1+0.05,ax1+0.8,yb+1.15,az2-0.05,"b") end
 end end
end
function M.container(par,x,z,y,alongX,col)
 local m=M.model(par,"Container")
 local L,W,H=20,8,8.6
 local hx,hz=(alongX and L or W)/2,(alongX and W or L)/2
 local b=M.box(m,"Body",x-hx,y,z-hz,x+hx,y+H,z+hz,"c") if col then b.Color=col end
 -- end frames
 if alongX then M.box(m,"EndFrame",x-hx-0.2,y,z-hz-0.2,x-hx+0.6,y+H+0.2,z+hz+0.2,"d") M.box(m,"EndFrame",x+hx-0.6,y,z-hz-0.2,x+hx+0.2,y+H+0.2,z+hz+0.2,"d")
 else M.box(m,"EndFrame",x-hx-0.2,y,z-hz-0.2,x+hx+0.2,y+H+0.2,z-hz+0.6,"d") M.box(m,"EndFrame",x-hx-0.2,y,z+hz-0.6,x+hx+0.2,y+H+0.2,z+hz+0.2,"d") end
 return m,y+H+0.2
end
function M.dome(par,x,y,z,r)
 local m=M.model(par,"Radome")
 M.box(m,"DomeBase",x-r*0.75,y,z-r*0.75,x+r*0.75,y+2,z+r*0.75,"d")
 local s=M.part(m,"Dome",Vector3.new(r*2,r*2,r*2),CFrame.new(x,y+1+r*0.85,z),"w",Enum.PartType.Ball) s.MaterialVariant="VS_WhitePrecast" s.Material=MAT.Concrete s.Color=Color3.fromRGB(240,240,238)
 return m
end
function M.mast(par,x,z,y0,h,s)
 s=s or 2
 local m=M.model(par,"Mast")
 for _,o in ipairs({{-1,-1},{1,-1},{-1,1},{1,1}}) do M.box(m,"MastLeg",x+o[1]*s-0.15,y0,z+o[2]*s-0.15,x+o[1]*s+0.15,y0+h,z+o[2]*s+0.15,"m") end
 for yy=y0+4,y0+h-1,5 do M.box(m,"MastRing",x-s,yy,z-s,x+s,yy+0.25,z+s,"m").Transparency=0 end
 M.box(m,"Antenna",x-0.12,y0+h,z-0.12,x+0.12,y0+h+14,z+0.12,"m")
 M.box(m,"Beacon",x-0.5,y0+h+14,z-0.5,x+0.5,y0+h+15,z+0.5,"red")
 M.box(m,"Beacon",x-s-0.4,y0+h-1,z-s-0.4,x-s+0.4,y0+h,z-s+0.4,"red")
 return m
end
function M.camo(par,x1,z1,x2,z2,y,h)
 h=h or 5
 for _,c in ipairs({{x1,z1},{x2,z1},{x1,z2},{x2,z2}}) do M.box(par,"NetPole",c[1]-0.15,y,c[2]-0.15,c[1]+0.15,y+h,c[2]+0.15,"m") end
 local n=M.box(par,"CamoNet",x1,y+h,z1,x2,y+h+0.3,z2,"camo") n.CanCollide=false
 n.CFrame=n.CFrame*CFrame.Angles(0,0,math.rad(4)) n.Transparency=0.08
end
function M.hvac(par,x,z,y)
 M.box(par,"HVAC",x-3,y,z-2.2,x+3,y+3,z+2.2,"m")
 M.box(par,"HVACFan",x-2.4,y+3,z-1.6,x-0.2,y+3.3,z+1.6,"d") M.box(par,"HVACFan",x+0.2,y+3,z-1.6,x+2.4,y+3.3,z+1.6,"d")
end
-- BARRIER_OVERRIDE: rails are solid barrier panels with orange cap
function M.rail(par,x1,z1,x2,z2,y)
 local alongX=math.abs(x2-x1)>=math.abs(z2-z1)
 local L=alongX and math.abs(x2-x1) or math.abs(z2-z1) if L<0.8 then return end
 local a1=alongX and math.min(x1,x2) or math.min(z1,z2) local a2=a1+L local c=alongX and z1 or x1
 local function bx(name,lo,hi,th,k) if alongX then return M.box(par,name,a1,lo,c-th/2,a2,hi,c+th/2,k) else return M.box(par,name,c-th/2,lo,a1,c+th/2,hi,a2,k) end end
 bx("Barrier",y,y+3.0,0.25,"d")
 local cap=bx("BarrierCap",y+3.0,y+3.5,0.45,"y") cap.Color=Color3.fromRGB(232,164,40)
 local n=math.max(1,math.floor(L/8))
 for i=0,n do local v=a1+L*i/n
  if alongX then M.box(par,"BarrierPost",v-0.25,y,c-0.3,v+0.25,y+3.5,c+0.3,"d") else M.box(par,"BarrierPost",c-0.3,y,v-0.25,c+0.3,y+3.5,v+0.25,"d") end end
end
return M

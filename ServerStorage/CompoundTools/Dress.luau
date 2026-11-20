local P=require(script.Parent.Plot)
local D={}
local MAT=Enum.Material
D.ORANGE=Color3.fromRGB(232,164,40)
D.GREEN=Color3.fromRGB(78,102,58)
D.GRIME=Color3.fromRGB(70,64,54)
local function flat(p) if not p then return nil end p.CanCollide=false p.CanQuery=false p.CanTouch=false p.CastShadow=false return p end
D.flat=flat
-- solid barrier panel along axis-aligned run at base y
function D.barrier(par,x1,z1,x2,z2,y)
 local alongX=math.abs(x2-x1)>=math.abs(z2-z1)
 local L=alongX and math.abs(x2-x1) or math.abs(z2-z1) if L<0.8 then return end
 local a1=alongX and math.min(x1,x2) or math.min(z1,z2) local a2=a1+L
 local c=alongX and z1 or x1
 local function bx(name,lo,hi,th,k) if alongX then return P.box(par,name,a1,lo,c-th/2,a2,hi,c+th/2,k) else return P.box(par,name,c-th/2,lo,a1,c+th/2,hi,a2,k) end end
 bx("Barrier",y,y+3.0,0.25,"d")
 local cap=bx("BarrierCap",y+3.0,y+3.5,0.45,"y") cap.Color=D.ORANGE
 local n=math.max(1,math.floor(L/8))
 for i=0,n do local v=a1+L*i/n
  if alongX then P.box(par,"BarrierPost",v-0.25,y,c-0.3,v+0.25,y+3.5,c+0.3,"d") else P.box(par,"BarrierPost",c-0.3,y,v-0.25,c+0.3,y+3.5,v+0.25,"d") end end
end
-- dark steel truss column on a face (axis "x" face at z=f, n outward), centre a, from y1..y2, width w
function D.truss(par,axis,a,f,n,y1,y2,w)
 w=w or 3.2
 local m=P.model(par,"TrussColumn")
 local function v(name,u1,u2,lo,hi,d1,d2,k) if axis=="x" then return P.box(m,name,u1,lo,f+n*d1,u2,hi,f+n*d2,k) else return P.box(m,name,f+n*d1,lo,u1,f+n*d2,hi,u2,k) end end
 v("TrussBack",a-w/2-0.6,a+w/2+0.6,y1,y2,0,0.3,"d")
 v("TrussChord",a-w/2-0.4,a-w/2+0.3,y1,y2,0.3,1.3,"d") v("TrussChord",a+w/2-0.3,a+w/2+0.4,y1,y2,0.3,1.3,"d")
 local step=w*1.4
 for y=y1+0.5,y2-step,step do
  local A,B
  if axis=="x" then
   for s=-1,1,2 do
    A=Vector3.new(a-s*w/2,y,f+n*0.9) B=Vector3.new(a+s*w/2,y+step,f+n*0.9)
    local L=(B-A).Magnitude P.part(m,"TrussBrace",Vector3.new(0.3,0.3,L),CFrame.lookAt((A+B)/2,B),"d")
   end
  else
   for s=-1,1,2 do
    A=Vector3.new(f+n*0.9,y,a-s*w/2) B=Vector3.new(f+n*0.9,y+step,a+s*w/2)
    local L=(B-A).Magnitude P.part(m,"TrussBrace",Vector3.new(0.3,0.3,L),CFrame.lookAt((A+B)/2,B),"d")
   end
  end
 end
 return m
end
-- cantilever dark box at top of face: spans a1..a2, from y1..y2, projecting out d
function D.cantilever(par,axis,a1,a2,f,n,y1,y2,d)
 local m=P.model(par,"Cantilever")
 if axis=="x" then
  P.box(m,"CantBox",a1,y1,f,a2,y2,f+n*d,"c")
  P.box(m,"CantTrim",a1-0.3,y2,f-n*0.3,a2+0.3,y2+0.6,f+n*(d+0.3),"d")
  -- sloped underside brace
  local L=math.sqrt(d*d+(d*0.9)^2)
  local cf=CFrame.lookAt(Vector3.new((a1+a2)/2,y1-d*0.45,f+n*d/2),Vector3.new((a1+a2)/2,y1,f+n*d))
  P.part(m,"CantSlope",Vector3.new(a2-a1,0.8,L),cf,"d")
  P.box(m,"CantFill",a1,y1-d*0.9,f,a2,y1,f+n*0.4,"d")
 else
  P.box(m,"CantBox",f,y1,a1,f+n*d,y2,a2,"c")
  P.box(m,"CantTrim",f-n*0.3,y2,a1-0.3,f+n*(d+0.3),y2+0.6,a2+0.3,"d")
  local L=math.sqrt(d*d+(d*0.9)^2)
  local cf=CFrame.lookAt(Vector3.new(f+n*d/2,y1-d*0.45,(a1+a2)/2),Vector3.new(f+n*d,y1,(a1+a2)/2))
  P.part(m,"CantSlope",Vector3.new(L,0.8,a2-a1),cf*CFrame.Angles(0,math.rad(90),0),"d")
  P.box(m,"CantFill",f,y1-d*0.9,a1,f+n*0.4,y1,a2,"d")
 end
 return m
end
-- grime: streaks down from y2, base staining, chip spots, on a face
function D.grime(par,axis,a1,a2,f,n,y1,y2,rng,density)
 density=density or 0.35
 local function strip(name,u1,u2,lo,hi,tr,col)
  local p if axis=="x" then p=P.box(par,name,u1,lo,f+n*0.02,u2,hi,f+n*0.08,"m") else p=P.box(par,name,f+n*0.02,lo,u1,f+n*0.08,hi,u2,"m") end
  if p then flat(p) p.Material=MAT.SmoothPlastic p.MaterialVariant="" p.Color=col or D.GRIME p.Transparency=tr end return p
 end
 strip("BaseStain",a1,a2,y1,y1+1.6,0.55) strip("BaseStain",a1,a2,y1+1.6,y1+3.2,0.78)
 local u=a1+rng:NextNumber(1,5)
 while u<a2-1 do
  if rng:NextNumber()<density then local w=rng:NextNumber(0.5,2.2) local len=rng:NextNumber(3,math.max(3.5,(y2-y1)*0.6))
   strip("Streak",u,math.min(u+w,a2),y2-len,y2,rng:NextNumber(0.72,0.86)) end
  if rng:NextNumber()<0.25 then local s=rng:NextNumber(0.4,1.1) local yy=rng:NextNumber(y1+2,y2-1)
   strip("Chip",u,u+s,yy,yy+s*0.8,0.45,Color3.fromRGB(150,146,138)) end
  u+=rng:NextNumber(3,7)
 end
end
-- irregular vents / small windows
function D.vents(par,axis,a1,a2,f,n,y1,y2,rng,count)
 for i=1,count do local s=rng:NextNumber()<0.7 and 1.2 or 0.9 local h=rng:NextNumber()<0.3 and 2.6 or s
  local u=rng:NextNumber(a1+1,a2-1-s) local y=rng:NextNumber(y1,y2-h)
  if axis=="x" then P.box(par,"Vent",u,y,f,u+s,y+h,f+n*0.18,"void") else P.box(par,"Vent",f,y,u,f+n*0.18,y+h,u+s,"void") end end
end
-- wall lamp with conduit running down
function D.lamp(par,axis,a,f,n,y,ydown)
 if axis=="x" then P.box(par,"Lamp",a-0.8,y,f,a+0.8,y+0.5,f+n*1.1,"d") local l=P.box(par,"LampLens",a-0.6,y-0.05,f+n*0.2,a+0.6,y,f+n*0.9,"m") l.Material=MAT.Neon l.Color=Color3.fromRGB(240,236,220) flat(l)
  P.box(par,"Conduit",a+1.2,ydown,f,a+1.45,y+0.4,f+n*0.25,"d") P.box(par,"Conduit",a+0.6,y+0.15,f,a+1.45,y+0.4,f+n*0.25,"d")
 else P.box(par,"Lamp",f,y,a-0.8,f+n*1.1,y+0.5,a+0.8,"d") local l=P.box(par,"LampLens",f+n*0.2,y-0.05,a-0.6,f+n*0.9,y,a+0.6,"m") l.Material=MAT.Neon l.Color=Color3.fromRGB(240,236,220) flat(l)
  P.box(par,"Conduit",f,ydown,a+1.2,f+n*0.25,y+0.4,a+1.45,"d") P.box(par,"Conduit",f,y+0.15,a+0.6,f+n*0.25,y+0.4,a+1.45,"d") end
end
-- chipped jersey barrier (axis-aligned)
function D.jersey(par,x,z,alongX,y)
 y=y or P.G local m=P.model(par,"Jersey")
 local hx,hz=alongX and 3 or 0.9,alongX and 0.9 or 3
 P.box(m,"JerseyBase",x-hx,y,z-hz,x+hx,y+1.2,z+hz,"p")
 local hx2,hz2=alongX and 3 or 0.45,alongX and 0.45 or 3
 P.box(m,"JerseyTop",x-hx2,y+1.2,z-hz2,x+hx2,y+3.6,z+hz2,"p")
 return m
end
-- military green ammo crate stack
function D.ammo(par,x,z,y,rng)
 y=y or P.G local m=P.model(par,"AmmoStack")
 local col=Color3.fromRGB(70,80,58)
 local layers=rng:NextInteger(1,3)
 for l=0,layers-1 do for i=0,1 do
  local b=P.box(m,"AmmoBox",x-2.2+i*2.2+0.05,y+l*1.5,z-1.4,x+i*2.2-0.05,y+l*1.5+1.45,z+1.4,"m") b.Color=col b.Material=MAT.Metal b.MaterialVariant=""
  P.box(m,"AmmoLatch",x-1.4+i*2.2,y+l*1.5+0.5,z+1.4,x-0.8+i*2.2,y+l*1.5+0.9,z+1.5,"d")
 end end
 return m
end
-- utility cabinet
function D.cabinet(par,x,z,y,face)
 y=y or P.G local m=P.model(par,"Cabinet")
 P.box(m,"CabinetBody",x-2,y,z-1.2,x+2,y+6,z+1.2,"m")
 P.box(m,"CabinetTop",x-2.2,y+6,z-1.4,x+2.2,y+6.4,z+1.4,"d")
 P.box(m,"CabinetPanel",x-1.6,y+1,z+1.2,x+1.6,y+5,z+1.3,"d")
 local led=P.box(m,"CabinetLED",x+1,y+4.4,z+1.3,x+1.3,y+4.7,z+1.35,"red") 
 if face then m:PivotTo(CFrame.new(x,y,z)*CFrame.Angles(0,math.rad(face),0)*CFrame.new(-x,-y,-z)*m:GetPivot()) end
 return m
end
-- floodlight pole
function D.floodlight(par,x,z,y,h,yaw)
 y=y or P.G local m=P.model(par,"Floodlight")
 P.box(m,"PoleBase",x-0.8,y,z-0.8,x+0.8,y+1,z+0.8,"p")
 P.box(m,"Pole",x-0.3,y+1,z-0.3,x+0.3,y+h,z+0.3,"d")
 local head=CFrame.new(x,y+h+0.6,z)*CFrame.Angles(0,math.rad(yaw or 0),0)
 P.part(m,"LightBar",Vector3.new(5,0.4,0.4),head,"d")
 for i=-1,1,2 do local f=P.part(m,"Lamp",Vector3.new(1.6,1.2,0.8),head*CFrame.new(i*1.6,0.6,-0.3)*CFrame.Angles(math.rad(-25),0,0),"d")
  local l=P.part(m,"Lens",Vector3.new(1.3,0.9,0.1),head*CFrame.new(i*1.6,0.6,-0.75)*CFrame.Angles(math.rad(-25),0,0),"m") l.Material=MAT.Neon l.Color=Color3.fromRGB(245,240,225) flat(l) end
 return m
end
-- rocket pod
function D.pods(par,x,z,y,yaw)
 local m=P.model(par,"RocketPods")
 local base=CFrame.new(x,y,z)*CFrame.Angles(0,math.rad(yaw or 0),0)
 P.part(m,"PodMount",Vector3.new(3,2,3),base*CFrame.new(0,1,0),"d")
 for i=-1,1,2 do local pod=base*CFrame.new(i*2.4,3.4,0)*CFrame.Angles(math.rad(12),0,0)
  P.part(m,"Pod",Vector3.new(3.6,3.2,5),pod,"m")
  for r=-1,1,2 do for c=-1,1,2 do local t=P.part(m,"Tube",Vector3.new(1,1,0.12),pod*CFrame.new(c*0.85,r*0.8,-2.52),"y") t.Color=D.ORANGE end end end
 return m
end
-- slatted fence run (dark vertical slats look via corrugated panel + posts)
function D.fence(par,x1,z1,x2,z2,y,h)
 local alongX=math.abs(x2-x1)>=math.abs(z2-z1)
 local L=alongX and math.abs(x2-x1) or math.abs(z2-z1)
 local a1=alongX and math.min(x1,x2) or math.min(z1,z2) local c=alongX and z1 or x1
 local n=math.ceil(L/10)
 for i=0,n-1 do local u1=a1+L*i/n local u2=a1+L*(i+1)/n
  if alongX then P.box(par,"FencePanel",u1,y+1.5,c-0.2,u2,y+h,c+0.2,"c") P.box(par,"FencePost",u1-0.4,y,c-0.6,u1+0.4,y+h+0.6,c+0.6,"d")
   for s=u1+1,u2-0.5,1.25 do P.box(par,"FenceSlat",s-0.25,y+1.5,c-0.45,s+0.25,y+h,c+0.45,"d") end
  else P.box(par,"FencePanel",c-0.2,y+1.5,u1,c+0.2,y+h,u2,"c") P.box(par,"FencePost",c-0.6,y,u1-0.4,c+0.6,y+h+0.6,u1+0.4,"d")
   for s=u1+1,u2-0.5,1.25 do P.box(par,"FenceSlat",c-0.45,y+1.5,s-0.25,c+0.45,y+h,s+0.25,"d") end end
 end
 if alongX then P.box(par,"FenceBase",a1,y,c-0.5,a1+L,y+1.5,c+0.5,"p") P.box(par,"FenceCap",a1,y+h,c-0.5,a1+L,y+h+0.4,c+0.5,"d")
 else P.box(par,"FenceBase",c-0.5,y,a1,c+0.5,y+1.5,a1+L,"p") P.box(par,"FenceCap",c-0.5,y+h,a1,c+0.5,y+h+0.4,a1+L,"d") end
end
-- floor paint (flat decal-like parts)
function D.paint(par,x1,z1,x2,z2,y,col,name)
 local p=P.box(par,name or "Paint",math.min(x1,x2),y,math.min(z1,z2),math.max(x1,x2),y+0.06,math.max(z1,z2),"y")
 if p then flat(p) p.Material=MAT.SmoothPlastic p.Color=col or Color3.fromRGB(220,176,48) end return p
end
function D.paintRot(par,cx,cz,len,w,yaw,y,col)
 local p=P.part(par,"Paint",Vector3.new(w,0.06,len),CFrame.new(cx,y+0.03,cz)*CFrame.Angles(0,math.rad(yaw),0),"y")
 flat(p) p.Material=MAT.SmoothPlastic p.Color=col or Color3.fromRGB(220,176,48) return p
end
-- hatch zone (white diagonal stripes inside rectangle, with yellow border)
function D.hatch(par,x1,z1,x2,z2,y,col)
 col=col or Color3.fromRGB(226,226,220)
 local Y=Color3.fromRGB(220,176,48)
 D.paint(par,x1,z1,x2,z1+0.35,y,Y) D.paint(par,x1,z2-0.35,x2,z2,y,Y) D.paint(par,x1,z1,x1+0.35,z2,y,Y) D.paint(par,x2-0.35,z1,x2,z2,y,Y)
 local w,d=x2-x1,z2-z1
 local L=math.min(w,d)*1.35
 for s=-d,w,2.4 do local cx=x1+s+d/2 local cz=(z1+z2)/2
  -- clip roughly: only stripes whose centre is inside
  if cx>x1+1 and cx<x2-1 then D.paintRot(par,cx,cz,math.min(L,d*1.38),0.45,45,y,col) end end
end
-- fluorescent strip light (ceiling), optional real light
function D.strip(par,x1,z1,x2,z2,y,light)
 local p=P.box(par,"StripLight",x1,y-0.3,z1,x2,y,z2,"m") p.Material=MAT.Neon p.Color=Color3.fromRGB(235,242,250) flat(p)
 P.box(par,"StripHousing",x1-0.2,y,z1-0.2,x2+0.2,y+0.25,z2+0.2,"d")
 if light then local l=Instance.new("SurfaceLight") l.Face=Enum.NormalId.Bottom l.Range=18 l.Brightness=1.6 l.Angle=110 l.Color=Color3.fromRGB(230,238,250) l.Shadows=false l.Parent=p end
 return p
end
return D

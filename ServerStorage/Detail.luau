local D={}
local Y=Vector3.yAxis
D.C={back=Color3.fromRGB(46,48,52),panel=Color3.fromRGB(64,66,70),rib=Color3.fromRGB(34,35,39),skirt=Color3.fromRGB(30,31,34),
 trim=Color3.fromRGB(84,86,90),hazard=Color3.fromRGB(226,168,38),black=Color3.fromRGB(22,22,24),blue=Color3.fromRGB(70,160,255),
 pipe=Color3.fromRGB(92,94,98),floor=Color3.fromRGB(44,46,50),beam=Color3.fromRGB(38,40,44),light=Color3.fromRGB(235,242,255)}
local MET=Enum.Material.Metal local COR=Enum.Material.CorrodedMetal local DIA=Enum.Material.DiamondPlate local NEON=Enum.Material.Neon
local function mk(cls,par,name,cf,size,color,mat)
 local p=Instance.new(cls) p.Name=name p.Anchored=true p.TopSurface=0 p.BottomSurface=0 p.Size=size p.CFrame=cf p.Color=color p.Material=mat or MET p.Parent=par return p end
D.mk=mk
-- frame: local X along wall, Y up, Z into the room
local function frame(c,d,n) if d:Cross(Y):Dot(n)<0 then d=-d end return CFrame.fromMatrix(c,d,Y,d:Cross(Y)) end
D.frame=frame
-- one wall bay: base centre c on the wall face line, width w, height h, n = into room
function D.bay(par,F,w,h,variant,opts)
 opts=opts or {}
 local function P(name,x,y,z,sx,sy,sz,col,mat) return mk("Part",par,name,F*CFrame.new(x,y,z),Vector3.new(sx,sy,sz),col,mat) end
 local function W(name,x,y,z,sx,sy,sz,col,mat,flip) local cf=F*CFrame.new(x,y,z) if flip then cf=cf*CFrame.Angles(0,math.pi,0) end return mk("WedgePart",par,name,cf,Vector3.new(sx,sy,sz),col,mat) end
 P("Back",0,h/2,0.3,w,h,0.6,D.C.back,MET)
 -- skirt: kick plate + angled chamfer rising back to the wall
 P("Kick",0,0.6,0.85,w,1.2,1.1,D.C.skirt,DIA)
 W("SkirtSlope",0,1.9,0.85,w,1.4,1.1,D.C.skirt,MET,true)
 if variant%4==0 then P("Hazard",0,0.95,1.42,w-0.4,0.35,0.05,D.C.hazard,Enum.Material.SmoothPlastic) end
 -- ribs (chamfered tops)
 local top=h-2.6
 for _,s in ipairs({-1,1}) do local x=s*(w/2-0.45)
  P("Rib",x,(2.6+top)/2,0.95,0.9,top-2.6,1.3,D.C.rib,MET)
  W("RibCap",x,top+0.6,0.95,0.9,1.2,1.3,D.C.rib,MET,true)
  W("RibFoot",x,2.0,1.75,0.9,0.8,0.3,D.C.rib,MET) end
 local iw=w-1.8 local ih=top-2.9 local iy=2.75+ih/2
 if variant%3==1 then
  -- vent grille: frame + slanted slats
  P("VentFrame",0,iy,0.7,iw,ih,0.2,D.C.rib,MET)
  local n=math.max(4,math.floor(ih/1.1))
  for i=1,n do local y=2.9+ih*(i-0.5)/n mk("Part",par,"Slat",F*CFrame.new(0,y,0.95)*CFrame.Angles(math.rad(-35),0,0),Vector3.new(iw-0.4,0.12,0.9),D.C.trim,MET) end
 else
  -- recessed corroded panel with raised centre plate and seams
  P("Inset",0,iy,0.7,iw,ih,0.2,D.C.panel,MET)
  P("Plate",0,iy+ih*0.12,0.85,iw*0.7,ih*0.45,0.15,D.C.back,MET)
  W("PlateBevelT",0,iy+ih*0.12+ih*0.225+0.25,0.85,iw*0.7,0.5,0.15,D.C.back,MET,true)
  P("Seam",0,2.9+ih*0.33,0.82,iw,0.18,0.06,D.C.black,Enum.Material.SmoothPlastic)
  P("Seam",0,2.9+ih*0.8,0.82,iw,0.18,0.06,D.C.black,Enum.Material.SmoothPlastic)
 end
 -- cornice: angled overhang + cap
 W("CorniceSlope",0,h-2.0,0.95,w,1.2,1.3,D.C.trim,MET)
 P("Cornice",0,h-0.7,1.05,w,1.4,1.5,D.C.rib,MET)
 -- pipes with clamps
 if opts.pipe then
  for _,py in ipairs({h-3.6}) do
   local pc=mk("Part",par,"Pipe",F*CFrame.new(0,py,2.05)*CFrame.Angles(0,0,math.rad(90))*CFrame.Angles(0,0,0),Vector3.new(0.9,0.9,w),D.C.pipe,MET) pc.Shape=Enum.PartType.Cylinder pc.CFrame=F*CFrame.new(0,py,2.05)*CFrame.Angles(0,math.rad(90),0)*CFrame.Angles(0,0,0)
   pc.Size=Vector3.new(w,0.9,0.9) pc.CFrame=F*CFrame.new(0,py,2.05)
   P("Clamp",0,py,1.75,0.5,1.4,0.9,D.C.rib,MET)
  end
 end
 if variant%5==2 and opts.blue~=false then local s=P("BlueStrip",-(w/2-0.45),(2.6+top)/2,1.65,0.25,top-4,0.1,D.C.blue,NEON) s.CanCollide=false
  if variant%10==2 then local l=Instance.new("PointLight") l.Color=D.C.blue l.Range=16 l.Brightness=1.1 l.Parent=s end end
end
-- run of bays along a line a->b (ground points), n into room
function D.wall(par,a,b,y0,h,n,opts)
 local d=Vector3.new(b.X-a.X,0,b.Z-a.Z) local L=d.Magnitude if L<1 then return end local dir=d.Unit
 local cnt=math.max(1,math.floor(L/8+0.5)) local w=L/cnt local k=(opts and opts.seed) or 0
 for i=0,cnt-1 do local c=a+dir*w*(i+0.5) D.bay(par,frame(Vector3.new(c.X,y0,c.Z),dir,n),w,h,i+k,opts) end
end
-- octagonal pillar with stepped base and capital
function D.pillar(par,x,z,y0,y1,w,col)
 col=col or Color3.fromRGB(226,227,222) local h=y1-y0
 local function oct(name,y,hh,ww,c,mat) local a=mk("Part",par,name,CFrame.new(x,y,z),Vector3.new(ww,hh,ww*0.58),c,mat) local b=mk("Part",par,name,CFrame.new(x,y,z),Vector3.new(ww*0.58,hh,ww),c,mat)
  mk("Part",par,name,CFrame.new(x,y,z)*CFrame.Angles(0,math.rad(45),0),Vector3.new(ww*0.58,hh,ww),c,mat) mk("Part",par,name,CFrame.new(x,y,z)*CFrame.Angles(0,math.rad(45),0),Vector3.new(ww,hh,ww*0.58),c,mat) end
 oct("PillarBase",y0+0.7,1.4,w+2.2,D.C.skirt,MET) oct("PillarBase2",y0+1.8,0.8,w+1.2,D.C.rib,MET)
 oct("PillarShaft",y0+2.2+(h-4.4)/2,h-4.4,w,col,Enum.Material.Concrete)
 oct("PillarCap",y1-1.6,0.8,w+1.2,D.C.rib,MET) oct("PillarCap2",y1-0.6,1.2,w+2.2,D.C.skirt,MET)
 local s=mk("Part",par,"PillarBand",CFrame.new(x,y0+4,z),Vector3.new(w+0.15,0.5,w+0.15),D.C.hazard,Enum.Material.SmoothPlastic)
end
-- ceiling: I-beam grid + recessed light housings with angled sides
function D.ceiling(par,x1,z1,x2,z2,y,step)
 step=step or 12 local k=0
 for x=x1+step/2,x2-step/2,step do
  mk("Part",par,"BeamWeb",CFrame.new(x,y-1.1,(z1+z2)/2),Vector3.new(0.35,2.2,z2-z1),D.C.beam,MET)
  mk("Part",par,"BeamFlange",CFrame.new(x,y-2.3,(z1+z2)/2),Vector3.new(1.4,0.3,z2-z1),D.C.beam,MET)
 end
 for z=z1+step,z2-step*0.5,step do mk("Part",par,"BeamCross",CFrame.new((x1+x2)/2,y-0.6,z),Vector3.new(x2-x1,1.2,0.35),D.C.beam,MET) end
 for x=x1+step,x2-step*0.5,step do for z=z1+step/2,z2-step/2,step do k+=1
  local cf=CFrame.new(x,y-0.35,z)
  mk("Part",par,"LightHousing",cf,Vector3.new(5,0.7,2.6),D.C.rib,MET)
  local f1=mk("WedgePart",par,"LightBevel",cf*CFrame.new(0,-0.45,1.55)*CFrame.Angles(0,0,math.rad(180)),Vector3.new(5,0.5,0.5),D.C.rib,MET)
  local f2=mk("WedgePart",par,"LightBevel",cf*CFrame.new(0,-0.45,-1.55)*CFrame.Angles(0,math.pi,math.rad(180)),Vector3.new(5,0.5,0.5),D.C.rib,MET)
  local l=mk("Part",par,"CeilLight",cf*CFrame.new(0,-0.38,0),Vector3.new(4.2,0.1,1.8),D.C.light,NEON) l.CanCollide=false
  if k%3==1 then local s=Instance.new("SurfaceLight") s.Face=Enum.NormalId.Bottom s.Range=24 s.Brightness=1.5 s.Angle=120 s.Color=Color3.fromRGB(230,238,255) s.Parent=l end
 end end
end
-- floor plates with seams and hazard border
function D.floor(par,x1,z1,x2,z2,y)
 local f=mk("Part",par,"Floor",CFrame.new((x1+x2)/2,y-0.3,(z1+z2)/2),Vector3.new(x2-x1,0.6,z2-z1),D.C.floor,MET) f.Reflectance=0.04
 for x=x1+8,x2-4,8 do mk("Part",par,"FloorSeam",CFrame.new(x,y+0.01,(z1+z2)/2),Vector3.new(0.18,0.04,z2-z1),D.C.black,Enum.Material.SmoothPlastic).CanCollide=false end
 for z=z1+8,z2-4,8 do mk("Part",par,"FloorSeam",CFrame.new((x1+x2)/2,y+0.01,z),Vector3.new(x2-x1,0.04,0.18),D.C.black,Enum.Material.SmoothPlastic).CanCollide=false end
end
-- chamfered door portal (angled top corners) on a wall opening
function D.portal(par,cx,cz,axis,w,h,y0,out)
 local dir=axis=="x" and Vector3.xAxis or Vector3.zAxis
 local F=frame(Vector3.new(cx,y0,cz),dir,out)
 local function P(name,x,y,z,sx,sy,sz,col,mat) return mk("Part",par,name,F*CFrame.new(x,y,z),Vector3.new(sx,sy,sz),col,mat) end
 for _,s in ipairs({-1,1}) do
  P("Jamb",s*(w/2+0.7),h/2,0.6,1.4,h,1.6,D.C.rib,MET)
  local cw=mk("WedgePart",par,"PortalCorner",F*CFrame.new(s*(w/2-0.9),h-0.9,0.6)*CFrame.Angles(0,s>0 and 0 or 0,0)*CFrame.Angles(0,math.rad(90)*s,math.rad(180)),Vector3.new(1.6,1.8,1.8),D.C.rib,MET)
  local b=P("PortalLight",s*(w/2-0.05),h*0.45,1.45,0.15,h*0.8,0.15,D.C.blue,NEON) b.CanCollide=false
 end
 P("Header",0,h+0.8,0.6,w+2.8,1.6,1.6,D.C.rib,MET)
 P("HeaderStripe",0,h+0.8,1.42,w,0.35,0.05,D.C.hazard,Enum.Material.SmoothPlastic)
end
return D

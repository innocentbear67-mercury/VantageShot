local K={}
local WHITE1,WHITE2=Color3.fromRGB(238,238,234),Color3.fromRGB(214,215,210)
local JOINT=Color3.fromRGB(62,64,68)
local DIRT=Color3.fromRGB(92,84,70) local CHIP=Color3.fromRGB(132,128,120)
K.JOINT=JOINT
local function part(par,name,size,cf,mat,col,tr,flat)
 local p=Instance.new("Part") p.Anchored=true p.Name=name p.Size=size p.CFrame=cf p.Material=mat p.Color=col p.Transparency=tr or 0
 p.TopSurface=Enum.SurfaceType.Smooth p.BottomSurface=Enum.SurfaceType.Smooth
 if flat then p.CanCollide=false p.CanQuery=false p.CanTouch=false p.CastShadow=false end
 p.Parent=par return p
end
K.part=part
-- panelise one face. axis "x": face plane z=f (normal n along z), span a1..a2 along x. axis "z": plane x=f, span along z.
function K.panels(par,axis,a1,a2,f,n,y1,y2,rng,pw,ph)
 pw=pw or 8 ph=ph or 12
 local L=a2-a1 local Hh=y2-y1 if L<1.2 or Hh<1.2 then return 0 end
 local nx=math.max(1,math.floor(L/pw+0.5)) local ny=math.max(1,math.floor(Hh/ph+0.5))
 local w=L/nx local h=Hh/ny local gap=0.35 local cnt=0
 local along=axis=="x" and Vector3.new(1,0,0) or Vector3.new(0,0,1)
 local nrm=axis=="x" and Vector3.new(0,0,n) or Vector3.new(n,0,0)
 for i=0,nx-1 do for j=0,ny-1 do
  local pw2,ph2=w-gap,h-gap
  if pw2>0.3 and ph2>0.3 then
   local out=0.45+0.04*rng:NextInteger(0,2)
   local cu=a1+(i+0.5)*w local cv=y1+(j+0.5)*h
   local base=(axis=="x" and Vector3.new(cu,cv,f) or Vector3.new(f,cv,cu))
   local c=base+nrm*(out/2)
   local size=axis=="x" and Vector3.new(pw2,ph2,out) or Vector3.new(out,ph2,pw2)
   part(par,"Panel",size,CFrame.new(c),Enum.Material.Plaster,WHITE1:Lerp(WHITE2,rng:NextNumber()^1.6)) cnt+=1
   local face=base+nrm*(out+0.03)
   local function g(u,v,ww,hh,col,tr) local cc=face+along*u+Vector3.new(0,v,0) part(par,"Grime",axis=="x" and Vector3.new(ww,hh,0.04) or Vector3.new(0.04,hh,ww),CFrame.new(cc),Enum.Material.SmoothPlastic,col,tr,true) cnt+=1 end
   -- soft base dirt only on lowest row
   if j==0 then g(0,-ph2/2+0.5,pw2,1.0,DIRT,0.78) g(0,-ph2/2+1.5,pw2,1.0,DIRT,0.9) end
   for k=1,rng:NextInteger(0,2) do local sw=rng:NextNumber(0.2,0.7) local len=rng:NextNumber(ph2*0.3,ph2*0.75) local u=rng:NextNumber(-pw2/2+0.5,pw2/2-0.5) local seg=len/3
    for q=0,2 do g(u,ph2/2-seg*(q+0.5),sw*(1-q*0.15),seg,DIRT,0.7+q*0.08) end end
   for k=1,rng:NextInteger(0,2) do local cu2=rng:NextNumber(-pw2/2+0.5,pw2/2-0.5) local cv2=rng:NextNumber(-ph2/2+0.5,ph2/2-0.5)
    for q=1,rng:NextInteger(1,3) do local sz=rng:NextNumber(0.1,0.3) g(cu2+rng:NextNumber(-0.5,0.5),cv2+rng:NextNumber(-0.4,0.4),sz,sz,CHIP,0.3) end end
   if rng:NextNumber()<0.3 then g(rng:NextNumber(-pw2/4,pw2/4),rng:NextNumber(-ph2/4,ph2/4),math.min(pw2*0.6,rng:NextNumber(2,4)),math.min(ph2*0.6,rng:NextNumber(1.5,3.5)),DIRT,0.93) end
  end
 end end
 return cnt
end
-- drip stain under an object on a face
function K.drip(par,pos,axis,w,n)
 for i=0,2 do local len=1.4 local c=pos-Vector3.new(0,len*(i+0.5),0)
  part(par,"Grime",axis=="x" and Vector3.new(w*(0.7-i*0.15),len,0.06) or Vector3.new(0.06,len,w*(0.7-i*0.15)),CFrame.new(c),Enum.Material.SmoothPlastic,DIRT,0.66+i*0.1,true) end
end
return K

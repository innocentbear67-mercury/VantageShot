-- Live Fire canyon terrain (heightmap decal: R,G = (h+40)*50 16-bit, B = mat*40). Grid 4 studs from X0=-720,Z0=-416. World Y = h + 4.
local M={}
local IS=game:GetService("InsertService") local AS=game:GetService("AssetService")
local MAT={[0]=Enum.Material.Grass,Enum.Material.Ground,Enum.Material.Rock,Enum.Material.Grass,Enum.Material.Ground}
M.X0,M.Z0,M.C,M.Yoff=-720,-416,4,4
function M.load(id)
 local m=IS:LoadAsset(id) local tex=m:FindFirstChildWhichIsA("Decal",true).Texture m:Destroy()
 local img for _=1,20 do local ok,r=pcall(function() return AS:CreateEditableImageAsync(Content.fromUri(tex)) end) if ok then img=r break end task.wait(3) end
 assert(img,"heightmap did not load")
 local W,Hh=img.Size.X,img.Size.Y local buf=img:ReadPixelsBuffer(Vector2.zero,img.Size) img:Destroy()
 local H,Mt={},{}
 for r=0,Hh-1 do for c=0,W-1 do local i=(r*W+c)*4 H[r*W+c]=(buffer.readu8(buf,i)*256+buffer.readu8(buf,i+1))/50-40+M.Yoff Mt[r*W+c]=math.floor(buffer.readu8(buf,i+2)/40+0.5) end end
 local hm={W=W,Hh=Hh,H=H,M=Mt}
 function hm.h(x,z) local fx,fz=(x-M.X0)/M.C,(z-M.Z0)/M.C local c0,r0=math.clamp(math.floor(fx),0,W-2),math.clamp(math.floor(fz),0,Hh-2) local tx,tz=math.clamp(fx-c0,0,1),math.clamp(fz-r0,0,1)
  local a,b,c,d=H[r0*W+c0],H[r0*W+c0+1],H[(r0+1)*W+c0],H[(r0+1)*W+c0+1] return (a*(1-tx)+b*tx)*(1-tz)+(c*(1-tx)+d*tx)*tz end
 function hm.slope(x,z,e) e=e or 5 local gx=(hm.h(x+e,z)-hm.h(x-e,z))/(2*e) local gz=(hm.h(x,z+e)-hm.h(x,z-e))/(2*e) return math.sqrt(gx*gx+gz*gz),gx,gz end
 return hm
end
function M.write(hm,cxFrom,cxTo)
 local T=workspace.Terrain local W,Hh,H,Mt=hm.W,hm.Hh,hm.H,hm.M
 local Y0,ny,C=-16,38,M.C
 cxFrom=cxFrom or 0 cxTo=cxTo or W-2
 for cx=cxFrom,cxTo,25 do local nxc=math.min(25,cxTo+1-cx)
  local mats,occ={},{}
  for i=1,nxc do mats[i]={} occ[i]={} local col=cx+i-1 for j=1,ny do mats[i][j]={} occ[i][j]={} end
   for k=1,Hh-1 do local row=k-1
    local h=(H[row*W+col]+H[row*W+col+1]+H[(row+1)*W+col]+H[(row+1)*W+col+1])/4
    local mi=Mt[row*W+col] local mt=MAT[mi] local deep=(mi==2) and Enum.Material.Rock or Enum.Material.Ground
    for j=1,ny do local y0=Y0+(j-1)*C local o=math.clamp((h-y0)/C,0,1) occ[i][j][k]=o mats[i][j][k]= o<=0 and Enum.Material.Air or ((h-y0>C*1.5) and deep or mt) end end end
  local x0=M.X0+cx*C
  T:WriteVoxels(Region3.new(Vector3.new(x0,Y0,M.Z0),Vector3.new(x0+nxc*C,Y0+ny*C,M.Z0+(Hh-1)*C)),C,mats,occ)
  task.wait()
 end
end
return M
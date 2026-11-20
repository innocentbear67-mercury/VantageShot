local K={}
local lib=game.ServerStorage.LF_MeshBoard
local build=workspace.Map_LiveFire.FR_Build
K.MAT={
 alloy={Enum.Material.Metal,Color3.fromRGB(168,172,178)},
 dark={Enum.Material.Metal,Color3.fromRGB(62,66,74)},
 light={Enum.Material.Neon,Color3.fromRGB(110,200,255)},
 concrete={Enum.Material.Concrete,Color3.fromRGB(150,146,138)},
 paint={Enum.Material.Metal,Color3.fromRGB(86,92,82)},
}
function K.block(parent,name,cf,size,mat)
 local p=Instance.new("Part") p.Name=name p.Anchored=true p.Size=size p.CFrame=cf
 local m=K.MAT[mat or "alloy"] p.Material=m[1] p.Color=m[2] p.TopSurface=Enum.SurfaceType.Smooth p.BottomSurface=Enum.SurfaceType.Smooth
 if mat=="light" then p.CastShadow=false end
 p.Parent=parent return p end
-- clone a library mesh, size it exactly, place its centre at cf
function K.mesh(parent,name,cf,size)
 local src=lib:FindFirstChild(name) assert(src,name)
 local m=src:Clone() m.Anchored=true
 if m:IsA("BasePart") then m.Size=size m.CFrame=cf
 else local ocf,os=m:GetBoundingBox() local k=size.Y/os.Y m:ScaleTo(m:GetScale()*k) m:PivotTo(cf*(ocf:Inverse()*m:GetPivot())) end
 m.Parent=parent return m end
-- clone any model from a source (keeps its own scale), bottom-centre on ground point, yaw
function K.model(parent,src,pos,yaw,scale)
 local m=src:Clone() if scale and scale~=1 then m:ScaleTo(m:GetScale()*scale) end
 local cf,s=m:GetBoundingBox()
 local target=CFrame.new(pos+Vector3.new(0,s.Y/2,0))*CFrame.Angles(0,math.rad(yaw or 0),0)
 m:PivotTo(target*(cf:Inverse()*m:GetPivot()))
 for _,p in ipairs(m:GetDescendants()) do if p:IsA("BasePart") then p.Anchored=true end end
 m.Parent=parent return m end
function K.ground(x,z)
 local rp=RaycastParams.new() rp.FilterType=Enum.RaycastFilterType.Include rp.FilterDescendantsInstances={workspace.Terrain}
 local r=workspace:Raycast(Vector3.new(x,400,z),Vector3.new(0,-700,0),rp) return r and r.Position.Y or 0 end
K.build=build
return K

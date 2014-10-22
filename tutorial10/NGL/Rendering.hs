{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE InstanceSigs #-}

module NGL.Rendering where

import Graphics.Rendering.OpenGL as GL
import Graphics.UI.GLFW as GLFW
import Control.Monad
import Control.Applicative
import System.Exit ( exitWith, ExitCode(..) )
import Foreign.Marshal.Array
import Foreign.Ptr
import Foreign.Storable
import NGL.LoadShaders
import NGL.Shape as N
import Graphics.GLUtil


data Descriptor = Descriptor VertexArrayObject ArrayIndex NumArrayIndices

class DrawIn a where
    drawIn :: N.Color -> Window -> a -> IO ()
instance DrawIn Minimal where
    drawIn = draw
instance DrawIn [Minimal] where
    drawIn :: N.Color -> Window -> [Minimal] -> IO ()
    drawIn wc win ds = draw wc win (fromDrawables ds)
            where
               fromDrawables ds = (concat $ map fst ds, concat $ map snd ds)


draw :: N.Color -> Window -> Minimal -> IO ()
draw clr win xs = do
    descriptor <- initResources xs
    onDisplay clr win descriptor

bufferOffset :: Integral a => a -> Ptr b
bufferOffset = plusPtr nullPtr . fromIntegral


loadTex :: FilePath -> IO TextureObject
loadTex f = do t <- either error id <$> readTexture f
               textureFilter Texture2D $= ((Linear', Nothing), Linear')
               texture2DWrap $= (Repeated, ClampToEdge)
               return t

initResources :: ([Color4 Float],[Vertex4 Float]) -> IO Descriptor
initResources (cs, vs) = do
    triangles <- genObjectName
    bindVertexArrayObject $= Just triangles
    
    --
    -- Declaring VBO: vertices
    --
    let vertices = vs
        numVertices = length vertices
   
    vertexBuffer <- genObjectName
    bindBuffer ArrayBuffer $= Just vertexBuffer
    withArray vs $ \ptr -> do
        let size = fromIntegral (numVertices * sizeOf (head vs))
        bufferData ArrayBuffer $= (size, ptr, StaticDraw)

    let firstIndex = 0
        vPosition = AttribLocation 0
    vertexAttribPointer vPosition $=
        (ToFloat, VertexArrayDescriptor 4 Float 0 (bufferOffset firstIndex))
    vertexAttribArray vPosition $= Enabled

    --
    -- Declaring VBO: colors
    --
    let rgba = cs
    
    colorBuffer <- genObjectName
    bindBuffer ArrayBuffer $= Just colorBuffer
    withArray rgba $ \ptr -> do
        let size = fromIntegral (numVertices * sizeOf (head rgba))
        bufferData ArrayBuffer $= (size, ptr, StaticDraw)    
    
    let firstIndex = 0
        vertexColor = AttribLocation 1
    vertexAttribPointer vertexColor $=
        (ToFloat, VertexArrayDescriptor 4 Float 0 (bufferOffset firstIndex))
    vertexAttribArray vertexColor $= Enabled

    --
    -- Declaring VBO: UVs
    --
    let uvs = toUVs ps -- temporary hack, replace with argument call
            where ps = [(1.0, 1.0),( 0.0, 1.0),( 0.0, 0.0)
                       ,(1.0, 1.0),( 0.0, 0.0),( 1.0, 0.0)]::Points

    textureBuffer <- genObjectName
    bindBuffer ArrayBuffer $= Just textureBuffer
    withArray uvs $ \ptr -> do
        let size = fromIntegral (numVertices * sizeOf (head uvs))
        bufferData ArrayBuffer $= (size, ptr, StaticDraw)
    let firstIndex = 0
        uvCoords = AttribLocation 2
    vertexAttribPointer uvCoords $=
        (ToFloat, VertexArrayDescriptor 2 Float 0 (bufferOffset firstIndex))
    vertexAttribArray uvCoords $= Enabled 
    
    tex <- loadTex "test.png"
    texture Texture2D $= Enabled
    activeTexture $= TextureUnit 0
    textureBinding Texture2D $= Just tex    

    program <- loadShaders [
        ShaderInfo VertexShader (FileSource "Shaders/triangles.vert"),
        ShaderInfo FragmentShader (FileSource "Shaders/triangles.frac")]
    currentProgram $= Just program
    
    return $ Descriptor triangles firstIndex (fromIntegral numVertices)


keyPressed :: GLFW.KeyCallback 
keyPressed win GLFW.Key'Escape _ GLFW.KeyState'Pressed _ = shutdown win
keyPressed _   _               _ _                     _ = return ()


shutdown :: GLFW.WindowCloseCallback
shutdown win = do
  GLFW.destroyWindow win
  GLFW.terminate
  _ <- exitWith ExitSuccess
  return ()


resizeWindow :: GLFW.WindowSizeCallback
resizeWindow win w h =
    do
      GL.viewport   $= (GL.Position 0 0, GL.Size (fromIntegral w) (fromIntegral h))
      GL.matrixMode $= GL.Projection
      GL.loadIdentity
      GL.ortho2D 0 (realToFrac w) (realToFrac h) 0


createWindow :: String -> (Int, Int) -> IO GLFW.Window
createWindow title (sizex,sizey) = do
    GLFW.init
    GLFW.defaultWindowHints
    Just win <- GLFW.createWindow sizex sizey title Nothing Nothing
    GLFW.makeContextCurrent (Just win)
    GLFW.setWindowSizeCallback win (Just resizeWindow)
    GLFW.setKeyCallback win (Just keyPressed)
    GLFW.setWindowCloseCallback win (Just shutdown)
    return win


closeWindow :: GLFW.Window -> IO ()
closeWindow win = do
    GLFW.destroyWindow win
    GLFW.terminate


onDisplay :: N.Color -> GLFW.Window -> Descriptor -> IO ()
onDisplay clr win descriptor@(Descriptor triangles firstIndex numVertices) = do
  GL.clearColor $= getColor clr
  GL.clear [ColorBuffer]
  bindVertexArrayObject $= Just triangles
  drawArrays Triangles firstIndex numVertices
  GLFW.swapBuffers win

  forever $ do
     GLFW.pollEvents
     onDisplay clr win descriptor

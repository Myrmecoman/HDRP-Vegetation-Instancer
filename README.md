# Unity GPU Vegetation Instancer for HDRP and URP

![Presentation](./ReadmeImages/presentation.png?raw=true "Presentation")
![Presentation2](./ReadmeImages/presentation2.png?raw=true "Presentation2")
![Presentation3](./ReadmeImages/gif.gif?raw=true "Presentation3")

## Overview

The vegetation instancer is a unity project whose goal is to bring vegetation details into unity terrains. All objects are proceduraly placed on the terrain without requiring any data saving. This makes the project very lightweight. Assets (like ferns) come from the Unity HDRP Terrain tools. Although the provided shaders work with HDRP, this project can work with URP as long as you provide your own shaders. To generate your shaders, see "How to get GPU indirect instancing capable shaders ?".   

It consists in 3 main scripts :   

- VegetationManager.cs : this script sets up the terrain data required for full GPU positioning. There can only be one instance of it, and is used by all the VegetationInstancers.   

- VegetationInstancer.cs : in charge of displaying large amounts of vegetation (up to millions) using any shader implementing GPU indirect instancing rendering. Everything from positioning, texture mapping, slope etc, is done on the GPU, leading to almost 0 CPU charge.   

- ShaderConverter.cs : allows to convert any shader into a GPU instancing capable shader. Attention : this only works with .shader files, not with shader graphs. However you can generate such file with your shader graph by selecting it, clicking "Copy Shader", and pasting this code into an empty .shader file.    

Note that this project only spawns vegetation objects without colliders, and is reserved for small objects to populate your world.   

## Import Vegetation Instancer to your project

Import in a new HDRP project (advised before importing to an existing project) :    

- Download the .unitypackage file.   
- Create an empty HDRP project.   
- Drag the VegetationInstancer.unitypackage file inside the new HDRP project.   
- Follow the instructions in the PDF documentation provided.  

Import in an existing project with megaworld (only works for megaworld 2.3 and later version) :    

- Download the repository.   
- Drag the folder VegetationInstancer/Assets/VegetationInstancer in your project.    
- Make sure to install the **Burst** package and the **Collections** package if they are not installed already.   

## How to use

The documentation PDF file is included in the project.    
Additionaly you can see it on this page : https://docs.google.com/document/d/1z-tnjB9TRnWCRJ2o-AAlGLZsNXd_zbJwtEbFgVhQEaw/edit?usp=sharing    

## In the futur

Support large objects with colliders ?   

## Futur support

Developpement of this asset is currently halted. You can still ask me for more infos on how it works if you plan to fork and expand it's features though.

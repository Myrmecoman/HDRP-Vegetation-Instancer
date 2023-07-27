# HDRP-Vegetation-Instancer

## Overview

HDRP vegetation instancer is a unity project whose goal is to bring vegetation details into unity terrains. All objects are proceduraly placed on the terrain without requiring any data saving. This makes the project very lightweight.

It consists in 2 main scripts :

- GrassInstancer.cs :      in charge of displaying large amounts of grass (up to millions) using a custom shader and GPU indirect rendering.
- VegetationInstancer.cs : in charge of displaying lower amounts of larger vegetation objects (ferns, bushes, etc...). This one works with any shader as long as GPU instancing is enabled, but is less optimized and can therefore work with fewer instances (about 10000).

Note that this project only spawns vegetation objects without colliders at the moment.

## Code explaination

GrassInstancer and VegetationInstancer both use the same code to generate the objects positions at runtime using burst.   
The positions are not constantly regenerated, but only if a new chunk enters the camera frustrum. Finding new chunks is done in PickVisibleChunkJob.cs. Due to this, no CPU computation is required when the camera does not move. When a new chunk enters the camera view, all positions inside it are generated in a dedicated burst job (PositionsJob.cs).   
TerrainHeight.cs and TerrainsTextures.cs are used to sample the terrain in efficiently using Native unmanaged containers.

All the code is commented and was made to be easily readable.

## Work in progress

GrassInstancer displays the material as pitch black at the moment. The shader probably has a bug.   
Implement falloff.   
Support multiple objects instantiation for VegetationInstancer.cs.
